package com.nomara.modi.server.domain.dashboard.dto;

import com.nomara.modi.server.domain.archive.entity.ArchiveItem;

public record ArchiveBrief(
    Long id, String title, String thumbnail, String url, boolean pinned, long likeCount) {

  public static ArchiveBrief of(ArchiveItem item, long likeCount) {
    return new ArchiveBrief(
        item.getId(),
        item.getTitle(),
        item.getThumbnail(),
        item.getUrl(),
        item.isPinned(),
        likeCount);
  }
}
