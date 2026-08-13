package com.nomara.modi.server.domain.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.auth.client.KakaoUserClient;
import com.nomara.modi.server.domain.auth.client.KakaoUserProfile;
import com.nomara.modi.server.domain.auth.dto.KakaoLoginResponse;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.service.UserService;
import org.junit.jupiter.api.Test;

class KakaoAuthServiceTest {

  @Test
  void exchangesKakaoUserForFirebaseCustomTokenAndKeepsNickname() {
    KakaoUserClient kakaoUserClient = mock(KakaoUserClient.class);
    UserService userService = mock(UserService.class);
    FirebaseTokenIssuer tokenIssuer = mock(FirebaseTokenIssuer.class);
    KakaoAuthService service = new KakaoAuthService(kakaoUserClient, userService, tokenIssuer);
    User user = new User("kakao:1234", "카카오닉네임", null);

    when(kakaoUserClient.fetchUser("access-token"))
        .thenReturn(new KakaoUserProfile(1234L, "카카오닉네임", "https://img.kakao.test/profile.png"));
    when(userService.ensureSocialUser(
            "kakao:1234", "카카오닉네임", "https://img.kakao.test/profile.png", null))
        .thenReturn(user);
    when(tokenIssuer.issue("kakao:1234", "카카오닉네임")).thenReturn("firebase-token");

    KakaoLoginResponse response = service.login("access-token");

    assertThat(response).isEqualTo(new KakaoLoginResponse("firebase-token", "카카오닉네임"));
    verify(kakaoUserClient).fetchUser("access-token");
    verify(userService)
        .ensureSocialUser(
            eq("kakao:1234"), eq("카카오닉네임"), eq("https://img.kakao.test/profile.png"), eq(null));
  }

  @Test
  void passesKakaoEmailThroughToEnsureSocialUser() {
    // V29 — 카카오 "이메일" 동의항목이 켜져 있으면 KakaoUserProfile.email()이 채워지고, 그대로 UserService로 전달된다.
    KakaoUserClient kakaoUserClient = mock(KakaoUserClient.class);
    UserService userService = mock(UserService.class);
    FirebaseTokenIssuer tokenIssuer = mock(FirebaseTokenIssuer.class);
    KakaoAuthService service = new KakaoAuthService(kakaoUserClient, userService, tokenIssuer);
    User user = new User("kakao:5678", "닉네임", null);

    when(kakaoUserClient.fetchUser("access-token-2"))
        .thenReturn(new KakaoUserProfile(5678L, "닉네임", null, "kakao@example.com"));
    when(userService.ensureSocialUser("kakao:5678", "닉네임", null, "kakao@example.com"))
        .thenReturn(user);
    when(tokenIssuer.issue("kakao:5678", "닉네임")).thenReturn("firebase-token-2");

    service.login("access-token-2");

    verify(userService)
        .ensureSocialUser(eq("kakao:5678"), eq("닉네임"), eq(null), eq("kakao@example.com"));
  }
}
