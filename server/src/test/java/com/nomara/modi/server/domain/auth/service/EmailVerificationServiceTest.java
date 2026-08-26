package com.nomara.modi.server.domain.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.auth.client.EmailAttachment;
import com.nomara.modi.server.domain.auth.client.EmailSender;
import com.nomara.modi.server.global.exception.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
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
 * 이메일 인증코드 발송/검증을 실제 Redis(Testcontainers)로 검증한다. Firebase Admin SDK(중복 이메일 확인)와 SMTP(발송)는 실제로 부르지
 * 않고 손으로 만든 가짜로 대체한다({@code TodoSuggestionServiceTest} 선례와 동일하게 Mockito 대신 직접 만든다). EmailSender가 없는
 * 상태(503)는 별도 클래스({@code EmailVerificationServiceUnavailableTest})에서 검증한다 — 같은 클래스에서
 * {@code @Primary} 빈을 조건부로 넣고 뺄 수 없다.
 */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class EmailVerificationServiceTest {

  @Container
  @ServiceConnection(name = "redis")
  static GenericContainer<?> redis =
      new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    // 로컬에 SPRING_MAIL_HOST/FIREBASE_CREDENTIALS_PATH가 export돼 있으면 실물 빈이 끼어들 수 있어
    // 명시적으로 끈다(minio.endpoint 방어 패턴과 동일, specs/OPEN.md #26 참고).
    registry.add("spring.mail.host", () -> "false");
    registry.add("firebase.credentials-path", () -> "false");
  }

  static class RecordingEmailSender implements EmailSender {
    String lastTo;
    String lastPlainText;
    String lastHtml;

    @Override
    public void send(String to, String subject, String plainText, String html) {
      this.lastTo = to;
      this.lastPlainText = plainText;
      this.lastHtml = html;
    }

    @Override
    public void sendNotification(
        String to, String subject, String plainText, EmailAttachment attachment) {
      // 인증코드는 이 경로를 쓰지 않는다(팀 알림 전용, #70). 잘못 불리면 조용히 지나가지 않게 터뜨린다.
      throw new UnsupportedOperationException("인증코드는 send를 쓴다");
    }
  }

  static class StubAvailabilityChecker implements EmailAvailabilityChecker {
    boolean registered = false;

    @Override
    public boolean isRegistered(String email) {
      return registered;
    }
  }

  @TestConfiguration
  static class FakeConfig {
    @Bean
    @Primary
    RecordingEmailSender recordingEmailSender() {
      return new RecordingEmailSender();
    }

    @Bean
    @Primary
    StubAvailabilityChecker stubAvailabilityChecker() {
      return new StubAvailabilityChecker();
    }
  }

  @Autowired private EmailVerificationService service;
  @Autowired private RecordingEmailSender emailSender;

  @Autowired
  @Qualifier("stubAvailabilityChecker")
  private StubAvailabilityChecker availabilityChecker;

  private static String extractCode(String plainText) {
    return plainText.replaceAll("(?s).*인증코드: (\\d{6}).*", "$1");
  }

  @Test
  void sendingCodeCallsEmailSenderAndTheCodeVerifiesSuccessfully() {
    availabilityChecker.registered = false;

    service.sendCode("uid-send@example.com");

    assertThat(emailSender.lastTo).isEqualTo("uid-send@example.com");
    assertThat(emailSender.lastPlainText).containsPattern("\\d{6}");
    // Redis 키 포맷에 테스트를 묶지 않고, 실제로 저장됐는지는 검증 성공으로 간접 확인한다.
    service.verifyCode("uid-send@example.com", extractCode(emailSender.lastPlainText));
  }

  /** HTML 본문(2026-08-05 QA 핸드오프 적용)이 실제로 코드·로고를 담고, 치환되지 않은 플레이스홀더가 남아 있지 않은지 회귀 가드로 검증한다. */
  @Test
  void sendingCodeRendersHtmlBodyWithCodeAndInlineLogoAndNoLeftoverPlaceholders() {
    availabilityChecker.registered = false;

    service.sendCode("uid-html@example.com");

    String code = extractCode(emailSender.lastPlainText);
    assertThat(emailSender.lastHtml).contains(code);
    assertThat(emailSender.lastHtml).contains("cid:" + VerificationEmailTemplate.LOGO_CONTENT_ID);
    assertThat(emailSender.lastHtml).doesNotContain("{{");
  }

  @Test
  void sendingCodeForAlreadyRegisteredEmailThrowsConflictAndSkipsSend() {
    availabilityChecker.registered = true;
    emailSender.lastTo = null;

    ApiException ex =
        catchThrowableOfType(() -> service.sendCode("uid-dup@example.com"), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.CONFLICT);
    assertThat(emailSender.lastTo).isNull();
  }

  @Test
  void resendingWithinCooldownThrowsTooManyRequests() {
    availabilityChecker.registered = false;
    service.sendCode("uid-cooldown@example.com");

    ApiException ex =
        catchThrowableOfType(
            () -> service.sendCode("uid-cooldown@example.com"), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
  }

  @Test
  void emailIsNormalizedSoCasingCannotBypassCooldown() {
    // Firebase 이메일 조회는 대소문자를 구분하지 않고 대부분의 메일 공급자도 마찬가지다 — 정규화하지
    // 않으면 대소문자만 바꿔 같은 메일함으로 쿨다운을 우회할 수 있다(2026-07-31 리뷰 지적).
    availabilityChecker.registered = false;
    service.sendCode("Uid-Case@Example.com");

    ApiException ex =
        catchThrowableOfType(() -> service.sendCode("uid-case@example.com"), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
  }

  @Test
  void verifyingCorrectCodeSucceedsAndIsSingleUse() {
    availabilityChecker.registered = false;
    service.sendCode("uid-verify@example.com");
    String code = extractCode(emailSender.lastPlainText);

    service.verifyCode("uid-verify@example.com", code);

    ApiException ex =
        catchThrowableOfType(
            () -> service.verifyCode("uid-verify@example.com", code), ApiException.class);
    assertThat(ex.getStatus()).isEqualTo(HttpStatus.GONE);
  }

  @Test
  void verifyingWrongCodeThrowsBadRequest() {
    availabilityChecker.registered = false;
    service.sendCode("uid-wrong@example.com");

    ApiException ex =
        catchThrowableOfType(
            () -> service.verifyCode("uid-wrong@example.com", "000000"), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void verifyingWithoutSendingCodeFirstThrowsGone() {
    ApiException ex =
        catchThrowableOfType(
            () -> service.verifyCode("uid-nosend@example.com", "123456"), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.GONE);
  }

  @Test
  void fiveWrongAttemptsInvalidatesCodeForSubsequentChecks() {
    availabilityChecker.registered = false;
    service.sendCode("uid-bruteforce@example.com");
    String realCode = extractCode(emailSender.lastPlainText);
    String wrongCode = realCode.equals("000000") ? "111111" : "000000";

    for (int i = 0; i < 5; i++) {
      ApiException ex =
          catchThrowableOfType(
              () -> service.verifyCode("uid-bruteforce@example.com", wrongCode),
              ApiException.class);
      assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
    }

    // 5회를 다 썼으니 코드는 무효화됐다 — 진짜 코드를 넣어도 이제는 "코드 없음"(410)이어야 한다.
    ApiException ex =
        catchThrowableOfType(
            () -> service.verifyCode("uid-bruteforce@example.com", realCode), ApiException.class);
    assertThat(ex.getStatus()).isEqualTo(HttpStatus.GONE);
  }
}
