package com.nomara.modi.server.domain.archive.dto;

import jakarta.validation.constraints.NotNull;

public record MoveItemFolderRequest(@NotNull Long folderId) {}
