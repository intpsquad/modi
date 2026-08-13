package com.nomara.modi.server.domain.archive.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;

public record UpdateItemTagsRequest(@NotNull List<@NotBlank @Size(max = 20) String> tags) {}
