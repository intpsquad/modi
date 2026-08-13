package com.nomara.modi.server.domain.room.exception;

import com.nomara.modi.server.global.exception.ConflictException;

public class RoomEndedException extends ConflictException {

  public RoomEndedException() {
    super("종료된 방에는 참여할 수 없어요");
  }
}
