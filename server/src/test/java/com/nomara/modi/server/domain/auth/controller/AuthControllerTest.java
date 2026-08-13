package com.nomara.modi.server.domain.auth.controller;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * {@code /auth/**}가 {@code FirebaseAuthFilter} 화이트리스트 밖에 있어 실제로 미인증 접근이 가능한지 확인하는 유일한 컨트롤러 테스트다 —
 * 다른 컨트롤러 테스트는 401만 확인할 수 있지만(실제 Firebase 토큰 없이는 인증 성공 경로를 재현할 수 없음, {@code RoomServiceTest} 참고), 이
 * 경로는 애초에 미인증이라 끝까지 태울 수 있다. 이메일 인증은 Redis를 타므로 Testcontainers Redis가 필요하다.
 */
@Testcontainers
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class AuthControllerTest {

  @Container
  @ServiceConnection(name = "redis")
  static GenericContainer<?> redis =
      new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("minio.endpoint", () -> "false");
    registry.add("firebase.credentials-path", () -> "false");
    registry.add("spring.mail.host", () -> "false");
  }

  @Autowired private TestRestTemplate restTemplate;

  private ResponseEntity<String> post(String path, String body) {
    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.APPLICATION_JSON);
    return restTemplate.postForEntity(path, new HttpEntity<>(body, headers), String.class);
  }

  @Test
  void sendEmailCodeWithoutBearerTokenIsNotBlockedByFirebaseAuthFilter() {
    ResponseEntity<String> response =
        post("/auth/email/code", "{\"email\":\"uid-http@example.com\"}");

    assertThat(response.getStatusCode()).isNotEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void sendEmailCodeWithBlankEmailIsRejected() {
    ResponseEntity<String> response = post("/auth/email/code", "{\"email\":\"\"}");

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void verifyEmailCodeWithoutSendingFirstReturnsGone() {
    ResponseEntity<String> response =
        post(
            "/auth/email/code/verify",
            "{\"email\":\"uid-http-verify@example.com\",\"code\":\"123456\"}");

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.GONE);
  }
}
