package com.nomara.modi.server.domain.room.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.room.dto.CoverImageResponse;
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
 * {@code UserServiceProfilePhotoUploadTest}와 같은 패턴 — 실물 MinIO 대신 기록용 가짜 {@link ObjectStorage}를
 * {@code @Primary}로 꽂아 {@link RoomCoverImageService}가 검증·objectKey·put 호출을 올바르게 하는지만 본다.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class RoomCoverImageServiceTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    registry.add("minio.endpoint", () -> "false");
  }

  private static final byte[] JPEG_BYTES = {
    (byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0x01, 0x02, 0x03
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

  @Autowired private RoomCoverImageService roomCoverImageService;
  @Autowired private RecordingObjectStorage objectStorage;

  @Test
  void uploadStoresSniffedJpegUnderRoomsCoverPrefix() {
    MockMultipartFile file = new MockMultipartFile("image", "cover.jpg", null, JPEG_BYTES);

    CoverImageResponse response = roomCoverImageService.upload(file);

    assertThat(objectStorage.lastObjectKey).startsWith("rooms/cover/").endsWith(".jpg");
    assertThat(objectStorage.lastContentType).isEqualTo("image/jpeg");
    assertThat(Arrays.equals(objectStorage.lastContent, JPEG_BYTES)).isTrue();
    assertThat(response.coverImage())
        .isEqualTo("https://minio.local/public/" + objectStorage.lastObjectKey);
  }

  @Test
  void uploadRejectsEmptyFile() {
    MockMultipartFile file = new MockMultipartFile("image", "cover.jpg", null, new byte[0]);

    ApiException ex =
        catchThrowableOfType(() -> roomCoverImageService.upload(file), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void uploadRejectsFileWhoseBytesAreNotARecognizedImage() {
    MockMultipartFile file =
        new MockMultipartFile("image", "cover.jpg", null, "not an image".getBytes());

    ApiException ex =
        catchThrowableOfType(() -> roomCoverImageService.upload(file), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void uploadRejectsFileOverSizeLimit() {
    byte[] oversized = new byte[6 * 1024 * 1024];
    System.arraycopy(JPEG_BYTES, 0, oversized, 0, JPEG_BYTES.length);
    MockMultipartFile file = new MockMultipartFile("image", "cover.jpg", null, oversized);

    ApiException ex =
        catchThrowableOfType(() -> roomCoverImageService.upload(file), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }
}
