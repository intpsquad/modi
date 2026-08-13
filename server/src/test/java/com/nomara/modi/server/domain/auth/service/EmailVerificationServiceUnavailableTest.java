package com.nomara.modi.server.domain.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.global.exception.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * {@link EmailVerificationServiceTest}는 {@code EmailSender} 빈이 있는 상태(발송 성공)를 검증한다. 이 클래스는 반대로 없는
 * 상태(503)를 검증하려고 별도 클래스로 분리했다 — 같은 클래스에서 {@code @Primary} 빈을 조건부로 넣고 뺄 수 없다 ({@code
 * UserServiceProfilePhotoUploadTest}/{@code UserServiceTest} 선례와 동일 이유).
 */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class EmailVerificationServiceUnavailableTest {

  @Container
  @ServiceConnection(name = "redis")
  static GenericContainer<?> redis =
      new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.mail.host", () -> "false");
    registry.add("firebase.credentials-path", () -> "false");
  }

  static class StubAvailabilityChecker implements EmailAvailabilityChecker {
    @Override
    public boolean isRegistered(String email) {
      return false;
    }
  }

  @TestConfiguration
  static class FakeConfig {
    @Bean
    @Primary
    StubAvailabilityChecker stubAvailabilityChecker() {
      return new StubAvailabilityChecker();
    }
  }

  @Autowired private EmailVerificationService service;

  @Test
  void sendCodeThrowsServiceUnavailableWithoutEmailSenderConfigured() {
    ApiException ex =
        catchThrowableOfType(
            () -> service.sendCode("uid-nosender@example.com"), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
  }
}
