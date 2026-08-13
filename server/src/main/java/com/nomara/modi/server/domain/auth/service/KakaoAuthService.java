package com.nomara.modi.server.domain.auth.service;

import com.nomara.modi.server.domain.auth.client.KakaoUserClient;
import com.nomara.modi.server.domain.auth.client.KakaoUserProfile;
import com.nomara.modi.server.domain.auth.dto.KakaoLoginResponse;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.service.UserService;
import com.nomara.modi.server.global.exception.BadRequestException;
import org.springframework.stereotype.Service;

@Service
public class KakaoAuthService {

  private final KakaoUserClient kakaoUserClient;
  private final UserService userService;
  private final FirebaseTokenIssuer firebaseTokenIssuer;

  public KakaoAuthService(
      KakaoUserClient kakaoUserClient,
      UserService userService,
      FirebaseTokenIssuer firebaseTokenIssuer) {
    this.kakaoUserClient = kakaoUserClient;
    this.userService = userService;
    this.firebaseTokenIssuer = firebaseTokenIssuer;
  }

  public KakaoLoginResponse login(String accessToken) {
    if (accessToken == null || accessToken.isBlank()) {
      throw new BadRequestException("카카오 access token이 필요합니다.");
    }

    KakaoUserProfile profile = kakaoUserClient.fetchUser(accessToken);
    String firebaseUid = "kakao:" + profile.id();
    User user =
        userService.ensureSocialUser(
            firebaseUid, profile.nickname(), profile.profileImage(), profile.email());
    String firebaseToken = firebaseTokenIssuer.issue(firebaseUid, user.getNickname());
    return new KakaoLoginResponse(firebaseToken, user.getNickname());
  }
}
