package com.nomara.modi.server.domain.auth.client;

public interface KakaoUserClient {

  KakaoUserProfile fetchUser(String accessToken);
}
