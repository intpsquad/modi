package com.nomara.modi.server.domain.archive.dto;

import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;

public record ArchiveFolderResponse(Long id, String name, long itemCount, String thumbnail) {

  public static ArchiveFolderResponse of(ArchiveFolder folder, long itemCount, String thumbnail) {
    return new ArchiveFolderResponse(folder.getId(), folder.getName(), itemCount, thumbnail);
  }
}
