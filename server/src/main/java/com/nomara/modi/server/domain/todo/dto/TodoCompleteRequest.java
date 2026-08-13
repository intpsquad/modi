package com.nomara.modi.server.domain.todo.dto;

import jakarta.validation.constraints.NotNull;

public record TodoCompleteRequest(@NotNull Boolean completed) {}
