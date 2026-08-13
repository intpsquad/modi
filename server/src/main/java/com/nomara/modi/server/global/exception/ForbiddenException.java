package com.nomara.modi.server.global.exception;

import org.springframework.http.HttpStatus;

public class ForbiddenException extends ApiException {

  public ForbiddenException(String message) {
    super(HttpStatus.FORBIDDEN, message);
  }

  public ForbiddenException(String message, Throwable cause) {
    super(HttpStatus.FORBIDDEN, message, cause);
  }
}
