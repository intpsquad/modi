package com.nomara.modi.server.domain.user.controller;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class MeControllerTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    // 로컬에 MINIO_ENDPOINT가 export돼 있으면 컨텍스트가 못 뜬다(UserServiceTest 주석 참고) — 명시적으로 끈다.
    registry.add("minio.endpoint", () -> "false");
  }

  @Autowired private TestRestTemplate restTemplate;

  @Test
  void meWithoutBearerTokenReturnsUnauthorized() {
    ResponseEntity<String> response = restTemplate.getForEntity("/me", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void fcmTokenRegistrationWithoutBearerTokenReturnsUnauthorized() {
    ResponseEntity<String> response =
        restTemplate.exchange(
            "/me/fcm-token", org.springframework.http.HttpMethod.PUT, null, String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void getProfileWithoutBearerTokenReturnsUnauthorized() {
    ResponseEntity<String> response = restTemplate.getForEntity("/me/profile", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void updateProfileWithoutBearerTokenReturnsUnauthorized() {
    ResponseEntity<String> response =
        restTemplate.exchange(
            "/me/profile", org.springframework.http.HttpMethod.PATCH, null, String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void profilePhotoUploadUrlWithoutBearerTokenReturnsUnauthorized() {
    ResponseEntity<String> response =
        restTemplate.postForEntity("/me/profile/photo/upload-url", null, String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void withdrawWithoutBearerTokenReturnsUnauthorized() {
    ResponseEntity<String> response =
        restTemplate.exchange(
            "/me", org.springframework.http.HttpMethod.DELETE, null, String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }
}
