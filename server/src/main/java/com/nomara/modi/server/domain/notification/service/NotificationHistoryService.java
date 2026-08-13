package com.nomara.modi.server.domain.notification.service;

import com.nomara.modi.server.domain.notification.dto.NotificationResponse;
import com.nomara.modi.server.domain.notification.dto.UnreadCountResponse;
import com.nomara.modi.server.domain.notification.entity.Notification;
import com.nomara.modi.server.domain.notification.repository.NotificationRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.global.notification.PushType;
import java.time.Instant;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 알림 내역(specs/0017-알림-내역.md, S-41) — 기록·조회·읽음 처리. */
@Service
public class NotificationHistoryService {

  private static final Logger log = LoggerFactory.getLogger(NotificationHistoryService.class);

  /** 목록 조회 상한 — 페이지네이션 없이 최신 N건만(다른 목록 API들과 같은 패턴, home-activity-feed의 20건 캡과 동일 근거). */
  private static final int LIST_LIMIT = 100;

  private final NotificationRepository notificationRepository;

  public NotificationHistoryService(NotificationRepository notificationRepository) {
    this.notificationRepository = notificationRepository;
  }

  /**
   * {@code PushNotifier}가 발송 게이트를 통과시킨 직후 호출한다 — FCM 발송 성공 여부와 무관하게 기록한다. 부가 기록이 주 발송을 막으면 안 되므로
   * 예외를 삼키고 로그만 남긴다({@code PushNotifier.send}와 같은 원칙).
   */
  @Transactional
  public void record(User target, PushType type, Room room, String title, String body) {
    try {
      notificationRepository.save(new Notification(target, room, type, title, body));
    } catch (RuntimeException e) {
      log.warn("알림 내역 기록 실패: userId={} type={}", target.getId(), type, e);
    }
  }

  @Transactional(readOnly = true)
  public List<NotificationResponse> list(String userId) {
    return notificationRepository
        .findByUserIdOrderByCreatedAtDesc(userId, PageRequest.of(0, LIST_LIMIT))
        .stream()
        .map(NotificationResponse::of)
        .toList();
  }

  @Transactional(readOnly = true)
  public UnreadCountResponse unreadCount(String userId) {
    return new UnreadCountResponse(notificationRepository.countByUserIdAndReadAtIsNull(userId));
  }

  @Transactional
  public void markAllRead(String userId) {
    notificationRepository.markAllRead(userId, Instant.now());
  }
}
