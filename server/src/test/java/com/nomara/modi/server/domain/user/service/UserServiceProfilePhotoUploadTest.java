package com.nomara.modi.server.domain.user.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.user.dto.ProfilePhotoUploadUrlResponse;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/**
 * {@link UserServiceTest}는 {@code minio.*} 프로퍼티가 없어 {@code ObjectStorage} 빈이 없는 상태(503 케이스)를 검증한다.
 * 이 클래스는 반대로 있는 상태(발급 성공)를 검증하려고 별도 클래스로 분리했다 — 같은 클래스에서 {@code @Primary} 빈을 조건부로 넣고 뺄 수 없다.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class UserServiceProfilePhotoUploadTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    // 실물 MinioConfig 빈은 여기서도 끈다 — 이 클래스가 검증하려는 건 아래 가짜 ObjectStorage(@Primary)를
    // UserService가 올바르게 쓰는지지, 실제 MinIO 연동이 아니다. 로컬에 MINIO_ENDPOINT가 export돼 있으면
    // 실물 빈도 같이 뜨려다 실패할 수 있어(UserServiceTest 주석 참고) 명시적으로 막는다.
    registry.add("minio.endpoint", () -> "false");
  }

  static class RecordingObjectStorage implements ObjectStorage {
    String lastObjectKey;
    Duration lastExpiry;
    byte[] lastPutContent;
    String lastPutContentType;

    @Override
    public String createPresignedUploadUrl(String objectKey, Duration expiry) {
      this.lastObjectKey = objectKey;
      this.lastExpiry = expiry;
      return "https://minio.local/upload/" + objectKey;
    }

    @Override
    public void put(String objectKey, byte[] content, String contentType) {
      this.lastObjectKey = objectKey;
      this.lastPutContent = content;
      this.lastPutContentType = contentType;
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

  @Autowired private UserService userService;
  @Autowired private RecordingObjectStorage objectStorage;

  @Test
  void createProfilePhotoUploadUrlUsesFixedKeyPerUser() {
    ProfilePhotoUploadUrlResponse response =
        userService.createProfilePhotoUploadUrl("uid-photo-owner");

    assertThat(objectStorage.lastObjectKey).isEqualTo("profile/uid-photo-owner");
    assertThat(response.uploadUrl())
        .isEqualTo("https://minio.local/upload/profile/uid-photo-owner");
    assertThat(response.publicUrl())
        .isEqualTo("https://minio.local/public/profile/uid-photo-owner");
  }
}
