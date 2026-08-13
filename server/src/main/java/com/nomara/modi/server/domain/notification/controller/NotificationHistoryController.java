package com.nomara.modi.server.domain.notification.controller;

import com.nomara.modi.server.domain.notification.dto.NotificationResponse;
import com.nomara.modi.server.domain.notification.dto.UnreadCountResponse;
import com.nomara.modi.server.domain.notification.service.NotificationHistoryService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

/** specs/0017-알림-내역.md — S-41 알림 내역. */
@RestController
public class NotificationHistoryController {

  private final NotificationHistoryService notificationHistoryService;

  public NotificationHistoryController(NotificationHistoryService notificationHistoryService) {
    this.notificationHistoryService = notificationHistoryService;
  }

  @GetMapping("/me/notifications")
  public List<NotificationResponse> list(HttpServletRequest request) {
    return notificationHistoryService.list(uid(request));
  }

  @GetMapping("/me/notifications/unread-count")
  public UnreadCountResponse unreadCount(HttpServletRequest request) {
    return notificationHistoryService.unreadCount(uid(request));
  }

  @PostMapping("/me/notifications/read-all")
  public ResponseEntity<Void> markAllRead(HttpServletRequest request) {
    notificationHistoryService.markAllRead(uid(request));
    return ResponseEntity.status(HttpStatus.NO_CONTENT).build();
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
