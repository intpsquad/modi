package com.nomara.modi.server.domain.feedback.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.auth.client.EmailAttachment;
import com.nomara.modi.server.domain.auth.client.EmailSender;
import com.nomara.modi.server.domain.feedback.dto.FeedbackResponse;
import com.nomara.modi.server.domain.feedback.entity.FeedbackType;
import com.nomara.modi.server.domain.feedback.repository.FeedbackRepository;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.time.Duration;
import java.util.Arrays;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/** 알림 메일(#70)은 <b>부가물</b>이라는 계약을 고정한다 — 메일이 어떻게 되든 제출은 살아남아야 한다. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class FeedbackNotificationTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    registry.add("minio.endpoint", () -> "false");
    registry.add("feedback.notify-to", () -> "team@example.com");
  }

  private static final byte[] PNG_BYTES = {
    (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02
  };

  /** 발송을 기록하고, {@code failing=true}면 실제 SMTP처럼 예외를 던진다. */
  static class RecordingEmailSender implements EmailSender {
    boolean failing;
    String lastTo;
    String lastSubject;
    String lastPlainText;
    EmailAttachment lastAttachment;
    int sendCount;

    @Override
    public void send(String to, String subject, String plainText, String html) {
      throw new UnsupportedOperationException("피드백은 sendNotification을 쓴다");
    }

    @Override
    public void sendNotification(
        String to, String subject, String plainText, EmailAttachment attachment) {
      sendCount++;
      if (failing) {
        throw new IllegalStateException("smtp down");
      }
      this.lastTo = to;
      this.lastSubject = subject;
      this.lastPlainText = plainText;
      this.lastAttachment = attachment;
    }
  }

  static class NoopObjectStorage implements ObjectStorage {
    @Override
    public String createPresignedUploadUrl(String objectKey, Duration expiry) {
      throw new UnsupportedOperationException();
    }

    @Override
    public void put(String objectKey, byte[] content, String contentType) {}

    @Override
    public String publicUrl(String objectKey) {
      return "https://minio.local/public/" + objectKey;
    }
  }

  @TestConfiguration
  static class FakesConfig {
    @Bean
    @Primary
    RecordingEmailSender recordingEmailSender() {
      return new RecordingEmailSender();
    }

    @Bean
    @Primary
    NoopObjectStorage noopObjectStorage() {
      return new NoopObjectStorage();
    }
  }

  @Autowired private FeedbackService feedbackService;
  @Autowired private FeedbackRepository feedbackRepository;
  @Autowired private RecordingEmailSender emailSender;

  @BeforeEach
  void resetSender() {
    emailSender.failing = false;
    emailSender.sendCount = 0;
    emailSender.lastAttachment = null;
  }

  @Test
  void notifiesTeamWithReplyAddressAndContent() {
    feedbackService.submit(
        "uid-1", FeedbackType.BUG, "삭제가 안 돼요", "me@example.com", "1.0.0(5)", "ios 18.2", null);

    assertThat(emailSender.lastTo).isEqualTo("team@example.com");
    assertThat(emailSender.lastSubject).contains("BUG");
    assertThat(emailSender.lastPlainText).contains("me@example.com").contains("삭제가 안 돼요");
    assertThat(emailSender.lastAttachment).isNull();
  }

  @Test
  void notifiesThatReplyIsImpossibleWhenEmailWasLeftBlank() {
    feedbackService.submit("uid-1", FeedbackType.QUESTION, "문의", null, null, null, null);

    // 팀이 "답장할 수 없는 제보"임을 메일에서 바로 알아야 한다.
    assertThat(emailSender.lastPlainText).contains("미입력");
  }

  @Test
  void attachesScreenshotBytesRatherThanALink() {
    MockMultipartFile image = new MockMultipartFile("image", "shot.png", null, PNG_BYTES);

    feedbackService.submit("uid-1", FeedbackType.BUG, "이렇게 나와요", null, null, null, image);

    assertThat(emailSender.lastAttachment).isNotNull();
    assertThat(emailSender.lastAttachment.contentType()).isEqualTo("image/png");
    assertThat(emailSender.lastAttachment.filename()).endsWith(".png").doesNotContain("/");
    assertThat(Arrays.equals(emailSender.lastAttachment.content(), PNG_BYTES)).isTrue();
  }

  @Test
  void keepsFeedbackWhenNotificationMailThrows() {
    // 🔴 이 PR의 핵심 계약 — 저장이 진실이고 메일은 부가물이다.
    emailSender.failing = true;

    FeedbackResponse response =
        feedbackService.submit("uid-1", FeedbackType.BUG, "메일이 죽어도 남아야 함", null, null, null, null);

    assertThat(emailSender.sendCount).isEqualTo(1);
    assertThat(feedbackRepository.findById(response.id())).isPresent();
    assertThat(feedbackRepository.findById(response.id()).orElseThrow().getContent())
        .isEqualTo("메일이 죽어도 남아야 함");
  }
}
