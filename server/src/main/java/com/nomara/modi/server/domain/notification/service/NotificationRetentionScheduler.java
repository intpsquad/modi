package com.nomara.modi.server.domain.notification.service;

import com.nomara.modi.server.domain.notification.repository.NotificationRepository;
import java.time.Duration;
import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 알림 내역(specs/0017-알림-내역.md)을 90일만 보관한다 — "그때 놓친 걸 확인하는 용도"라 무한 보관할 이유가 적고, {@code
 * UserActivityRetentionScheduler}(협업 캐릭터 로그)와 같은 근거로 기간을 맞췄다.
 *
 * <p>매일 한 번 도는 저빈도 정리 작업이라 {@code UserActivityRetentionScheduler}와 같은 이유로 {@code @Scheduled(cron)}을
 * 쓴다. 기본 시각(04:30 KST)은 같은 04:00 대의 {@code UserActivityRetentionScheduler}와 08:00의 일정 리마인더 배치를 피해
 * 잡았다.
 */
@Component
public class NotificationRetentionScheduler {

  private static final Logger log = LoggerFactory.getLogger(NotificationRetentionScheduler.class);

  private static final Duration RETENTION = Duration.ofDays(90);

  private final NotificationRepository notificationRepository;

  public NotificationRetentionScheduler(NotificationRepository notificationRepository) {
    this.notificationRepository = notificationRepository;
  }

  @Scheduled(cron = "${modi.notification.retention-cron:0 30 4 * * *}")
  @Transactional
  public void purgeOldNotifications() {
    Instant cutoff = Instant.now().minus(RETENTION);
    long deleted = notificationRepository.deleteByCreatedAtBefore(cutoff);
    if (deleted > 0) {
      log.info("알림 내역 90일 경과분 {}건 삭제", deleted);
    }
  }
}
