package com.nomara.modi.server.domain.user.exception;

import com.nomara.modi.server.global.exception.NotFoundException;

public class UserNotFoundException extends NotFoundException {

  public UserNotFoundException() {
    super("유저를 찾을 수 없어요");
  }
}
