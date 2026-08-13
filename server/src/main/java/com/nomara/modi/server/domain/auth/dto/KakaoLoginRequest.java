package com.nomara.modi.server.domain.auth.dto;

import jakarta.validation.constraints.NotBlank;

public record KakaoLoginRequest(@NotBlank String accessToken) {}
