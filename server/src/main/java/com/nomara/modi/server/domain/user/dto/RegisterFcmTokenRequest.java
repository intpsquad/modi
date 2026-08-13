package com.nomara.modi.server.domain.user.dto;

import jakarta.validation.constraints.NotBlank;

public record RegisterFcmTokenRequest(@NotBlank String token) {}
