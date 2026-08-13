package com.nomara.modi.server.domain.todo.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.util.List;

/**
 * 전체 교체 방식이므로 {@code dueDate}를 보내지 않으면 마감일이 지워진다(CreateTodoRequest와 같은 롤백 근거). {@code imageUrl}·
 * {@code important}도 같은 규칙 — 안 보내면 각각 사진 해제·중요표시 해제로 반영된다(2026-08-09,
 * docs/backend/todo-image-archive-handoff.md, docs/backend/todo-form-handoff.md).
 */
public record UpdateTodoRequest(
    @NotBlank @Size(min = 1, max = 50) String title,
    @Size(max = 500) String detail,
    Long categoryId,
    List<String> assigneeUserIds,
    LocalDate dueDate,
    @Size(max = 1024) String imageUrl,
    boolean important) {

  /** 마감일을 보내지 않는 기존 호출부(테스트 다수)를 그대로 두기 위한 오버로드. */
  public UpdateTodoRequest(
      String title, String detail, Long categoryId, List<String> assigneeUserIds) {
    this(title, detail, categoryId, assigneeUserIds, null, null, false);
  }

  /** 마감일만 보내고 사진·중요표시는 안 보내는 기존 호출부를 위한 오버로드. */
  public UpdateTodoRequest(
      String title,
      String detail,
      Long categoryId,
      List<String> assigneeUserIds,
      LocalDate dueDate) {
    this(title, detail, categoryId, assigneeUserIds, dueDate, null, false);
  }

  /** 사진까지만 보내고 중요표시는 안 보내는 기존 호출부(투두 이미지 테스트 등)를 위한 오버로드. */
  public UpdateTodoRequest(
      String title,
      String detail,
      Long categoryId,
      List<String> assigneeUserIds,
      LocalDate dueDate,
      String imageUrl) {
    this(title, detail, categoryId, assigneeUserIds, dueDate, imageUrl, false);
  }
}
