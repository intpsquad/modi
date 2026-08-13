package com.nomara.modi.server.domain.todo.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.dto.TodoImageUploadUrlResponse;
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
 * {@code UserServiceProfilePhotoUploadTest}·{@code RoomCoverImageServiceTest}와 같은 패턴 — 실물 MinIO 대신
 * 기록용 가짜 {@link ObjectStorage}를 {@code @Primary}로 꽂아 발급 성공 경로만 본다. 빈 부재(503) 케이스는 {@link
 * TodoImageServiceTest}가 별도로 검증한다(같은 클래스에서 {@code @Primary} 빈을 조건부로 넣고 뺄 수 없다).
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TodoImageUploadUrlTest {

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

  @Autowired private TodoImageService todoImageService;
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
  void createUploadUrlUsesRoomScopedRandomKey() {
    Room room = room();
    User member = userRepository.save(new User("uid-upload-owner", "uid-upload-owner", null));
    roomMemberRepository.save(new RoomMember(room, member));

    TodoImageUploadUrlResponse response =
        todoImageService.createUploadUrl(member.getId(), room.getId());

    assertThat(objectStorage.lastObjectKey).startsWith("todos/" + room.getId() + "/");
    assertThat(objectStorage.lastExpiry).isEqualTo(Duration.ofMinutes(5));
    assertThat(response.uploadUrl())
        .isEqualTo("https://minio.local/upload/" + objectStorage.lastObjectKey);
    assertThat(response.publicUrl())
        .isEqualTo("https://minio.local/public/" + objectStorage.lastObjectKey);
  }

  @Test
  void createUploadUrlRejectsNonMember() {
    Room room = room();
    User outsider = userRepository.save(new User("uid-upload-outsider", "outsider", null));

    ApiException ex =
        catchThrowableOfType(
            () -> todoImageService.createUploadUrl(outsider.getId(), room.getId()),
            ApiException.class);

    assertThat(ex).isInstanceOf(NotRoomMemberException.class);
  }
}
