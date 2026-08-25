package com.nomara.modi.server.domain.feedback.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.feedback.entity.FeedbackType;
import com.nomara.modi.server.domain.feedback.repository.FeedbackRepository;
import com.nomara.modi.server.global.exception.ApiException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/**
 * 스토리지 빈이 <b>아예 없는</b> 환경(로컬/CI, {@code MINIO_ENDPOINT} 미설정). 가짜 {@code ObjectStorage}를 꽂지 않는 것이 이
 * 테스트의 핵심이라 {@code FeedbackServiceTest}와 분리했다.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class FeedbackWithoutStorageTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    registry.add("minio.endpoint", () -> "false");
  }

  private static final byte[] PNG_BYTES = {
    (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02
  };

  @Autowired private FeedbackService feedbackService;
  @Autowired private FeedbackRepository feedbackRepository;

  @Test
  void submitWithoutImageSucceedsEvenWhenStorageIsNotConfigured() {
    // 스크린샷이 없으면 스토리지를 아예 건드리지 않으므로 제출은 정상이어야 한다.
    var response =
        feedbackService.submit("uid-1", FeedbackType.QUESTION, "내용", null, null, null, null);

    assertThat(feedbackRepository.findById(response.id())).isPresent();
  }

  @Test
  void submitWithImageFailsLoudlyWhenStorageIsNotConfigured() {
    // 이미지를 조용히 버리고 성공시키면 사용자는 스크린샷이 전달됐다고 믿는다 — 503으로 알린다.
    MockMultipartFile image = new MockMultipartFile("image", "shot.png", null, PNG_BYTES);

    ApiException ex =
        catchThrowableOfType(
            () -> feedbackService.submit("uid-1", FeedbackType.BUG, "내용", null, null, null, image),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
    assertThat(feedbackRepository.count()).isZero();
  }
}
