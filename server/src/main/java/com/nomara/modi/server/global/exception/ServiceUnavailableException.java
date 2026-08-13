package com.nomara.modi.server.global.exception;

import org.springframework.http.HttpStatus;

public class ServiceUnavailableException extends ApiException {

  public ServiceUnavailableException(String message) {
    super(HttpStatus.SERVICE_UNAVAILABLE, message);
  }

  public ServiceUnavailableException(String message, Throwable cause) {
    super(HttpStatus.SERVICE_UNAVAILABLE, message, cause);
  }
}
