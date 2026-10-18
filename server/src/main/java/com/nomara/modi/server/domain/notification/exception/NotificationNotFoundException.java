package com.nomara.modi.server.domain.notification.exception;

import com.nomara.modi.server.global.exception.NotFoundException;

/** 없는 알림이거나 남의 알림이다 — 둘을 구분하지 않는다(남의 알림이 있는지 알려주지 않는다). */
public class NotificationNotFoundException extends NotFoundException {

  public NotificationNotFoundException() {
    super("알림을 찾을 수 없어요");
  }
}
