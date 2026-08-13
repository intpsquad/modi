package com.nomara.modi.server.domain.room.exception;

import com.nomara.modi.server.global.exception.NotFoundException;

public class InviteCodeNotFoundException extends NotFoundException {

  public InviteCodeNotFoundException() {
    super("코드가 없거나 만료됐어요. 방 멤버에게 새 코드를 요청하세요");
  }
}
