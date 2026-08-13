package com.nomara.modi.server.domain.todo.dto;

import com.nomara.modi.server.domain.todo.entity.Todo;
import java.time.Instant;

public record TodoBriefResponse(Long id, boolean completed, Instant completedAt) {

  public static TodoBriefResponse of(Todo todo) {
    return new TodoBriefResponse(todo.getId(), todo.isCompleted(), todo.getCompletedAt());
  }
}
