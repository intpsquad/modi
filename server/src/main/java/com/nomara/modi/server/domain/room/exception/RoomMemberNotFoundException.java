package com.nomara.modi.server.domain.room.exception;

import com.nomara.modi.server.global.exception.NotFoundException;

/** 다른 유저(조회 대상)가 그 방의 멤버가 아닐 때. 요청자 본인 멤버십 체크는 {@link NotRoomMemberException}(403)을 쓴다. */
public class RoomMemberNotFoundException extends NotFoundException {

  public RoomMemberNotFoundException() {
    super("멤버를 찾을 수 없어요");
  }
}
