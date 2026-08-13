package com.nomara.modi.server.domain.todo.dto;

import com.nomara.modi.server.domain.room.dto.MemberBriefResponse;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.user.entity.User;
import java.time.Instant;

/**
 * 모아보기 "이미지" 탭 셀 하나(2026-08-09, docs/backend/todo-image-archive-handoff.md) — 투두에 첨부된 사진.
 *
 * <p>투두 1개당 사진 1장이라 {@code id}는 곧 {@code todoId}다 — 별도 이미지 테이블을 두지 않는다.
 */
public record TodoImageResponse(
    Long id,
    String imageUrl,
    Long todoId,
    String todoTitle,
    /** 대표 담당자 1명 — 미지정 투두면 {@code null}. 담당자가 여럿이면 {@code userId} 오름차순 첫 번째(결정론용 근거일 뿐 우선순위 아님). */
    MemberBriefResponse assignee,
    boolean pinned,
    Instant createdAt) {

  public static TodoImageResponse of(Todo todo, User representativeAssignee) {
    return new TodoImageResponse(
        todo.getId(),
        todo.getImageUrl(),
        todo.getId(),
        todo.getTitle(),
        MemberBriefResponse.of(representativeAssignee),
        todo.isImagePinned(),
        todo.getImageAttachedAt());
  }
}
