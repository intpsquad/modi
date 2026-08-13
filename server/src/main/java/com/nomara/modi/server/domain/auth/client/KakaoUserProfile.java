package com.nomara.modi.server.domain.auth.client;

public record KakaoUserProfile(long id, String nickname, String profileImage, String email) {

  public KakaoUserProfile(long id, String nickname) {
    this(id, nickname, null, null);
  }

  public KakaoUserProfile(long id, String nickname, String profileImage) {
    this(id, nickname, profileImage, null);
  }
}
