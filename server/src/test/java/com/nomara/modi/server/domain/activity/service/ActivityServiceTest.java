package com.nomara.modi.server.domain.activity.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.activity.dto.ActivityResponse;
import com.nomara.modi.server.domain.activity.entity.ActivityType;
import com.nomara.modi.server.domain.activity.repository.ActivityRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.schedule.entity.Schedule;
import com.nomara.modi.server.domain.schedule.repository.ScheduleRepository;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.entity.TodoAssignee;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.data.domain.PageRequest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 홈 활동 피드(docs/backend/home-activity-feed.md) — 그룹화·마일스톤 판정·파생형 4종·정렬/limit을 실제
 * Postgres(Testcontainers)로 검증한다.
 */
@Testcontainers
@SpringBootTest
class ActivityServiceTest {

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

  @Autowired private ActivityService activityService;
  @Autowired private ActivityRepository activityRepository;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private TodoRepository todoRepository;
  @Autowired private TodoAssigneeRepository todoAssigneeRepository;
  @Autowired private ScheduleRepository scheduleRepository;
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

  private RoomMember join(Room room, User user) {
    return roomMemberRepository.save(new RoomMember(room, user));
  }

  /**
   * {@code @CreationTimestamp}는 INSERT 시에만 자동 채워진다 — 과거로 되돌리려면 직접 UPDATE한다. JPA 엔티티를 고쳐 다시 save()하는
   * 대신 SQL로 바로 쓴다({@code @EmbeddedId} 엔티티의 merge 경합을 피한다).
   */
  private void backdateJoinedAt(Room room, User user, Instant when) {
    jdbcTemplate.update(
        "update room_members set joined_at = ? where room_id = ? and user_id = ?",
        java.sql.Timestamp.from(when),
        room.getId(),
        user.getId());
  }

  private void backdateActivityCreatedAt(Long activityId, Instant when) {
    jdbcTemplate.update(
        "update activities set created_at = ? where id = ?",
        java.sql.Timestamp.from(when),
        activityId);
  }

  @Test
  void isMilestoneOnlyTrueOnMultiplesOfFive() {
    assertThat(activityService.isMilestone(0)).isFalse();
    assertThat(activityService.isMilestone(4)).isFalse();
    assertThat(activityService.isMilestone(5)).isTrue();
    assertThat(activityService.isMilestone(9)).isFalse();
    assertThat(activityService.isMilestone(10)).isTrue();
  }

  @Test
  void recordedActivityIsReturnedWithResolvedNicknamesAndTargetName() {
    Room room = room();
    User actor = user("uid-activity-actor");
    join(room, actor);

    activityService.record(room, ActivityType.ARCHIVE_ADDED, actor, null, "여행 폴더", null);

    // 방마다 항상 붙는 NUDGE_NONE_TODAY(오늘 완료 0건) 파생 항목이 섞여 있을 수 있어 타입으로 좁힌다.
    ActivityResponse a = findByType(activityService.getRecentActivities(room), "ARCHIVE_ADDED");
    assertThat(a.actorNickname()).isEqualTo(actor.getNickname());
    assertThat(a.actorUserId()).isEqualTo(actor.getId());
    assertThat(a.targetName()).isEqualTo("여행 폴더");
  }

  private static ActivityResponse findByType(List<ActivityResponse> activities, String type) {
    return activities.stream()
        .filter(a -> a.type().equals(type))
        .findFirst()
        .orElseThrow(() -> new AssertionError("타입 " + type + " 항목을 찾지 못했다: " + activities));
  }

  @Test
  void pokeTargetNameResolvesFromTargetUserNicknameNotStoredString() {
    Room room = room();
    User from = user("uid-activity-poke-from");
    User to = user("uid-activity-poke-to");
    join(room, from);
    join(room, to);

    activityService.record(room, ActivityType.POKE, from, to, null, null);

    ActivityResponse a = findByType(activityService.getRecentActivities(room), "POKE");
    assertThat(a.targetName()).isEqualTo(to.getNickname());
  }

  @Test
  void pokesFromSameActorToSameTargetCollapseToOne() {
    Room room = room();
    User from = user("uid-activity-poke-dedup-from");
    User to = user("uid-activity-poke-dedup-to");
    join(room, from);
    join(room, to);

    activityService.record(room, ActivityType.POKE, from, to, null, null);
    activityService.record(room, ActivityType.POKE, from, to, null, null);
    activityService.record(room, ActivityType.POKE, from, to, null, null);

    List<ActivityResponse> pokes =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("POKE"))
            .toList();

