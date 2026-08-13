package com.nomara.modi.server.domain.user.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveLike;
import com.nomara.modi.server.domain.archive.entity.ArchiveLikeId;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveLikeRepository;
import com.nomara.modi.server.domain.notification.dto.UpdateNotificationSettingsRequest;
import com.nomara.modi.server.domain.notification.repository.NotificationSettingRepository;
import com.nomara.modi.server.domain.notification.service.NotificationSettingService;
import com.nomara.modi.server.domain.poke.entity.Poke;
import com.nomara.modi.server.domain.poke.entity.PokeType;
import com.nomara.modi.server.domain.poke.repository.PokeRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.entity.TodoAssignee;
import com.nomara.modi.server.domain.todo.entity.TodoAssigneeId;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 회원 탈퇴(specs/0012-설정.md S-40)를 실제 Postgres+Redis(Testcontainers)로 검증한다. FK cascade 동작은
 * V9__account_deletion_cascades.sql에만 있고 엔티티에 {@code @OnDelete}가 없어, Hibernate가 스키마를 auto-생성하는
 * create-drop 테스트로는 재현되지 않는다 — 반드시 Flyway가 실제로 적용된 스키마로 검증해야 한다.
 */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class UserWithdrawalServiceTest {

  @Container @ServiceConnection
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

  @Container
  @ServiceConnection(name = "redis")
  static GenericContainer<?> redis =
      new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.enabled", () -> "true");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
    registry.add("minio.endpoint", () -> "false");
  }

  @Autowired private UserService userService;
  @Autowired private UserRepository userRepository;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private ArchiveFolderRepository archiveFolderRepository;
  @Autowired private ArchiveItemRepository archiveItemRepository;
  @Autowired private ArchiveLikeRepository archiveLikeRepository;
  @Autowired private TodoRepository todoRepository;
  @Autowired private TodoAssigneeRepository todoAssigneeRepository;
  @Autowired private PokeRepository pokeRepository;
  @Autowired private NotificationSettingRepository notificationSettingRepository;
  @Autowired private NotificationSettingService notificationSettingService;

  private static int counter = 0;

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter), null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10)));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  private void join(Room room, User user) {
    roomMemberRepository.save(new RoomMember(room, user));
  }

  @Test
  void withdrawDeletesUserAndLeavesAllRooms() {
    User withdrawing = user("uid-withdraw-rooms");
    Room soleRoom = room();
    join(soleRoom, withdrawing);
    Room sharedRoom = room();
    User staying = user("uid-withdraw-staying");
    join(sharedRoom, withdrawing);
    join(sharedRoom, staying);

    userService.withdraw(withdrawing.getId());

    assertThat(userRepository.findById(withdrawing.getId())).isEmpty();
    assertThat(roomRepository.findById(soleRoom.getId())).isEmpty();
    assertThat(roomRepository.findById(sharedRoom.getId())).isPresent();
    assertThat(
            roomMemberRepository.existsById(new RoomMemberId(sharedRoom.getId(), staying.getId())))
        .isTrue();
  }

  @Test
  void withdrawKeepsArchiveItemInSharedRoomButClearsAuthor() {
    User withdrawing = user("uid-withdraw-author");
    User staying = user("uid-withdraw-author-staying");
    Room sharedRoom = room();
    join(sharedRoom, withdrawing);
    join(sharedRoom, staying);
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(sharedRoom, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, sharedRoom, "자료", null, "본문", null, null, withdrawing));

    userService.withdraw(withdrawing.getId());

    ArchiveItem reloaded = archiveItemRepository.findById(item.getId()).orElseThrow();
    assertThat(reloaded.getCreatedBy()).isNull();
  }

  @Test
  void withdrawCascadesLikesPokesAssigneesAndNotificationSettingsWithoutTouchingOtherUsers() {
    User withdrawing = user("uid-withdraw-activity");
    User other = user("uid-withdraw-activity-other");
    Room sharedRoom = room();
    join(sharedRoom, withdrawing);
    join(sharedRoom, other);

    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(sharedRoom, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, sharedRoom, "자료", null, "본문", null, null, other));
    archiveLikeRepository.save(new ArchiveLike(item, withdrawing));
    archiveLikeRepository.save(new ArchiveLike(item, other));

    Todo todo = todoRepository.save(new Todo(sharedRoom, null, "할일", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, withdrawing));
    todoAssigneeRepository.save(new TodoAssignee(todo, other));

    pokeRepository.save(new Poke(sharedRoom, withdrawing, other, PokeType.POKE));
    pokeRepository.save(new Poke(sharedRoom, other, withdrawing, PokeType.POKE));

    // NotificationSetting은 @MapsId로 PK를 User와 공유해서, 직접 new해 save하면 트랜잭션 경계를
    // 넘어온 User 참조 때문에 Hibernate가 엉뚱하게 users를 다시 insert하려 든다. 운영 코드와 똑같이
    // NotificationSettingService를 통해(한 트랜잭션 안에서 findById→생성→save) 만든다.
    UpdateNotificationSettingsRequest keepDefaults =
        new UpdateNotificationSettingsRequest(true, true);
    notificationSettingService.updateSettings(
        withdrawing.getId(), withdrawing.getId(), keepDefaults);
    notificationSettingService.updateSettings(other.getId(), other.getId(), keepDefaults);

    userService.withdraw(withdrawing.getId());

    assertThat(archiveLikeRepository.findById(new ArchiveLikeId(item.getId(), withdrawing.getId())))
        .isEmpty();
    assertThat(archiveLikeRepository.findById(new ArchiveLikeId(item.getId(), other.getId())))
        .isPresent();

    assertThat(
            todoAssigneeRepository.findById(new TodoAssigneeId(todo.getId(), withdrawing.getId())))
        .isEmpty();
    assertThat(todoAssigneeRepository.findById(new TodoAssigneeId(todo.getId(), other.getId())))
        .isPresent();

    assertThat(pokeRepository.findAll())
        .noneMatch(
            poke ->
                poke.getFromUser().getId().equals(withdrawing.getId())
                    || poke.getToUser().getId().equals(withdrawing.getId()));

    assertThat(notificationSettingRepository.findById(withdrawing.getId())).isEmpty();
    assertThat(notificationSettingRepository.findById(other.getId())).isPresent();
  }

  @Test
  void withdrawSucceedsForUserWithNoRoomsOrData() {
    User withdrawing = user("uid-withdraw-bare");

    userService.withdraw(withdrawing.getId());

    assertThat(userRepository.findById(withdrawing.getId())).isEmpty();
  }

  @Test
  void withdrawIsANoOpWhenUserRowDoesNotExist() {
    userService.withdraw("uid-withdraw-never-existed");

    assertThat(userRepository.findById("uid-withdraw-never-existed")).isEmpty();
  }
}
