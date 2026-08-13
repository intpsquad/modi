package com.nomara.modi.server.domain.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

public record VerifyEmailCodeRequest(@NotBlank @Email String email, @NotBlank String code) {}
