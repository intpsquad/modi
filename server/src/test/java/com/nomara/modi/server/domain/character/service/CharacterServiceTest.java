package com.nomara.modi.server.domain.character.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveLike;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveLikeRepository;
import com.nomara.modi.server.domain.character.dto.CharacterResponse;
import com.nomara.modi.server.domain.character.dto.CharacterResponse.Confidence;
import com.nomara.modi.server.domain.character.entity.CharacterId;
import com.nomara.modi.server.domain.character.entity.UserActivity;
import com.nomara.modi.server.domain.character.entity.UserActivityKind;
import com.nomara.modi.server.domain.character.repository.UserActivityRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.entity.TodoAssignee;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** 협업 캐릭터 판정(specs/0016-협업-캐릭터.md 3장)을 실제 Postgres+Redis(Testcontainers)로 검증한다. */
@Testcontainers
@SpringBootTest
class CharacterServiceTest {

  private static final ZoneId KST = ZoneId.of("Asia/Seoul");

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
  }

  @Autowired private CharacterService characterService;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private TodoRepository todoRepository;
  @Autowired private TodoAssigneeRepository todoAssigneeRepository;
  @Autowired private ArchiveFolderRepository archiveFolderRepository;
  @Autowired private ArchiveItemRepository archiveItemRepository;
  @Autowired private ArchiveLikeRepository archiveLikeRepository;
  @Autowired private UserActivityRepository userActivityRepository;
  @Autowired private JdbcTemplate jdbcTemplate;

  private static int counter = 0;

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter), null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(30)));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  private void join(Room room, User user) {
    roomMemberRepository.save(new RoomMember(room, user));
  }

  private Instant atKst(LocalDate date, int hour) {
    return date.atTime(hour, 0).atZone(KST).toInstant();
  }

  /** 완료된 투두 하나를 만들고 due_date/created_at/completed_at을 원하는 값으로 되돌린다. */
  private Todo completedTodo(Room room, User assignee, LocalDate dueDate, LocalDate completedDate) {
    Todo todo = new Todo(room, null, "할일", null);
    todo.complete();
    Todo saved = todoRepository.save(todo);
    todoAssigneeRepository.save(new TodoAssignee(saved, assignee));
    Instant completedAt = atKst(completedDate, 9);
    Instant createdAt = completedAt.minusSeconds(3600);
    jdbcTemplate.update(
        "update todos set due_date = ?, created_at = ?, completed_at = ? where id = ?",
        dueDate,
        Timestamp.from(createdAt),
        Timestamp.from(completedAt),
        saved.getId());
    return saved;
  }

  private Todo incompleteTodo(Room room, User assignee) {
    Todo saved = todoRepository.save(new Todo(room, null, "할일", null));
    todoAssigneeRepository.save(new TodoAssignee(saved, assignee));
    return saved;
  }

  private void giveLikes(User liker, Room room, int count) {
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    for (int i = 0; i < count; i++) {
      ArchiveItem item =
          archiveItemRepository.save(
              new ArchiveItem(folder, room, "자료" + i, null, "본문", null, null, liker));
      archiveLikeRepository.save(new ArchiveLike(item, liker));
    }
  }

  private void recordView(User user, Room room, int count) {
    for (int i = 0; i < count; i++) {
      userActivityRepository.save(new UserActivity(user, room, UserActivityKind.ROOM_VIEW, null));
    }
  }

  @Test
  void completedCountUnderFiveIsWarmingUp() {
    Room room = room();
    User me = user("uid-char-warming-up");
    join(room, me);
    LocalDate today = LocalDate.now(KST);
    for (int i = 0; i < 3; i++) {
      completedTodo(room, me, null, today);
    }

    CharacterResponse response = characterService.getCharacter(me.getId());

    assertThat(response.characterId()).isEqualTo(CharacterId.WARMING_UP);
    assertThat(response.confidence()).isEqualTo(Confidence.LOW);
    assertThat(response.evolveTo()).isNull();
  }

  /** 구분 포인트(문서): 둘 다 늦지만 완료율로 갈린다 — PROCRASTINATOR는 낮고 SPRINTER는 높다. */
  @Test
  void lateAndLowCompletionRateIsProcrastinator() {
    Room room = room();
    User me = user("uid-char-procrastinator");
    join(room, me);
    LocalDate today = LocalDate.now(KST);
    for (int i = 0; i < 5; i++) {
      // 마감보다 5일 늦게 완료 — 뚜렷하게 "미룸".
      completedTodo(room, me, today.minusDays(5), today);
    }
    for (int i = 0; i < 5; i++) {
      incompleteTodo(room, me); // 완료율을 0.5로 낮춘다.
    }

    CharacterResponse response = characterService.getCharacter(me.getId());

    assertThat(response.characterId()).isEqualTo(CharacterId.PROCRASTINATOR);
    assertThat(response.evolveTo()).isEqualTo(CharacterId.SPRINTER);
    assertThat(response.confidence()).isEqualTo(Confidence.LOW); // 완료 5개 < 10
  }

  @Test
  void lateButHighCompletionRateIsSprinter() {
    Room room = room();
    User me = user("uid-char-sprinter");
    join(room, me);
    LocalDate today = LocalDate.now(KST);
    for (int i = 0; i < 5; i++) {
      completedTodo(room, me, today.minusDays(5), today);
    }
    incompleteTodo(room, me); // 총 6개 중 5개 완료 = 0.833 → 완료율 높음.

    CharacterResponse response = characterService.getCharacter(me.getId());

    assertThat(response.characterId()).isEqualTo(CharacterId.SPRINTER);
    assertThat(response.evolveTo()).isEqualTo(CharacterId.EARLYBIRD);
  }

  @Test
  void earlyButLowCompletionRateIsEarlybirdNotTheJ() {
    Room room = room();
    User me = user("uid-char-earlybird");
    join(room, me);
    LocalDate today = LocalDate.now(KST);
    for (int i = 0; i < 5; i++) {
      // 마감보다 5일 일찍 완료 — 뚜렷하게 "미리".
      completedTodo(room, me, today.plusDays(5), today);
    }
    for (int i = 0; i < 5; i++) {
      incompleteTodo(room, me); // 완료율 0.5 — THE_J 문턱(0.85) 미달.
    }

    CharacterResponse response = characterService.getCharacter(me.getId());

    assertThat(response.characterId()).isEqualTo(CharacterId.EARLYBIRD);
    assertThat(response.evolveTo()).isEqualTo(CharacterId.THE_J);
  }

  @Test
  void allSignalsExcellentIsTheJ() {
    Room room = room();
    User me = user("uid-char-the-j");
    join(room, me);
    LocalDate today = LocalDate.now(KST);
    // 10일 연속 완료(스트릭 7 문턱을 넉넉히 넘기고, 완료 수도 confidence HIGH 문턱(10)을
    // 채운다) + 항상 마감 5일 전 + 전량 완료(담당=완료).
    for (int i = 0; i < 10; i++) {
      LocalDate day = today.minusDays(i);
      completedTodo(room, me, day.plusDays(5), day);
    }

    CharacterResponse response = characterService.getCharacter(me.getId());

    assertThat(response.characterId()).isEqualTo(CharacterId.THE_J);
    assertThat(response.evolveTo()).isNull();
    assertThat(response.evolveProgress()).isNull();
    assertThat(response.confidence()).isEqualTo(Confidence.HIGH);
  }

  @Test
  void regularTimingWithLongStreakIsSteady() {
    Room room = room();
    User me = user("uid-char-steady");
    join(room, me);
    LocalDate today = LocalDate.now(KST);
    // 7일 연속, 항상 마감 당일 완료(중립 타이밍).
    for (int i = 0; i < 7; i++) {
      LocalDate day = today.minusDays(i);
      completedTodo(room, me, day, day);
    }

    CharacterResponse response = characterService.getCharacter(me.getId());

    assertThat(response.characterId()).isEqualTo(CharacterId.STEADY);
    assertThat(response.evolveTo()).isEqualTo(CharacterId.EARLYBIRD);
  }

  @Test
  void regularTimingWithShortStreakIsTurtle() {
    Room room = room();
    User me = user("uid-char-turtle");
    join(room, me);
    LocalDate today = LocalDate.now(KST);
    // 완료는 5개 있지만 흩어져 있어 연속(streak)이 안 생긴다.
    completedTodo(room, me, today, today);
    completedTodo(room, me, today.minusDays(3), today.minusDays(3));
    completedTodo(room, me, today.minusDays(5), today.minusDays(5));
    completedTodo(room, me, today.minusDays(1), today.minusDays(1));
    completedTodo(room, me, today.minusDays(2), today.minusDays(2));

    CharacterResponse response = characterService.getCharacter(me.getId());

    // (today, today-1, today-2, today-3)까지는 실제로 연속이라 STEADY_STREAK_DAYS(7)엔 못 미친다.
    assertThat(response.characterId()).isEqualTo(CharacterId.TURTLE);
    assertThat(response.evolveTo()).isEqualTo(CharacterId.STEADY);
  }

  @Test
  void manyRecentViewsWithFewRecentCompletionsIsLurker() {
    Room room = room();
    User me = user("uid-char-lurker");
    join(room, me);
    LocalDate longAgo = LocalDate.now(KST).minusDays(60);
    for (int i = 0; i < 5; i++) {
      completedTodo(room, me, null, longAgo); // 최근 30일 밖 — recentCompleted에 안 잡힌다.
    }
    recordView(me, room, 10); // 지금 기록되므로 최근 30일 안.

    CharacterResponse response = characterService.getCharacter(me.getId());

    assertThat(response.characterId()).isEqualTo(CharacterId.LURKER);
    assertThat(response.evolveTo()).isEqualTo(CharacterId.STEADY);
  }

  @Test
  void longGapThenRecentBurstIsGhost() {
    Room room = room();
    User me = user("uid-char-ghost");
    join(room, me);
    LocalDate today = LocalDate.now(KST);
    // 20일 전 무렵 3건, 그리고 최근(오늘·어제) 2건 — 사이에 7일 넘는 공백.
    completedTodo(room, me, null, today.minusDays(20));
    completedTodo(room, me, null, today.minusDays(19));
    completedTodo(room, me, null, today.minusDays(18));
    completedTodo(room, me, null, today.minusDays(1));
    completedTodo(room, me, null, today);

    CharacterResponse response = characterService.getCharacter(me.getId());

    assertThat(response.characterId()).isEqualTo(CharacterId.GHOST);
    assertThat(response.evolveTo()).isEqualTo(CharacterId.STEADY);
  }

  @Test
  void manyLikesGivenOverridesToCheerleader() {
    Room room = room();
    User me = user("uid-char-cheerleader");
    join(room, me);
    LocalDate today = LocalDate.now(KST);
    for (int i = 0; i < 5; i++) {
      // PROCRASTINATOR가 될 신호(늦음+낮은 완료율)를 일부러 만들어 오버라이드를 확인한다.
      completedTodo(room, me, today.minusDays(5), today);
    }
    for (int i = 0; i < 5; i++) {
      incompleteTodo(room, me);
    }
    giveLikes(me, room, 20);

    CharacterResponse response = characterService.getCharacter(me.getId());

    assertThat(response.characterId()).isEqualTo(CharacterId.CHEERLEADER);
    assertThat(response.activityStats().helpGiven()).isEqualTo(20);
  }

  @Test
  void confidenceIsHighWithTenOrMoreCompletedAndSomeDueDates() {
    Room room = room();
    User me = user("uid-char-confidence-high");
    join(room, me);
    LocalDate today = LocalDate.now(KST);
    for (int i = 0; i < 10; i++) {
      completedTodo(room, me, today.minusDays(1), today);
    }

    CharacterResponse response = characterService.getCharacter(me.getId());

    assertThat(response.confidence()).isEqualTo(Confidence.HIGH);
    assertThat(response.activityStats().dueDateCompletedCount()).isEqualTo(10);
  }

  /**
   * 마감일 있는 완료 투두가 하나도 없으면 {@code deadlineKeptRate}가 0.0으로 나가는데, 이것이 "0%"(안 지킴)가 아니라 "잴 데이터 없음"임을
   * 프론트가 구분할 수 있도록 {@code dueDateCompletedCount}도 0으로 함께 나가야 한다 (2026-08-09, 마감 준수 0% 오표시 버그 수정).
   */
  @Test
  void confidenceIsLowWhenNoCompletedTodoHasDueDate() {
    Room room = room();
    User me = user("uid-char-confidence-low");
    join(room, me);
    LocalDate today = LocalDate.now(KST);
    for (int i = 0; i < 10; i++) {
      completedTodo(room, me, null, today); // 전부 마감 없음.
    }

    CharacterResponse response = characterService.getCharacter(me.getId());

    assertThat(response.confidence()).isEqualTo(Confidence.LOW);
    assertThat(response.activityStats().dueDateCompletedCount()).isEqualTo(0);
  }

  @Test
  void getCharacterForRoomMemberRequiresSharedRoomMembership() {
    Room room = room();
    User me = user("uid-char-caller");
    User target = user("uid-char-target");
    join(room, me);
    join(room, target);
    for (int i = 0; i < 5; i++) {
      completedTodo(room, target, null, LocalDate.now(KST));
    }

    CharacterResponse response =
        characterService.getCharacterForRoomMember(me.getId(), room.getId(), target.getId());

    assertThat(response).isNotNull();
  }

  @Test
  void getCharacterForRoomMemberRejectsNonMemberCaller() {
    Room room = room();
    User target = user("uid-char-target-2");
    join(room, target);

    org.assertj.core.api.Assertions.assertThatThrownBy(
            () ->
                characterService.getCharacterForRoomMember(
                    "uid-char-outsider", room.getId(), target.getId()))
        .isInstanceOf(com.nomara.modi.server.global.exception.ApiException.class);
  }
}
