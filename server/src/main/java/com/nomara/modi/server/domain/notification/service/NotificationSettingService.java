package com.nomara.modi.server.domain.notification.service;

import com.nomara.modi.server.domain.notification.dto.NotificationSettingResponse;
import com.nomara.modi.server.domain.notification.dto.UpdateNotificationSettingsRequest;
import com.nomara.modi.server.domain.notification.entity.NotificationSetting;
import com.nomara.modi.server.domain.notification.repository.NotificationSettingRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** specs/0012-설정.md 알림 설정(S-40 "[계정] 알림 설정"). */
@Service
public class NotificationSettingService {

  private final NotificationSettingRepository notificationSettingRepository;
  private final UserRepository userRepository;

  public NotificationSettingService(
      NotificationSettingRepository notificationSettingRepository, UserRepository userRepository) {
    this.notificationSettingRepository = notificationSettingRepository;
    this.userRepository = userRepository;
  }

  @Transactional(readOnly = true)
  public NotificationSettingResponse getSettings(String uid) {
    return notificationSettingRepository
        .findById(uid)
        .map(NotificationSettingResponse::of)
        .orElseGet(NotificationSettingResponse::defaults);
  }

  @Transactional
  public NotificationSettingResponse updateSettings(
      String uid, String displayName, UpdateNotificationSettingsRequest request) {
    NotificationSetting settings =
        notificationSettingRepository
            .findById(uid)
            .orElseGet(() -> new NotificationSetting(ensureUser(uid, displayName)));
    settings.updateSettings(
        request.allEnabled(),
        request.pokeEnabled(),
        request.scheduleDayBeforeEnabled(),
        request.scheduleDdayEnabled(),
        request.roomMemberJoinedEnabled(),
        request.roomMemberLeftEnabled(),
        request.assignedTodoAddedEnabled(),
        // 옛 버전 앱은 이 필드를 안 보낸다 — 그때는 기본 켜짐으로 읽는다(요청 DTO 주석 참고).
        request.archiveAnalysisDoneOrDefault());
    notificationSettingRepository.save(settings);
    return NotificationSettingResponse.of(settings);
  }

  private User ensureUser(String uid, String displayName) {
    return userRepository
        .findById(uid)
        .orElseGet(
            () ->
                userRepository.save(new User(uid, displayName != null ? displayName : uid, null)));
  }
}
