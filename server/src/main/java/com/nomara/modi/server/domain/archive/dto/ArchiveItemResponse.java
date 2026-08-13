package com.nomara.modi.server.domain.archive.dto;

import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import java.time.Instant;
import java.util.List;

public record ArchiveItemResponse(
    Long id,
    String title,
    String url,
    String source,
    String thumbnail,
    /** 폴더 직접 업로드 이미지 자료(V28)의 원본 URL — link/text 자료는 null. */
    String imageUrl,
    boolean pinned,
    Instant createdAt,
    List<String> tags,
    long likeCount,
    String crawlStatus) {

  public static ArchiveItemResponse of(ArchiveItem item, List<String> tags, long likeCount) {
    return new ArchiveItemResponse(
        item.getId(),
        item.getTitle(),
        item.getUrl(),
        item.getSource(),
        item.getThumbnail(),
        item.getImageUrl(),
        item.isPinned(),
        item.getCreatedAt(),
        tags,
        likeCount,
        item.getCrawlStatus().name());
  }
}
