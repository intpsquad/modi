package com.nomara.modi.server.domain.category.exception;

import com.nomara.modi.server.global.exception.NotFoundException;

public class CategoryNotFoundException extends NotFoundException {

  public CategoryNotFoundException() {
    super("카테고리를 찾을 수 없어요");
  }
}
