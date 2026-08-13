package com.nomara.modi.server.global.exception;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;

@RestControllerAdvice
public class GlobalExceptionHandler {

  private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

  @ExceptionHandler(ApiException.class)
  public ResponseEntity<ErrorResponse> handleApiException(ApiException e) {
    if (e.getStatus().is5xxServerError()) {
      log.warn("{}: {}", e.getClass().getSimpleName(), e.getMessage(), e);
    }
    return ResponseEntity.status(e.getStatus())
        .body(new ErrorResponse(e.getStatus().value(), e.getMessage()));
  }

  /** 업로드 용량이 spring.servlet.multipart 상한을 넘으면 톰캣이 던진다 — 500 대신 400으로 통일. */
  @ExceptionHandler(MaxUploadSizeExceededException.class)
  public ResponseEntity<ErrorResponse> handleMaxUploadSizeExceeded(
      MaxUploadSizeExceededException e) {
    return ResponseEntity.status(HttpStatus.BAD_REQUEST)
        .body(new ErrorResponse(HttpStatus.BAD_REQUEST.value(), "이미지 용량은 5MB를 넘을 수 없어요"));
  }
}
