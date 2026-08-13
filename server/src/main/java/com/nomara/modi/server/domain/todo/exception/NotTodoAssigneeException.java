package com.nomara.modi.server.domain.todo.exception;

import com.nomara.modi.server.global.exception.ForbiddenException;

/** specs/0006-투두-탭.md FR-39 — 담당자가 있는 투두는 그 담당자만 체크/해제 가능. */
public class NotTodoAssigneeException extends ForbiddenException {

  public NotTodoAssigneeException() {
    super("본인이 담당한 투두만 체크할 수 있어요");
  }
}
