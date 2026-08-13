package com.nomara.modi.server.domain.archive.dto;

import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.room.dto.MemberBriefResponse;
import java.time.Instant;
import java.util.List;

public record ArchiveItemDetailResponse(
    Long id,
    Long folderId,
    /**
     * 이 자료가 담긴 폴더 이름(2026-08-08, S-25-B 리디자인) — 상세 화면 앱바에 쓴다. 라우트가 {@code /archive/item/:id}라 앱이 폴더
     * 이름을 넘겨받지 못하고, {@code folderId}만으로는 폴더 목록을 한 번 더 불러야 한다.
     */
    String folderName,
    String title,
    String url,
    String source,
    String thumbnail,
    /** 폴더 직접 업로드 이미지 자료(V28)의 원본 URL — link/text 자료는 null. */
    String imageUrl,
    /** 사용자가 자료에 남기는 개인 메모(2026-08-06 도입, nullable) — AI 생성물인 {@code summary}와 다르다. */
    String memo,
    /** 본문의 AI 요약. {@code null}이면 앱이 요약 영역을 감춘다(S-25-B) — 없는 것이 정상인 경우가 셋 있다(specs/0002). */
    String summary,
    String bodyText,
    boolean pinned,
    List<String> tags,
    long likeCount,
    boolean likedByMe,
    /** 댓글 수(2026-08-08, docs/backend/archive-comments-handoff.md) — 목록을 따로 안 불러도 하단 반응 바에 바로 쓴다. */
    long commentCount,
    Instant createdAt,
    String crawlStatus,
    /**
     * 이 자료를 등록한 사람(2026-08-08, S-25-B 리디자인) — 사진 우하단 아바타에 쓴다.
     *
     * <p><b>{@code null}일 수 있다.</b> 탈퇴한 사용자의 자료는 방에 남고 작성자만 지워지고({@code
     * V9__account_deletion_cascades.sql}), {@code created_by} 컬럼이 생기기 전({@code V19}) 등록분은 애초에 비어
     * 있다. 앱은 이때 아바타 자리를 통째로 비운다.
     */
    MemberBriefResponse createdBy) {

  public static ArchiveItemDetailResponse of(
      ArchiveItem item, List<String> tags, long likeCount, boolean likedByMe, long commentCount) {
    return new ArchiveItemDetailResponse(
        item.getId(),
        item.getFolder().getId(),
        item.getFolder().getName(),
        item.getTitle(),
        item.getUrl(),
        item.getSource(),
        item.getThumbnail(),
        item.getImageUrl(),
        item.getMemo(),
        item.getSummary(),
        item.getBodyText(),
        item.isPinned(),
        tags,
        likeCount,
        likedByMe,
        commentCount,
        item.getCreatedAt(),
        item.getCrawlStatus().name(),
        MemberBriefResponse.of(item.getCreatedBy()));
  }
}
