package com.nomara.modi.server.domain.auth.controller;

import com.nomara.modi.server.domain.auth.dto.KakaoLoginRequest;
import com.nomara.modi.server.domain.auth.dto.KakaoLoginResponse;
import com.nomara.modi.server.domain.auth.dto.SendEmailCodeRequest;
import com.nomara.modi.server.domain.auth.dto.VerifyEmailCodeRequest;
import com.nomara.modi.server.domain.auth.service.EmailVerificationService;
import com.nomara.modi.server.domain.auth.service.KakaoAuthService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/** 외부 OAuth 토큰을 Firebase 세션으로 교환하고, 이메일 자체가입 인증코드를 발송/검증하는 인증 엔드포인트. */
@RestController
public class AuthController {

  private final KakaoAuthService kakaoAuthService;
  private final EmailVerificationService emailVerificationService;

  public AuthController(
      KakaoAuthService kakaoAuthService, EmailVerificationService emailVerificationService) {
    this.kakaoAuthService = kakaoAuthService;
    this.emailVerificationService = emailVerificationService;
  }

  @PostMapping("/auth/kakao")
  public KakaoLoginResponse kakaoLogin(@Valid @RequestBody KakaoLoginRequest request) {
    return kakaoAuthService.login(request.accessToken());
  }

  @PostMapping("/auth/email/code")
  public void sendEmailCode(@Valid @RequestBody SendEmailCodeRequest request) {
    emailVerificationService.sendCode(request.email());
  }

  @PostMapping("/auth/email/code/verify")
  public void verifyEmailCode(@Valid @RequestBody VerifyEmailCodeRequest request) {
    emailVerificationService.verifyCode(request.email(), request.code());
  }
}
