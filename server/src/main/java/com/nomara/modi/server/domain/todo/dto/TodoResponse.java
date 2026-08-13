package com.nomara.modi.server.domain.todo.dto;

import com.nomara.modi.server.domain.todo.entity.Todo;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

public record TodoResponse(
    Long id,
    String title,
    String detail,
    boolean completed,
    Instant createdAt,
    Instant completedAt,
    Long categoryId,
    List<AssigneeBrief> assignees,
    LocalDate dueDate,
    /** 첨부된 사진(2026-08-09, docs/backend/todo-image-archive-handoff.md) — 없으면 {@code null}. */
    String imageUrl,
    /** 중요 표시(2026-08-09, docs/backend/todo-form-handoff.md) — 정렬·필터엔 아직 반영되지 않는다. */
    boolean important) {

  public static TodoResponse of(Todo todo, List<AssigneeBrief> assignees) {
    Long categoryId = todo.getCategory() != null ? todo.getCategory().getId() : null;
    return new TodoResponse(
        todo.getId(),
        todo.getTitle(),
        todo.getDetail(),
        todo.isCompleted(),
        todo.getCreatedAt(),
        todo.getCompletedAt(),
        categoryId,
        assignees,
        todo.getDueDate(),
        todo.getImageUrl(),
        todo.isImportant());
  }
}
