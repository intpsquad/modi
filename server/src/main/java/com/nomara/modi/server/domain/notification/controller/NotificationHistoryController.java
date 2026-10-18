package com.nomara.modi.server.domain.notification.controller;

import com.nomara.modi.server.domain.notification.dto.NotificationResponse;
import com.nomara.modi.server.domain.notification.dto.UnreadCountResponse;
import com.nomara.modi.server.domain.notification.service.NotificationHistoryService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
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

  /** 알림 한 건 삭제(#111) — 본인 것만. 남의 것·없는 것은 404. */
  @DeleteMapping("/me/notifications/{notificationId}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void deleteNotification(@PathVariable Long notificationId, HttpServletRequest request) {
    notificationHistoryService.delete(uid(request), notificationId);
  }

  /** 알림 전체 삭제(#111) — 본인 것 전부. 앱이 확인 모달을 거친 뒤 부른다. */
  @DeleteMapping("/me/notifications")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void deleteAllNotifications(HttpServletRequest request) {
    notificationHistoryService.deleteAll(uid(request));
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
