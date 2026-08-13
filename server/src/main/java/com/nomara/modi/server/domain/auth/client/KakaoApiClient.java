package com.nomara.modi.server.domain.auth.client;

import com.nomara.modi.server.global.exception.BadGatewayException;
import com.nomara.modi.server.global.exception.UnauthorizedException;
import java.time.Duration;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

/** Kakao access token을 Kakao 사용자 정보로 검증하는 클라이언트. */
@Service
public class KakaoApiClient implements KakaoUserClient {

  private final RestClient restClient;

  @Autowired
  public KakaoApiClient(
      @Value("${modi.kakao.user-info-url:https://kapi.kakao.com/v2/user/me}") String userInfoUrl,
      @Value("${modi.kakao.connect-timeout-seconds:5}") long connectTimeoutSeconds,
      @Value("${modi.kakao.read-timeout-seconds:10}") long readTimeoutSeconds) {
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(Duration.ofSeconds(connectTimeoutSeconds));
    requestFactory.setReadTimeout(Duration.ofSeconds(readTimeoutSeconds));
    this.restClient =
        RestClient.builder().baseUrl(userInfoUrl).requestFactory(requestFactory).build();
  }

  KakaoApiClient(RestClient restClient) {
    this.restClient = restClient;
  }

  @Override
  public KakaoUserProfile fetchUser(String accessToken) {
    try {
      Map<String, Object> response =
          restClient
              .get()
              .header("Authorization", "Bearer " + accessToken)
              .retrieve()
              .body(new ParameterizedTypeReference<>() {});
      return toProfile(response);
    } catch (RestClientResponseException e) {
      if (e.getStatusCode().value() == 401 || e.getStatusCode().value() == 403) {
        throw new UnauthorizedException("카카오 access token이 유효하지 않습니다.");
      }
      throw new BadGatewayException("카카오 사용자 정보를 확인하지 못했습니다.", e);
    } catch (RestClientException e) {
      throw new BadGatewayException("카카오 인증 서버에 연결하지 못했습니다.", e);
    }
  }

  private KakaoUserProfile toProfile(Map<String, Object> response) {
    if (response == null || !(response.get("id") instanceof Number id)) {
      throw new BadGatewayException("카카오 사용자 정보 형식이 올바르지 않습니다.");
    }

    String nickname = nestedNickname(response);
    return new KakaoUserProfile(
        id.longValue(), nickname, nestedProfileImage(response), nestedEmail(response));
  }

  @SuppressWarnings("unchecked")
  private String nestedNickname(Map<String, Object> response) {
    Map<String, Object> account = asMap(response.get("kakao_account"));
    Map<String, Object> profile = account == null ? null : asMap(account.get("profile"));
    String nickname = profile == null ? null : asString(profile.get("nickname"));
    if (hasText(nickname)) {
      return nickname.trim();
    }

    Map<String, Object> properties = asMap(response.get("properties"));
    nickname = properties == null ? null : asString(properties.get("nickname"));
    return hasText(nickname) ? nickname.trim() : null;
  }

  private String nestedProfileImage(Map<String, Object> response) {
    Map<String, Object> account = asMap(response.get("kakao_account"));
    Map<String, Object> profile = account == null ? null : asMap(account.get("profile"));
    String profileImage = profile == null ? null : asString(profile.get("profile_image_url"));
    if (hasText(profileImage)) return profileImage.trim();

    Map<String, Object> properties = asMap(response.get("properties"));
    profileImage = properties == null ? null : asString(properties.get("profile_image"));
    return hasText(profileImage) ? profileImage.trim() : null;
  }

  /** V29 — email은 profile 하위가 아니라 kakao_account 바로 아래에 있고, "이메일" 동의항목이 꺼져 있으면 안 온다. */
  private String nestedEmail(Map<String, Object> response) {
    Map<String, Object> account = asMap(response.get("kakao_account"));
    String email = account == null ? null : asString(account.get("email"));
    return hasText(email) ? email.trim() : null;
  }

  @SuppressWarnings("unchecked")
  private Map<String, Object> asMap(Object value) {
    return value instanceof Map<?, ?> map ? (Map<String, Object>) map : null;
  }

  private String asString(Object value) {
    return value instanceof String string ? string : null;
  }

  private boolean hasText(String value) {
    return value != null && !value.isBlank();
  }
}
