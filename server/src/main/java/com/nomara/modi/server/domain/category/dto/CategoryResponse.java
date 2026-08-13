package com.nomara.modi.server.domain.category.dto;

import com.nomara.modi.server.domain.category.entity.Category;

public record CategoryResponse(Long id, String name) {

  public static CategoryResponse of(Category category) {
    return new CategoryResponse(category.getId(), category.getName());
  }
}
