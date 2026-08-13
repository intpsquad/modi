package com.nomara.modi.server.domain.room.exception;

import com.nomara.modi.server.global.exception.NotFoundException;

public class RoomNotFoundException extends NotFoundException {

  public RoomNotFoundException() {
    super("방을 찾을 수 없어요");
  }
}
