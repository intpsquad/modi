package com.nomara.modi.server.domain.archive.dto;

import com.nomara.modi.server.domain.archive.entity.ArchiveItemComment;
import com.nomara.modi.server.domain.room.dto.MemberBriefResponse;
import java.time.Instant;

/**
 * 자료 상세 댓글 한 건(docs/backend/archive-comments-handoff.md). {@code author}는 탈퇴한 작성자면 {@code
 * null}이다({@code MemberBriefResponse.of}가 흡수 — {@code ArchiveItemDetailResponse.createdBy}와 같은 패턴).
 */
public record ArchiveCommentResponse(
    Long id, MemberBriefResponse author, String body, Instant createdAt) {

  public static ArchiveCommentResponse of(ArchiveItemComment comment) {
    return new ArchiveCommentResponse(
        comment.getId(),
        MemberBriefResponse.of(comment.getAuthor()),
        comment.getBody(),
        comment.getCreatedAt());
  }
}
