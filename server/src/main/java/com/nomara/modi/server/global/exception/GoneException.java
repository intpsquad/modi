package com.nomara.modi.server.global.exception;

import org.springframework.http.HttpStatus;

public class GoneException extends ApiException {

  public GoneException(String message) {
    super(HttpStatus.GONE, message);
  }

  public GoneException(String message, Throwable cause) {
    super(HttpStatus.GONE, message, cause);
  }
}
