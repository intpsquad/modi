package com.nomara.modi.server.domain.archive.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record CreateArchiveFolderRequest(@NotBlank @Size(min = 1, max = 20) String name) {}
