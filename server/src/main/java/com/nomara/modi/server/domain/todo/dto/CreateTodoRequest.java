package com.nomara.modi.server.domain.todo.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.util.List;

/**
 * 2026-08-07 롤백: 미리 알림형 메타데이터(위치·태그·중요표시·사진)는 걷어냈다. {@code dueDate}만 남는데, 협업 캐릭터 판정이 마감 준수율 계산에 쓰기
 * 때문이다(specs/0006-투두-탭.md, CharacterService).
 *
 * <p>{@code imageUrl}은 2026-08-09 다시 들어왔다 — 투두 사진 첨부(1장) → 모아보기 "이미지" 탭 기획
 * (docs/backend/todo-image-archive-handoff.md). 앱이 {@code POST .../todos/image/upload-url}로 먼저 업로드해
 * 받은 {@code publicUrl}을 그대로 싣는다.
 *
 * <p>{@code important}도 같은 날 복원됐다(docs/backend/todo-form-handoff.md) — 옵션이고 기본값은 {@code false}.
 * 정렬·필터 반영은 이번 요청 범위 밖(저장·반환까지만).
 */
public record CreateTodoRequest(
    @NotBlank @Size(min = 1, max = 50) String title,
    @Size(max = 500) String detail,
    Long categoryId,
    List<String> assigneeUserIds,
    LocalDate dueDate,
    @Size(max = 1024) String imageUrl,
    boolean important) {

  /** 마감일을 보내지 않는 기존 호출부(테스트 다수)를 그대로 두기 위한 오버로드. */
  public CreateTodoRequest(
      String title, String detail, Long categoryId, List<String> assigneeUserIds) {
    this(title, detail, categoryId, assigneeUserIds, null, null, false);
  }

  /** 마감일만 보내고 사진·중요표시는 안 보내는 기존 호출부를 위한 오버로드. */
  public CreateTodoRequest(
      String title,
      String detail,
      Long categoryId,
      List<String> assigneeUserIds,
      LocalDate dueDate) {
    this(title, detail, categoryId, assigneeUserIds, dueDate, null, false);
  }

  /** 사진까지만 보내고 중요표시는 안 보내는 기존 호출부(투두 이미지 테스트 등)를 위한 오버로드. */
  public CreateTodoRequest(
      String title,
      String detail,
      Long categoryId,
      List<String> assigneeUserIds,
      LocalDate dueDate,
      String imageUrl) {
    this(title, detail, categoryId, assigneeUserIds, dueDate, imageUrl, false);
  }
}
