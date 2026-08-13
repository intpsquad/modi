package com.nomara.modi.server.domain.notification.dto;

import com.nomara.modi.server.domain.notification.entity.Notification;
import java.time.Instant;

/** 알림 내역 한 건(specs/0017-알림-내역.md, S-41). */
public record NotificationResponse(
    Long id, String type, String title, String body, Long roomId, boolean read, Instant createdAt) {

  public static NotificationResponse of(Notification notification) {
    return new NotificationResponse(
        notification.getId(),
        notification.getType(),
        notification.getTitle(),
        notification.getBody(),
        notification.getRoom() == null ? null : notification.getRoom().getId(),
        notification.getReadAt() != null,
        notification.getCreatedAt());
  }
}
