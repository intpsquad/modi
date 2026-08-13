package com.nomara.modi.server.global.exception;

import org.springframework.http.HttpStatus;

public class TooManyRequestsException extends ApiException {

  public TooManyRequestsException(String message) {
    super(HttpStatus.TOO_MANY_REQUESTS, message);
  }

  public TooManyRequestsException(String message, Throwable cause) {
    super(HttpStatus.TOO_MANY_REQUESTS, message, cause);
  }
}
