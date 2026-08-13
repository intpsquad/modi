package com.nomara.modi.server.global.exception;

import org.springframework.http.HttpStatus;

/**
 * API 예외의 공통 베이스. {@code ResponseStatusException}을 대체하는 게 아니라 상태코드+메시지 조합에 타입을 입힌다 — 여전히 {@link
 * RuntimeException}이라 {@code @Transactional} 기본 롤백 규칙(unchecked 예외는 자동 롤백)은 그대로 적용된다.
 */
public abstract class ApiException extends RuntimeException {

  private final HttpStatus status;

  protected ApiException(HttpStatus status, String message) {
    super(message);
    this.status = status;
  }

  protected ApiException(HttpStatus status, String message, Throwable cause) {
    super(message, cause);
    this.status = status;
  }

  public HttpStatus getStatus() {
    return status;
  }
}
