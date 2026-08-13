package com.nomara.modi.server.domain.room.exception;

import com.nomara.modi.server.global.exception.ForbiddenException;

/** 요청자 본인이 그 방의 멤버가 아닐 때. 다른 유저의 멤버십을 조회하는 경우는 {@link RoomMemberNotFoundException}(404)를 쓴다. */
public class NotRoomMemberException extends ForbiddenException {

  public NotRoomMemberException() {
    super("이 방의 멤버가 아니에요");
  }
}
