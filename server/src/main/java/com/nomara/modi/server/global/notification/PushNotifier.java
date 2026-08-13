package com.nomara.modi.server.global.notification;

import com.nomara.modi.server.domain.notification.entity.NotificationSetting;
import com.nomara.modi.server.domain.notification.repository.NotificationSettingRepository;
import com.nomara.modi.server.domain.notification.service.NotificationHistoryService;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.user.entity.User;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * {@code PokeService.notifyIfEnabled}(2026-07-29)에서 시작된 "설정 확인 → 토큰 확인 → 발송 → 실패 삼킴" 게이팅 로직을
 * 공용화한다(2026-08-05, 알림 트리거 6종 작업). 이 클래스가 하는 일은 오직 "보낼지 말지 판단 + 보내기"뿐이고, 언제·누구에게 보낼지는 각 도메인
 * 서비스(PokeService, RoomService, TodoService, ScheduleReminderService)가 정한다.
 *
 * <p><b>{@code allEnabled}는 개별 7종이 전부 켜졌는지를 나타내는 파생값일 뿐이다</b> — 개별을 막는 마스터 스위치가 아니다(2026-08-08 결정,
 * specs/0012-설정.md). 발송 여부는 각 {@link PushType}이 매핑하는 개별 플래그만으로 판단한다. 설정 행이 없는 유저는 {@link
 * NotificationSetting}의 기본값(전부 true)과 동일하게 발송 허용으로 취급한다.
 *
 * <p><b>트랜잭션 경계</b>: 콕찌르기 선례를 그대로 따라 커밋 전에 인라인으로 발송한다 — 호출 측 트랜잭션이 이후 롤백되면 "행은 안 생겼는데 푸시만 나간" 상태가 될
 * 수 있다. 이 트레이드오프는 의도적이다(발송 자체가 실패해도 주 액션을 막지 않는 것과 같은 이유로, 부가 기능이 주 기능의 정합성을 해치지 않는 쪽을 택했다) — 커밋 후
 * 발송이 필요해지면 {@code TransactionSynchronization#afterCommit}으로 옮기는 별도 작업이 필요하다.
 */
@Component
public class PushNotifier {

  private static final Logger log = LoggerFactory.getLogger(PushNotifier.class);

  private final NotificationSettingRepository notificationSettingRepository;
  private final NotificationHistoryService notificationHistoryService;
  private final Optional<PushSender> pushSender;

  public PushNotifier(
      NotificationSettingRepository notificationSettingRepository,
      NotificationHistoryService notificationHistoryService,
      Optional<PushSender> pushSender) {
    this.notificationSettingRepository = notificationSettingRepository;
    this.notificationHistoryService = notificationHistoryService;
    this.pushSender = pushSender;
  }

  /**
   * @param room 알림이 속한 방(있으면). {@code null}이면 알림 내역(specs/0017)에 방 없이 기록된다 — 예: 자료 분석 완료 알림은 유저 단위로
   *     여러 방의 결과를 합칠 수 있어 단일 room이 없다.
   */
  public void notify(User target, PushType type, Room room, String title, String body) {
    if (!isEnabled(target.getId(), type)) {
      return;
    }
    notificationHistoryService.record(target, type, room, title, body);
    send(target, title, body, type, room);
  }

  /** 여러 대상에게 같은 문구를 보낼 때 설정을 한 번에 조회해 N+1을 피한다(방 팬아웃, 일정 리마인더 팬아웃). */
  public void notifyEach(
      Collection<User> targets, PushType type, Room room, String title, String body) {
    if (targets.isEmpty()) {
      return;
    }
    List<String> userIds = targets.stream().map(User::getId).toList();
    Map<String, NotificationSetting> settingsByUserId =
        notificationSettingRepository.findAllById(userIds).stream()
            .collect(Collectors.toMap(NotificationSetting::getId, Function.identity()));
    for (User target : targets) {
      boolean enabled =
          Optional.ofNullable(settingsByUserId.get(target.getId()))
              .map(type::isEnabled)
              .orElse(true);
      if (enabled) {
        notificationHistoryService.record(target, type, room, title, body);
        send(target, title, body, type, room);
      }
    }
  }

  private boolean isEnabled(String userId, PushType type) {
    return notificationSettingRepository.findById(userId).map(type::isEnabled).orElse(true);
  }

  private void send(User target, String title, String body, PushType type, Room room) {
    if (target.getFcmToken() == null || pushSender.isEmpty()) {
      return;
    }
    try {
      pushSender.get().send(target.getFcmToken(), title, body, data(type, room));
    } catch (Exception e) {
      log.warn("푸시 발송 실패: target={}", target.getId(), e);
    }
  }

  /**
   * 탭 시 딥링크로 쓰는 최소 데이터(2026-08-09, docs/backend/notification-deeplink-handoff.md) — {@code type}은
   * 항상, {@code roomId}는 방 컨텍스트가 있을 때만 싣는다. {@code scheduleId}/{@code todoId}/{@code archiveItemId}는
   * 문서가 스스로 "프론트 미소비"라 명시한 선택 항목이라 아직 만들지 않는다.
   */
  private Map<String, String> data(PushType type, Room room) {
    Map<String, String> data = new HashMap<>();
    data.put("type", type.name());
    if (room != null) {
      data.put("roomId", String.valueOf(room.getId()));
    }
    return data;
  }
}
