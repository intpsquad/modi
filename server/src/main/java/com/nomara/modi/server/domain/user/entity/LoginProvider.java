package com.nomara.modi.server.domain.user.entity;

import com.fasterxml.jackson.annotation.JsonValue;

/**
 * 로그인 수단(마이 탭 계정 배지) — 최초 가입 시점에만 저장하고 이후 재로그인으로 덮어쓰지 않는다.
 *
 * <p>카카오는 Firebase Custom Token이라 ID 토큰의 {@code sign_in_provider} 클레임이 {@code "custom"}으로만 나와 구분이 안
 * 된다 — 유일한 카카오 진입점({@code UserService#ensureSocialUser})에서는 이 클레임을 거치지 않고 직접 {@link #KAKAO}로 고정한다.
 */
public enum LoginProvider {
  KAKAO,
  GOOGLE,
  APPLE,
  EMAIL;

  @JsonValue
  public String toJson() {
    return name().toLowerCase();
  }

  /** Firebase ID 토큰의 {@code firebase.sign_in_provider} 클레임 원본 값을 매핑한다. 모르는 값·null은 null. */
  public static LoginProvider fromFirebaseSignInProvider(String signInProvider) {
    if (signInProvider == null) {
      return null;
    }
    return switch (signInProvider) {
      case "google.com" -> GOOGLE;
      case "apple.com" -> APPLE;
      case "password" -> EMAIL;
      default -> null;
    };
  }
}
