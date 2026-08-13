package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.archive.dto.ArchiveImageUploadUrlResponse;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.time.Duration;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/**
 * 폴더 직접 업로드 이미지 자료(V28)의 presigned 업로드 URL 발급 — {@code TodoImageUploadUrlTest}와 같은 패턴(실물 MinIO 대신
 * 기록용 가짜 {@link ObjectStorage}를 {@code @Primary}로 꽂는다).
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ArchiveImageUploadUrlTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    registry.add("minio.endpoint", () -> "false");
  }

  static class RecordingObjectStorage implements ObjectStorage {
    String lastObjectKey;
    Duration lastExpiry;

    @Override
    public String createPresignedUploadUrl(String objectKey, Duration expiry) {
      this.lastObjectKey = objectKey;
      this.lastExpiry = expiry;
      return "https://minio.local/upload/" + objectKey;
    }

    @Override
    public void put(String objectKey, byte[] content, String contentType) {
      throw new UnsupportedOperationException();
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

  @Autowired private ArchiveItemService archiveItemService;
  @Autowired private RecordingObjectStorage objectStorage;
  @Autowired private RoomRepository roomRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;

  private static int counter = 0;

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter), null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10)));
  }

  @Test
  void createImageUploadUrlUsesRoomScopedRandomKey() {
    Room room = room();
    User member = userRepository.save(new User("uid-archive-upload-owner", "owner", null));
    roomMemberRepository.save(new RoomMember(room, member));

    ArchiveImageUploadUrlResponse response =
        archiveItemService.createImageUploadUrl(member.getId(), room.getId());

    // archive/ 로 시작해야 MinioConfig 의 공개 읽기 정책(archive/*)에 걸린다 — 다른 접두사를 쓰면
    // presigned PUT 업로드는 성공하지만 앱이 그 URL을 GET할 때 403이 난다(-archive-image-403).
    assertThat(objectStorage.lastObjectKey).startsWith("archive/images/" + room.getId() + "/");
    assertThat(objectStorage.lastExpiry).isEqualTo(Duration.ofMinutes(5));
    assertThat(response.uploadUrl())
        .isEqualTo("https://minio.local/upload/" + objectStorage.lastObjectKey);
    assertThat(response.publicUrl())
        .isEqualTo("https://minio.local/public/" + objectStorage.lastObjectKey);
  }

  @Test
  void createImageUploadUrlRejectsNonMember() {
    Room room = room();
    User outsider = userRepository.save(new User("uid-archive-upload-outsider", "outsider", null));

    ApiException ex =
        catchThrowableOfType(
            () -> archiveItemService.createImageUploadUrl(outsider.getId(), room.getId()),
            ApiException.class);

    assertThat(ex).isInstanceOf(NotRoomMemberException.class);
  }
}
