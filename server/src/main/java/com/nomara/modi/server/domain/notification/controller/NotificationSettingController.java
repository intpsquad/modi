package com.nomara.modi.server.domain.notification.controller;

import com.nomara.modi.server.domain.notification.dto.NotificationSettingResponse;
import com.nomara.modi.server.domain.notification.dto.UpdateNotificationSettingsRequest;
import com.nomara.modi.server.domain.notification.service.NotificationSettingService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** specs/0012-설정.md — S-40 "[계정] 알림 설정". */
@RestController
public class NotificationSettingController {

  private final NotificationSettingService notificationSettingService;

  public NotificationSettingController(NotificationSettingService notificationSettingService) {
    this.notificationSettingService = notificationSettingService;
  }

  @GetMapping("/me/notification-settings")
  public NotificationSettingResponse get(HttpServletRequest request) {
    return notificationSettingService.getSettings(uid(request));
  }

  @PutMapping("/me/notification-settings")
  public NotificationSettingResponse update(
      HttpServletRequest request, @Valid @RequestBody UpdateNotificationSettingsRequest body) {
    return notificationSettingService.updateSettings(uid(request), displayName(request), body);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }

  private String displayName(HttpServletRequest request) {
    String name = (String) request.getAttribute(FirebaseAuthFilter.ATTR_NAME);
    if (name != null) {
      return name;
    }
    String email = (String) request.getAttribute(FirebaseAuthFilter.ATTR_EMAIL);
    if (email != null) {
      return email;
    }
    return uid(request);
  }
}
