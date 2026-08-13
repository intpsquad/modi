package com.nomara.modi.server.domain.notification.dto;

import com.nomara.modi.server.domain.notification.entity.NotificationSetting;

public record NotificationSettingResponse(
    boolean allEnabled,
    boolean pokeEnabled,
    boolean scheduleDayBeforeEnabled,
    boolean scheduleDdayEnabled,
    boolean roomMemberJoinedEnabled,
    boolean roomMemberLeftEnabled,
    boolean assignedTodoAddedEnabled,
    boolean archiveAnalysisDoneEnabled) {

  public NotificationSettingResponse(boolean allEnabled, boolean pokeEnabled) {
    this(allEnabled, pokeEnabled, true, true, true, true, true, true);
  }

  public static NotificationSettingResponse of(NotificationSetting setting) {
    return new NotificationSettingResponse(
        setting.isAllEnabled(),
        setting.isPokeEnabled(),
        setting.isScheduleDayBeforeEnabled(),
        setting.isScheduleDdayEnabled(),
        setting.isRoomMemberJoinedEnabled(),
        setting.isRoomMemberLeftEnabled(),
        setting.isAssignedTodoAddedEnabled(),
        setting.isArchiveAnalysisDoneEnabled());
  }

  /** 설정 행이 아직 없는 유저 — {@link NotificationSetting}의 생성자 기본값(전부 true)과 동일하게 취급한다. */
  public static NotificationSettingResponse defaults() {
    return new NotificationSettingResponse(true, true, true, true, true, true, true, true);
  }
}
