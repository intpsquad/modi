package com.nomara.modi.server.domain.todo.exception;

import com.nomara.modi.server.global.exception.NotFoundException;

public class TodoNotFoundException extends NotFoundException {

  public TodoNotFoundException() {
    super("투두를 찾을 수 없어요");
  }
}
