package com.nomara.modi.server.domain.archive.exception;

import com.nomara.modi.server.global.exception.NotFoundException;

public class ArchiveItemNotFoundException extends NotFoundException {

  public ArchiveItemNotFoundException() {
    super("자료를 찾을 수 없어요");
  }
}
