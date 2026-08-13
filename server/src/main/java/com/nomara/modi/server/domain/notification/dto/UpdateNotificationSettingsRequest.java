package com.nomara.modi.server.domain.notification.dto;

import jakarta.validation.constraints.NotNull;

public record UpdateNotificationSettingsRequest(
    @NotNull Boolean allEnabled,
    @NotNull Boolean pokeEnabled,
    @NotNull Boolean scheduleDayBeforeEnabled,
    @NotNull Boolean scheduleDdayEnabled,
    @NotNull Boolean roomMemberJoinedEnabled,
    @NotNull Boolean roomMemberLeftEnabled,
    @NotNull Boolean assignedTodoAddedEnabled,
    // 🔴 **일부러 @NotNull 이 아니다**(2026-08-06). 이 필드는 V17 에서 새로 생겼는데, @NotNull 을
    // 붙이면 **아직 업데이트하지 않은 앱**이 알림 설정을 저장할 때마다 400 을 받는다. 스토어 배포는
    // 즉시 전파되지 않으므로 옛 버전이 한동안 남는다. 값이 없으면 서비스가 true(기본 켜짐)로 읽는다.
    Boolean archiveAnalysisDoneEnabled) {

  public UpdateNotificationSettingsRequest(Boolean allEnabled, Boolean pokeEnabled) {
    this(allEnabled, pokeEnabled, true, true, true, true, true, true);
  }

  /** 안 보내온 경우 기본 켜짐 — 위 필드 주석 참고. */
  public boolean archiveAnalysisDoneOrDefault() {
    return archiveAnalysisDoneEnabled == null || archiveAnalysisDoneEnabled;
  }
}
