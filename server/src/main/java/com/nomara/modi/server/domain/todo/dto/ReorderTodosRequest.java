package com.nomara.modi.server.domain.todo.dto;

import java.util.List;

/** categoryId는 "기타"(미분류)를 나타내려면 null이어야 하므로 {@code @NotNull}을 붙이지 않는다. */
public record ReorderTodosRequest(Long categoryId, List<Long> todoIds) {}
