package com.nomara.modi.server.domain.notification.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.notification.dto.NotificationSettingResponse;
import com.nomara.modi.server.domain.notification.dto.UpdateNotificationSettingsRequest;
import com.nomara.modi.server.domain.notification.entity.NotificationSetting;
import com.nomara.modi.server.domain.notification.repository.NotificationSettingRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/** specs/0012-설정.md 알림 설정. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class NotificationSettingServiceTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
  }

  @Autowired private TestRestTemplate restTemplate;
  @Autowired private NotificationSettingService notificationSettingService;
  @Autowired private NotificationSettingRepository notificationSettingRepository;

  @Test
  void getSettingsReturnsDefaultsWhenNoRowExists() {
    NotificationSettingResponse response =
        notificationSettingService.getSettings("uid-settings-no-row");

    assertThat(response).isEqualTo(new NotificationSettingResponse(true, true));
    assertThat(notificationSettingRepository.existsById("uid-settings-no-row")).isFalse();
  }

  @Test
  void updateSettingsCreatesRowWhenMissing() {
    NotificationSettingResponse response =
        notificationSettingService.updateSettings(
            "uid-settings-new", "닉네임", new UpdateNotificationSettingsRequest(false, true));

    assertThat(response).isEqualTo(new NotificationSettingResponse(false, true));
    NotificationSetting saved =
        notificationSettingRepository.findById("uid-settings-new").orElseThrow();
    assertThat(saved.isAllEnabled()).isFalse();
    assertThat(saved.isPokeEnabled()).isTrue();
  }

  @Test
  void updateSettingsOverwritesExistingRow() {
    notificationSettingService.updateSettings(
        "uid-settings-existing", "닉네임", new UpdateNotificationSettingsRequest(true, true));

    notificationSettingService.updateSettings(
        "uid-settings-existing", "닉네임", new UpdateNotificationSettingsRequest(false, false));

    NotificationSettingResponse response =
        notificationSettingService.getSettings("uid-settings-existing");
    assertThat(response).isEqualTo(new NotificationSettingResponse(false, false));
  }

  @Test
  void updateSettingsPersistsEachNotificationChannel() {
    NotificationSettingResponse response =
        notificationSettingService.updateSettings(
            "uid-settings-channels",
            "닉네임",
            new UpdateNotificationSettingsRequest(
                false, true, false, true, false, true, false, true));

    assertThat(response)
        .isEqualTo(
            new NotificationSettingResponse(false, true, false, true, false, true, false, true));
    NotificationSetting saved =
        notificationSettingRepository.findById("uid-settings-channels").orElseThrow();
    assertThat(saved.isScheduleDayBeforeEnabled()).isFalse();
    assertThat(saved.isScheduleDdayEnabled()).isTrue();
    assertThat(saved.isRoomMemberJoinedEnabled()).isFalse();
    assertThat(saved.isRoomMemberLeftEnabled()).isTrue();
    assertThat(saved.isAssignedTodoAddedEnabled()).isFalse();
  }

  @Test
  void getWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.getForEntity("/me/notification-settings", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void updateWithoutAuthReturnsUnauthorized() {
    var response =
        restTemplate.exchange("/me/notification-settings", HttpMethod.PUT, null, String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }
}
