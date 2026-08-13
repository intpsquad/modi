package com.nomara.modi.server.domain.user.dto;

import com.nomara.modi.server.domain.user.entity.LoginProvider;
import com.nomara.modi.server.domain.user.entity.User;
import java.time.Instant;

/**
 * 마이 탭 프로필 헤더용 {@code createdAt}/{@code loginProvider} 추가 — 값이 없으면 각각 "MODI와 함께하는 중"/"연결됨" 중립 폴백을
 * 쓴다고 요청서에 명시돼 있다(프론트 처리).
 */
public record UserProfileResponse(
    String userId,
    String nickname,
    String profileImage,
    Instant createdAt,
    LoginProvider loginProvider,
    String email) {

  /** {@code /me/profile}은 요청 토큰의 uid로만 조회되는 본인 전용 응답이라 email 노출이 안전하다(다른 사용자 조회 경로 없음). */
  public static UserProfileResponse of(User user) {
    return new UserProfileResponse(
        user.getId(),
        user.getNickname(),
        user.getProfileImage(),
        user.getCreatedAt(),
        user.getLoginProvider(),
        user.getEmail());
  }
}