    assertThat(pokes).hasSize(1);
  }

  @Test
  void pokesToDifferentTargetsAreNotCollapsed() {
    Room room = room();
    User from = user("uid-activity-poke-multi-from");
    User toB = user("uid-activity-poke-multi-to-b");
    User toC = user("uid-activity-poke-multi-to-c");
    join(room, from);
    join(room, toB);
    join(room, toC);

    activityService.record(room, ActivityType.POKE, from, toB, null, null);
    activityService.record(room, ActivityType.POKE, from, toC, null, null);

    List<ActivityResponse> pokes =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("POKE"))
            .toList();

    assertThat(pokes).hasSize(2);
  }

  @Test
  void pokeSpamDoesNotCrowdOutOtherActivities() {
    Room room = room();
    User from = user("uid-activity-poke-spam-from");
    User to = user("uid-activity-poke-spam-to");
    join(room, from);
    join(room, to);

    activityService.record(room, ActivityType.ARCHIVE_ADDED, from, null, "여행 폴더", null);
    for (int i = 0; i < 25; i++) {
      activityService.record(room, ActivityType.POKE, from, to, null, null);
    }

    assertThat(activityService.getRecentActivities(room))
        .anyMatch(a -> a.type().equals("ARCHIVE_ADDED"));
  }

  /**
   * 회원 탈퇴 시 {@code activities.actor_user_id}/{@code target_user_id}는 {@code ON DELETE SET NULL}이라
   * null이 된다(V20). 두 서로 무관한 콕이 우연히 양쪽 다 탈퇴자라 (actor=null, target=null)로 같아지면, dedup GROUP BY가 NULL을
   * 동등 취급해 실제로는 다른 두 사건을 하나로 합쳐버릴 위험이 있다 — 그룹핑에서 null 쌍은 아예 빼야 하는 이유.
   */
  @Test
  void pokesWithDifferentDeletedActorsAreNotIncorrectlyCollapsed() {
    Room room = room();
    User a1 = user("uid-poke-null-a1");
    User b1 = user("uid-poke-null-b1");
    User a2 = user("uid-poke-null-a2");
    User b2 = user("uid-poke-null-b2");

    activityService.record(room, ActivityType.POKE, a1, b1, null, null);
    activityService.record(room, ActivityType.POKE, a2, b2, null, null);

    userRepository.deleteById(a1.getId());
    userRepository.deleteById(b1.getId());
    userRepository.deleteById(a2.getId());
    userRepository.deleteById(b2.getId());

    List<ActivityResponse> pokes =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("POKE"))
            .toList();

    assertThat(pokes).hasSize(2);
  }

  @Test
  void sameActorSameDayTodoCompletedEventsAreMergedWithSummedCount() {
    Room room = room();
    User actor = user("uid-activity-merge");
    join(room, actor);

    activityService.record(room, ActivityType.TODO_COMPLETED, actor, null, null, 1);
    activityService.record(room, ActivityType.TODO_COMPLETED, actor, null, null, 1);
    activityService.record(room, ActivityType.TODO_COMPLETED, actor, null, null, 1);

    List<ActivityResponse> completed =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("TODO_COMPLETED"))
            .toList();

    assertThat(completed).hasSize(1);
    assertThat(completed.get(0).count()).isEqualTo(3);
  }

  @Test
  void todoCompletedOnDifferentDaysAreNotMerged() {
    Room room = room();
    User actor = user("uid-activity-merge-days");
    join(room, actor);

    activityService.record(room, ActivityType.TODO_COMPLETED, actor, null, null, 1);
    Long firstId =
        activityRepository
            .findByRoomIdOrderByCreatedAtDesc(room.getId(), PageRequest.of(0, 1))
            .get(0)
            .getId();
    backdateActivityCreatedAt(firstId, Instant.now().minus(Duration.ofDays(2)));
    activityService.record(room, ActivityType.TODO_COMPLETED, actor, null, null, 1);

    List<ActivityResponse> completed =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("TODO_COMPLETED"))
            .toList();

    assertThat(completed).hasSize(2);
    assertThat(completed).allSatisfy(a -> assertThat(a.count()).isEqualTo(1));
  }

  @Test
  void scheduleSoonAppearsOnlyWhenAScheduleIsTodayOrTomorrow() {
    Room room = room();
    User me = user("uid-activity-schedule-soon");
    join(room, me);

    assertThat(activityService.getRecentActivities(room))
        .noneMatch(a -> a.type().equals("SCHEDULE_SOON"));

    scheduleRepository.save(
        new Schedule(room, "내일 회의", LocalDate.now().plusDays(1), null, null, null, null, null));

    assertThat(activityService.getRecentActivities(room))
        .anyMatch(a -> a.type().equals("SCHEDULE_SOON"));
  }

  @Test
  void nudgeNoneTodayAppearsOnlyWhenTodayHasZeroCompletions() {
    Room room = room();
    User me = user("uid-activity-nudge-none");
    join(room, me);
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, me));

    assertThat(activityService.getRecentActivities(room))
        .anyMatch(a -> a.type().equals("NUDGE_NONE_TODAY"));

    todo.complete();
    todoRepository.save(todo);

    assertThat(activityService.getRecentActivities(room))
        .noneMatch(a -> a.type().equals("NUDGE_NONE_TODAY"));
  }

  @Test
  void nudgeUnassignedAppearsOnlyWhileUnassignedIncompleteTodoExists() {
    Room room = room();
    Todo todo = todoRepository.save(new Todo(room, null, "미지정 할일", null));

    ActivityResponse nudge =
        findByType(activityService.getRecentActivities(room), "NUDGE_UNASSIGNED");
    assertThat(nudge.count()).isEqualTo(1);

    User assignee = user("uid-activity-nudge-unassigned");
    join(room, assignee);
    todoAssigneeRepository.save(new TodoAssignee(todo, assignee));

    assertThat(activityService.getRecentActivities(room))
        .noneMatch(a -> a.type().equals("NUDGE_UNASSIGNED"));
  }

  @Test
  void weeklySummaryReflectsThisWeekCountAndDiffFromLastWeek() {
    Room room = room();
    User me = user("uid-activity-weekly");
    join(room, me);
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, me));
    todo.complete();
    todoRepository.save(todo);

    ActivityResponse weekly =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("WEEKLY_SUMMARY"))
            .findFirst()
            .orElseThrow();

    assertThat(weekly.count()).isEqualTo(1);
    // 저번 주 완료가 0건이므로 이번 주(1) - 저번 주(0) = +1.
    assertThat(weekly.secondaryCount()).isEqualTo(1);
  }

  @Test
  void quietMemberNudgeSurfacesOnlyTheQuietestMemberPastThreshold() {
    Room room = room();
    User quiet = user("uid-activity-quiet");
    User active = user("uid-activity-active");
    join(room, quiet);
    join(room, active);
    backdateJoinedAt(room, quiet, Instant.now().minus(Duration.ofDays(10)));

    // active는 오늘 활동을 남겨 조용하지 않다.
    activityService.record(room, ActivityType.MEMBER_JOINED, active, null, null, null);

    ActivityResponse nudge =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("NUDGE_QUIET_MEMBER"))
            .findFirst()
            .orElseThrow();

    assertThat(nudge.actorUserId()).isEqualTo(quiet.getId());
  }

  @Test
  void noQuietMemberNudgeWhenEveryoneJoinedRecently() {
    Room room = room();
    User me = user("uid-activity-fresh");
    join(room, me);

    assertThat(activityService.getRecentActivities(room))
        .noneMatch(a -> a.type().equals("NUDGE_QUIET_MEMBER"));
  }

  @Test
  void resultsAreSortedNewestFirstAndTruncatedToLimit() {
    Room room = room();
    User actor = user("uid-activity-limit");
    join(room, actor);

    for (int i = 0; i < 5; i++) {
      activityService.record(room, ActivityType.MEMBER_JOINED, actor, null, "이벤트" + i, null);
    }

    List<ActivityResponse> activities = activityService.getRecentActivities(room, 3);

    assertThat(activities).hasSize(3);
    for (int i = 0; i < activities.size() - 1; i++) {
      assertThat(activities.get(i).createdAt()).isAfterOrEqualTo(activities.get(i + 1).createdAt());
    }
  }
}
