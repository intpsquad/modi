package com.nomara.modi.server.global.exception;

import org.springframework.http.HttpStatus;

public class ConflictException extends ApiException {

  public ConflictException(String message) {
    super(HttpStatus.CONFLICT, message);
  }

  public ConflictException(String message, Throwable cause) {
    super(HttpStatus.CONFLICT, message, cause);
  }
}
