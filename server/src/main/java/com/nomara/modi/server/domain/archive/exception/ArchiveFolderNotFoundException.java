package com.nomara.modi.server.domain.archive.exception;

import com.nomara.modi.server.global.exception.NotFoundException;

public class ArchiveFolderNotFoundException extends NotFoundException {

  public ArchiveFolderNotFoundException() {
    super("폴더를 찾을 수 없어요");
  }
}
