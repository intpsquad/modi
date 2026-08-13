package com.nomara.modi.server.domain.user.dto;

import jakarta.validation.constraints.NotBlank;

public record UpdateProfileRequest(@NotBlank String nickname, String profileImage) {}
