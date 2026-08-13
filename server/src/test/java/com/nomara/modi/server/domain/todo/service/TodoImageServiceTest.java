package com.nomara.modi.server.domain.todo.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.dto.TodoImageResponse;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.entity.TodoAssignee;
import com.nomara.modi.server.domain.todo.exception.TodoNotFoundException;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 모아보기 "이미지" 탭 피드/핀(2026-08-09, docs/backend/todo-image-archive-handoff.md). 업로드 URL 발급의 "성공" 경로는
 * {@link TodoImageUploadUrlTest}가 가짜 {@code ObjectStorage}로 따로 검증한다 — 여기서는 빈 부재(503)만 본다.
 */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TodoImageServiceTest {

  @Container @ServiceConnection
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.enabled", () -> "true");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
    // 로컬에 MINIO_ENDPOINT가 export돼 있어도 이 클래스는 항상 빈 부재 상태로 고정한다(UserServiceTest와 같은 이유).
    registry.add("minio.endpoint", () -> "false");
  }

  @Autowired private TodoImageService todoImageService;
  @Autowired private TodoService todoService;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private TodoRepository todoRepository;
  @Autowired private TodoAssigneeRepository todoAssigneeRepository;

  private static int counter = 0;

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter), null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10)));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  private Todo todoWithImage(Room room, String title, String imageUrl) {
    Todo todo = todoRepository.save(new Todo(room, null, title, null));
    todo.attachImage(imageUrl);
    return todoRepository.save(todo);
  }

  @Test
  void listImagesExcludesTodosWithoutImageAndOtherRooms() {
    Room room = room();
    Room otherRoom = room();
    User member = user("uid-feed-member");
    roomMemberRepository.save(new RoomMember(room, member));
    roomMemberRepository.save(new RoomMember(otherRoom, member));
    todoRepository.save(new Todo(room, null, "사진 없는 투두", null));
    todoWithImage(room, "이 방 사진 투두", "https://minio.local/todos/1/a.jpg");
    todoWithImage(otherRoom, "다른 방 사진 투두", "https://minio.local/todos/2/a.jpg");

    List<TodoImageResponse> images = todoImageService.listImages(member.getId(), room.getId());

    assertThat(images).extracting(TodoImageResponse::todoTitle).containsExactly("이 방 사진 투두");
  }

  @Test
  void listImagesOrdersPinnedFirstThenMostRecentlyAttached() throws InterruptedException {
    Room room = room();
    User member = user("uid-feed-order");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo older = todoWithImage(room, "먼저 첨부", "https://minio.local/todos/1/a.jpg");
    Thread.sleep(5);
    Todo newer = todoWithImage(room, "나중 첨부", "https://minio.local/todos/1/b.jpg");

    List<TodoImageResponse> images = todoImageService.listImages(member.getId(), room.getId());
    assertThat(images).extracting(TodoImageResponse::todoTitle).containsExactly("나중 첨부", "먼저 첨부");

    todoImageService.setPinned(member.getId(), room.getId(), older.getId(), true);

    List<TodoImageResponse> afterPin = todoImageService.listImages(member.getId(), room.getId());
    assertThat(afterPin).extracting(TodoImageResponse::todoTitle).containsExactly("먼저 첨부", "나중 첨부");
    assertThat(afterPin.get(0).pinned()).isTrue();
    assertThat(afterPin.get(0).id()).isEqualTo(older.getId());
    assertThat(afterPin.get(0).todoId()).isEqualTo(older.getId());
  }

  @Test
  void listImagesLeavesAssigneeNullForUnassignedTodo() {
    Room room = room();
    User member = user("uid-feed-unassigned");
    roomMemberRepository.save(new RoomMember(room, member));
    todoWithImage(room, "미지정 사진 투두", "https://minio.local/todos/1/a.jpg");

    TodoImageResponse image = todoImageService.listImages(member.getId(), room.getId()).getFirst();

    assertThat(image.assignee()).isNull();
  }

  /** todo_assignees에 배정 순서 컬럼이 없어 결정론을 위해 userId 오름차순 첫 번째를 대표로 뽑는다(서버 판단, 2026-08-09). */
  @Test
  void listImagesPicksLowestUserIdAsRepresentativeAssignee() {
    Room room = room();
    User zed = user("zed");
    User amy = user("amy");
    roomMemberRepository.save(new RoomMember(room, zed));
    roomMemberRepository.save(new RoomMember(room, amy));
    Todo todo = todoWithImage(room, "공동 담당 사진 투두", "https://minio.local/todos/1/a.jpg");
    todoAssigneeRepository.save(new TodoAssignee(todo, zed));
    todoAssigneeRepository.save(new TodoAssignee(todo, amy));

    TodoImageResponse image = todoImageService.listImages(zed.getId(), room.getId()).getFirst();

    assertThat(image.assignee().userId()).isEqualTo("amy");
  }

  @Test
  void setPinnedOnTodoWithoutImageThrowsNotFound() {
    Room room = room();
    User member = user("uid-pin-no-image");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo todo = todoRepository.save(new Todo(room, null, "사진 없는 투두", null));

    ApiException ex =
        catchThrowableOfType(
            () -> todoImageService.setPinned(member.getId(), room.getId(), todo.getId(), true),
            ApiException.class);

    assertThat(ex).isInstanceOf(TodoNotFoundException.class);
  }

  @Test
  void nonMemberCannotListOrPinImages() {
    Room room = room();
    User outsider = user("uid-outsider");
    Todo todo = todoWithImage(room, "사진 투두", "https://minio.local/todos/1/a.jpg");

    ApiException listEx =
        catchThrowableOfType(
            () -> todoImageService.listImages(outsider.getId(), room.getId()), ApiException.class);
    ApiException pinEx =
        catchThrowableOfType(
            () -> todoImageService.setPinned(outsider.getId(), room.getId(), todo.getId(), true),
            ApiException.class);

    assertThat(listEx).isInstanceOf(NotRoomMemberException.class);
    assertThat(pinEx).isInstanceOf(NotRoomMemberException.class);
  }

  @Test
  void createUploadUrlReturnsServiceUnavailableWithoutObjectStorage() {
    Room room = room();
    User member = user("uid-upload-no-storage");
    roomMemberRepository.save(new RoomMember(room, member));

    ApiException ex =
        catchThrowableOfType(
            () -> todoImageService.createUploadUrl(member.getId(), room.getId()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
  }
}
