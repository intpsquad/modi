package com.nomara.modi.server.global.notification;

import com.nomara.modi.server.domain.notification.entity.NotificationSetting;
import java.util.function.Predicate;

/**
 * 발송 트리거 종류 — {@link NotificationSetting}의 개별 채널 게터에 매핑한다. 이름은 앱이 주고받는 알림 설정 JSON 필드명(예: {@code
 * pokeEnabled})과 1:1로 맞춘다 — 앱에 별도 공유 enum이 없어 이 필드명이 유일한 명명 선례다.
 */
public enum PushType {
  POKE(NotificationSetting::isPokeEnabled),
  SCHEDULE_DAY_BEFORE(NotificationSetting::isScheduleDayBeforeEnabled),
  SCHEDULE_DDAY(NotificationSetting::isScheduleDdayEnabled),
  ROOM_MEMBER_JOINED(NotificationSetting::isRoomMemberJoinedEnabled),
  ROOM_MEMBER_LEFT(NotificationSetting::isRoomMemberLeftEnabled),
  ASSIGNED_TODO_ADDED(NotificationSetting::isAssignedTodoAddedEnabled),
  /** 자료 분석 완료·실패(2026-08-06). 등록한 본인에게만 간다 — 방 전체에 보내면 남의 링크 알림까지 온다. */
  ARCHIVE_ANALYSIS_DONE(NotificationSetting::isArchiveAnalysisDoneEnabled);

  private final Predicate<NotificationSetting> enabled;

  PushType(Predicate<NotificationSetting> enabled) {
    this.enabled = enabled;
  }

  public boolean isEnabled(NotificationSetting setting) {
    return enabled.test(setting);
  }
}
