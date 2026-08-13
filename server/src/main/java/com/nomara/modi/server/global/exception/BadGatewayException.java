package com.nomara.modi.server.global.exception;

import org.springframework.http.HttpStatus;

public class BadGatewayException extends ApiException {

  public BadGatewayException(String message) {
    super(HttpStatus.BAD_GATEWAY, message);
  }

  public BadGatewayException(String message, Throwable cause) {
    super(HttpStatus.BAD_GATEWAY, message, cause);
  }
}
