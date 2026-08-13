package com.nomara.modi.server.domain.archive.exception;

import com.nomara.modi.server.global.exception.ForbiddenException;

/** 댓글 수정·삭제는 작성자 본인만 — 탈퇴한 작성자(author null)의 댓글은 아무도 고칠 수 없다. */
public class NotCommentAuthorException extends ForbiddenException {

  public NotCommentAuthorException() {
    super("본인이 작성한 댓글만 수정할 수 있어요");
  }
}
