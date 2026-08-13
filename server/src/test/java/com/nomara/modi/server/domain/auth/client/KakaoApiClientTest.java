package com.nomara.modi.server.domain.auth.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.nomara.modi.server.global.exception.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class KakaoApiClientTest {

  @Test
  void fetchesNicknameFromKakaoAccountProfile() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://kakao.test/v2/user/me");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    KakaoApiClient client = new KakaoApiClient(builder.build());

    server
        .expect(requestTo("http://kakao.test/v2/user/me"))
        .andExpect(header(HttpHeaders.AUTHORIZATION, "Bearer kakao-access-token"))
        .andRespond(
            withSuccess(
                """
                {
                  "id": 1234,
                  "kakao_account": {
                    "profile": {
                      "nickname": "카카오닉네임",
                      "profile_image_url": "https://img.kakao.test/profile.png"
                    }
                  }
                }
                """,
                MediaType.APPLICATION_JSON));

    KakaoUserProfile profile = client.fetchUser("kakao-access-token");

    assertThat(profile)
        .isEqualTo(new KakaoUserProfile(1234L, "카카오닉네임", "https://img.kakao.test/profile.png"));
    server.verify();
  }

  @Test
  void fetchesEmailFromKakaoAccountWhenConsentWasGranted() {
    // V29 — kakao_account.email은 profile 하위가 아니라 kakao_account 바로 아래에 온다.
    RestClient.Builder builder = RestClient.builder().baseUrl("http://kakao.test/v2/user/me");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    KakaoApiClient client = new KakaoApiClient(builder.build());

    server
        .expect(requestTo("http://kakao.test/v2/user/me"))
        .andRespond(
            withSuccess(
                """
                {
                  "id": 1234,
                  "kakao_account": {
                    "email": "kakao@example.com",
                    "profile": {"nickname": "카카오닉네임"}
                  }
                }
                """,
                MediaType.APPLICATION_JSON));

    assertThat(client.fetchUser("kakao-access-token").email()).isEqualTo("kakao@example.com");
    server.verify();
  }

  @Test
  void returnsNullEmailWhenConsentWasNotGranted() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://kakao.test/v2/user/me");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    KakaoApiClient client = new KakaoApiClient(builder.build());

    server
        .expect(requestTo("http://kakao.test/v2/user/me"))
        .andRespond(
            withSuccess(
                """
                {"id": 1234, "kakao_account": {"email_needs_agreement": true}}
                """,
                MediaType.APPLICATION_JSON));

    assertThat(client.fetchUser("kakao-access-token").email()).isNull();
    server.verify();
  }

  @Test
  void returnsNullNicknameWhenConsentWasNotGranted() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://kakao.test/v2/user/me");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    KakaoApiClient client = new KakaoApiClient(builder.build());

    server
        .expect(requestTo("http://kakao.test/v2/user/me"))
        .andRespond(
            withSuccess(
                """
                {"id": 1234, "kakao_account": {"profile_nickname_needs_agreement": true}}
                """,
                MediaType.APPLICATION_JSON));

    assertThat(client.fetchUser("kakao-access-token").nickname()).isNull();
    server.verify();
  }

  @Test
  void mapsInvalidKakaoTokenToUnauthorized() {
    RestClient.Builder builder = RestClient.builder().baseUrl("http://kakao.test/v2/user/me");
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    KakaoApiClient client = new KakaoApiClient(builder.build());

    server
        .expect(requestTo("http://kakao.test/v2/user/me"))
        .andRespond(withStatus(HttpStatus.UNAUTHORIZED));

    assertThatThrownBy(() -> client.fetchUser("invalid-token"))
        .isInstanceOf(ApiException.class)
        .extracting("status")
        .isEqualTo(HttpStatus.UNAUTHORIZED);
    server.verify();
  }
}
