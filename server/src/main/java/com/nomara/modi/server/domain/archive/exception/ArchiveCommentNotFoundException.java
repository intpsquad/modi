package com.nomara.modi.server.domain.archive.exception;

import com.nomara.modi.server.global.exception.NotFoundException;

public class ArchiveCommentNotFoundException extends NotFoundException {

  public ArchiveCommentNotFoundException() {
    super("댓글을 찾을 수 없어요");
  }
}
