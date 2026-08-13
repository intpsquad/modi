package com.nomara.modi.server.domain.archive.dto;

import java.util.List;

public record ArchiveFolderItemsResponse(
    Long folderId, String folderName, List<ArchiveItemResponse> items) {}
