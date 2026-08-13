package com.nomara.modi.server.global.exception;

import org.springframework.http.HttpStatus;

public class NotFoundException extends ApiException {

  public NotFoundException(String message) {
    super(HttpStatus.NOT_FOUND, message);
  }

  public NotFoundException(String message, Throwable cause) {
    super(HttpStatus.NOT_FOUND, message, cause);
  }
}
