package com.nomara.modi.server.domain.feedback.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.feedback.dto.FeedbackResponse;
import com.nomara.modi.server.domain.feedback.entity.Feedback;
import com.nomara.modi.server.domain.feedback.entity.FeedbackType;
import com.nomara.modi.server.domain.feedback.repository.FeedbackRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.time.Duration;
import java.util.Arrays;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/**
 * {@code RoomCoverImageServiceTest}와 같은 패턴 — 실물 MinIO 대신 기록용 가짜 {@link ObjectStorage}를
 * {@code @Primary}로 꽂는다.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class FeedbackServiceTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    registry.add("minio.endpoint", () -> "false");
  }

  private static final byte[] PNG_BYTES = {
    (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02
  };

  static class RecordingObjectStorage implements ObjectStorage {
    String lastObjectKey;
    byte[] lastContent;
    String lastContentType;

    @Override
    public String createPresignedUploadUrl(String objectKey, Duration expiry) {
      throw new UnsupportedOperationException();
    }

    @Override
    public void put(String objectKey, byte[] content, String contentType) {
      this.lastObjectKey = objectKey;
      this.lastContent = content;
      this.lastContentType = contentType;
    }

    @Override
    public String publicUrl(String objectKey) {
      return "https://minio.local/public/" + objectKey;
    }
  }

  @TestConfiguration
  static class FakeObjectStorageConfig {
    @Bean
    @Primary
    RecordingObjectStorage recordingObjectStorage() {
      return new RecordingObjectStorage();
    }
  }

  @Autowired private FeedbackService feedbackService;
  @Autowired private FeedbackRepository feedbackRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private RecordingObjectStorage objectStorage;

  @Test
  void submitStoresFeedbackWithoutImage() {
    userRepository.save(new User("uid-writer", "예원", null));

    FeedbackResponse response =
        feedbackService.submit(
            "uid-writer",
            FeedbackType.BUG,
            "  아카이브 삭제가 안 돼요  ",
            "me@example.com",
            "1.0.0(5)",
            "ios 18.2",
            null);

    assertThat(response.id()).isNotNull();
    assertThat(response.createdAt()).isNotNull();

    Feedback saved = feedbackRepository.findById(response.id()).orElseThrow();
    assertThat(saved.getType()).isEqualTo(FeedbackType.BUG);
    // 앞뒤 공백은 잘라 저장한다.
    assertThat(saved.getContent()).isEqualTo("아카이브 삭제가 안 돼요");
    assertThat(saved.getReplyEmail()).isEqualTo("me@example.com");
    assertThat(saved.getAppVersion()).isEqualTo("1.0.0(5)");
    assertThat(saved.getDeviceInfo()).isEqualTo("ios 18.2");
    assertThat(saved.getImageKey()).isNull();
    assertThat(saved.getUser().getId()).isEqualTo("uid-writer");
  }

  @Test
  void submitStoresScreenshotUnderPrivateFeedbackPrefix() {
    MockMultipartFile image = new MockMultipartFile("image", "shot.png", null, PNG_BYTES);

    FeedbackResponse response =
        feedbackService.submit(
            "uid-shot", FeedbackType.SUGGESTION, "이런 기능 어때요", null, null, null, image);

    // 공개 URL이 아니라 오브젝트 키만 남긴다 — feedback/* 는 버킷에서 공개로 열려 있지 않다.
    assertThat(objectStorage.lastObjectKey).startsWith("feedback/").endsWith(".png");
    assertThat(objectStorage.lastContentType).isEqualTo("image/png");
    assertThat(Arrays.equals(objectStorage.lastContent, PNG_BYTES)).isTrue();

    Feedback saved = feedbackRepository.findById(response.id()).orElseThrow();
    assertThat(saved.getImageKey()).isEqualTo(objectStorage.lastObjectKey);
    assertThat(saved.getImageKey()).doesNotStartWith("http");
  }

  @Test
  void submitKeepsFeedbackWhenUserRowDoesNotExistYet() {
    // 쓰기 API를 한 번도 안 태운 유저는 User 행이 없을 수 있다 — 그때 제출을 실패시키지 않는다.
    FeedbackResponse response =
        feedbackService.submit(
            "uid-never-written", FeedbackType.QUESTION, "문의합니다", null, null, null, null);

    Feedback saved = feedbackRepository.findById(response.id()).orElseThrow();
    assertThat(saved.getUser()).isNull();
    assertThat(saved.getContent()).isEqualTo("문의합니다");
  }

  @Test
  void submitTreatsBlankReplyEmailAsNull() {
    FeedbackResponse response =
        feedbackService.submit("uid-blank", FeedbackType.QUESTION, "내용", "   ", "  ", null, null);

    Feedback saved = feedbackRepository.findById(response.id()).orElseThrow();
    assertThat(saved.getReplyEmail()).isNull();
    assertThat(saved.getAppVersion()).isNull();
  }

  @Test
  void submitRejectsBlankContent() {
    ApiException ex =
        catchThrowableOfType(
            () -> feedbackService.submit("uid-1", FeedbackType.BUG, "   ", null, null, null, null),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void submitRejectsContentOverLengthLimit() {
    String tooLong = "가".repeat(2001);

    ApiException ex =
        catchThrowableOfType(
            () ->
                feedbackService.submit("uid-1", FeedbackType.BUG, tooLong, null, null, null, null),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void submitRejectsImageWhoseBytesAreNotARecognizedImage() {
    MockMultipartFile image =
        new MockMultipartFile("image", "shot.png", null, "not an image".getBytes());

    ApiException ex =
        catchThrowableOfType(
            () -> feedbackService.submit("uid-1", FeedbackType.BUG, "내용", null, null, null, image),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void submitRejectsImageOverSizeLimit() {
    byte[] oversized = new byte[6 * 1024 * 1024];
    System.arraycopy(PNG_BYTES, 0, oversized, 0, PNG_BYTES.length);
    MockMultipartFile image = new MockMultipartFile("image", "shot.png", null, oversized);

    ApiException ex =
        catchThrowableOfType(
            () -> feedbackService.submit("uid-1", FeedbackType.BUG, "내용", null, null, null, image),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }
}
