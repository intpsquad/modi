package com.nomara.modi.server.domain.category.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record UpdateCategoryRequest(@NotBlank @Size(min = 1, max = 20) String name) {}
