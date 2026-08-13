package com.nomara.modi.server.domain.dashboard.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveLike;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveLikeRepository;
import com.nomara.modi.server.domain.character.entity.UserActivityKind;
import com.nomara.modi.server.domain.character.repository.UserActivityRepository;
import com.nomara.modi.server.domain.dashboard.dto.ArchiveBrief;
import com.nomara.modi.server.domain.dashboard.dto.DashboardResponse;
import com.nomara.modi.server.domain.dashboard.dto.ScheduleBrief;
import com.nomara.modi.server.domain.dashboard.dto.TodoBrief;
import com.nomara.modi.server.domain.room.dto.MemberProgress;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.entity.RoomStatus;
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
import com.nomara.modi.server.global.exception.ApiException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** 홈 대시보드(specs/0005-홈-대시보드.md) 집계 로직을 실제 Postgres+Redis(Testcontainers)로 검증한다. */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class DashboardServiceTest {

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

  @Autowired private TestRestTemplate restTemplate;
  @Autowired private DashboardService dashboardService;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private TodoRepository todoRepository;
  @Autowired private TodoAssigneeRepository todoAssigneeRepository;
  @Autowired private ScheduleRepository scheduleRepository;
  @Autowired private ArchiveFolderRepository archiveFolderRepository;
  @Autowired private ArchiveItemRepository archiveItemRepository;
  @Autowired private ArchiveLikeRepository archiveLikeRepository;
  @Autowired private UserActivityRepository userActivityRepository;

  private static int counter = 0;

  private Room room(LocalDate start, LocalDate end) {
    return roomRepository.save(new Room("방-" + (++counter), null, "목표", null, start, end));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  private void join(Room room, User user) {
    roomMemberRepository.save(new RoomMember(room, user));
  }

  private Todo todo(Room room, String title) throws InterruptedException {
    Todo saved = todoRepository.save(new Todo(room, null, title, null));
    Thread.sleep(5);
    return saved;
  }

  private void assign(Todo todo, User user) {
    todoAssigneeRepository.save(new TodoAssignee(todo, user));
  }

  @Test
  void dashboardWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.getForEntity("/rooms/1/dashboard", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void unknownRoomIsForbiddenRegardlessOfExistence() {
    // 멤버십을 방 존재 여부보다 먼저 확인해 "없는 방"과 "남의 방"을 구분해 알려주지 않는다.
    ApiException ex =
        catchThrowableOfType(
            () ->
                dashboardService.getDashboard("uid-x", 999_999L, LocalDate.now(), LocalDate.now()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void nonMemberRequestThrowsForbidden() {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(10));
    User owner = user("uid-dash-owner");
    join(room, owner);

    ApiException ex =
        catchThrowableOfType(
            () ->
                dashboardService.getDashboard(
                    "uid-dash-outsider", room.getId(), LocalDate.now(), LocalDate.now()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void dashboardIncludesRoomInfoAndPerMemberProgress() throws InterruptedException {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User a = user("uid-dash-a");
    User b = user("uid-dash-b");
    join(room, a);
    join(room, b);

    Todo t1 = todo(room, "a1");
    Todo t2 = todo(room, "a2");
    Todo t3 = todo(room, "a3");
    Todo t4 = todo(room, "b1");
    assign(t1, a);
    assign(t2, a);
    assign(t3, a);
    assign(t4, b);
    t1.complete();
    t2.complete();
    todoRepository.save(t1);
    todoRepository.save(t2);

    DashboardResponse response =
        dashboardService.getDashboard(a.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.room().id()).isEqualTo(room.getId());
    assertThat(response.room().name()).isEqualTo(room.getName());
    MemberProgress memberA =
        response.members().stream()
            .filter(m -> m.userId().equals(a.getId()))
            .findFirst()
            .orElseThrow();
    assertThat(memberA.assignedTotal()).isEqualTo(3);
    assertThat(memberA.assignedDone()).isEqualTo(2);
    MemberProgress memberB =
        response.members().stream()
            .filter(m -> m.userId().equals(b.getId()))
            .findFirst()
            .orElseThrow();
    assertThat(memberB.assignedTotal()).isEqualTo(1);
    assertThat(memberB.assignedDone()).isEqualTo(0);
  }

  @Test
  void todayTodosOnlyIncludeMineNeverBackfillFromRoom() throws InterruptedException {
    // specs/0005-홈-대시보드.md 2026-07-27 패치: 방 전체 보충 폐기 — 남의 담당 투두가 섞이면 안 된다.
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-me");
    User other = user("uid-dash-other");
    join(room, me);
    join(room, other);

    Todo mine1 = todo(room, "mine-1");
    Todo mine2 = todo(room, "mine-2");
    assign(mine1, me);
    assign(mine2, me);

    Todo other1 = todo(room, "other-1");
    Todo other2 = todo(room, "other-2");
    Todo other3 = todo(room, "other-3");
    Todo other4 = todo(room, "other-4");
    assign(other1, other);
    assign(other2, other);
    assign(other3, other);
    assign(other4, other);

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.todayTodos())
        .extracting(TodoBrief::id)
        .containsExactly(mine1.getId(), mine2.getId());
  }

  @Test
  void todayTodosCapAtFiveWhenMineExceedsLimit() throws InterruptedException {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-plenty");
    join(room, me);

    List<Todo> mine =
        List.of(
            todo(room, "m1"),
            todo(room, "m2"),
            todo(room, "m3"),
            todo(room, "m4"),
            todo(room, "m5"),
            todo(room, "m6"));
    for (Todo t : mine) {
      assign(t, me);
    }

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.todayTodos()).hasSize(5);
    assertThat(response.todayTodos())
        .extracting(TodoBrief::id)
        .containsExactly(
            mine.get(0).getId(),
            mine.get(1).getId(),
            mine.get(2).getId(),
            mine.get(3).getId(),
            mine.get(4).getId());
  }

  @Test
  void todayTodosEmptyWhenNoIncompleteTodos() {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-empty");
    join(room, me);

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.todayTodos()).isEmpty();
  }

  @Test
  void todayTodosEmptyWhenOnlyOthersHaveIncompleteTodos() throws InterruptedException {
    // 내 담당이 0개면 방 전체로 보충하지 않고 빈 리스트를 반환한다(specs/0005 엣지케이스).
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-none");
    User other = user("uid-dash-someone");
    join(room, me);
    join(room, other);
    Todo othersTodo = todo(room, "other-only");
    assign(othersTodo, other);

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.todayTodos()).isEmpty();
  }

  @Test
  void memberProgressSortedByCompletionRateDescending() throws InterruptedException {
    // specs/0005-홈-대시보드.md 2026-07-27 패치: 멤버 아바타줄은 개인 진행률 내림차순.
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User low = user("uid-dash-low"); // 1/2 = 50%
    User high = user("uid-dash-high"); // 2/2 = 100%
    User none = user("uid-dash-none-progress"); // 0/0 = 0%
    join(room, low);
    join(room, high);
    join(room, none);

    Todo lowT1 = todo(room, "low-1");
    Todo lowT2 = todo(room, "low-2");
    assign(lowT1, low);
    assign(lowT2, low);
    lowT1.complete();
    todoRepository.save(lowT1);

    Todo highT1 = todo(room, "high-1");
    Todo highT2 = todo(room, "high-2");
    assign(highT1, high);
    assign(highT2, high);
    highT1.complete();
    highT2.complete();
    todoRepository.save(highT1);
    todoRepository.save(highT2);

    DashboardResponse response =
        dashboardService.getDashboard(low.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.members())
        .extracting(MemberProgress::userId)
        .containsExactly(high.getId(), low.getId(), none.getId());
  }

  @Test
  void roomWideTodoCountsAvoidDoubleCountingMultiAssigneeTodos() throws InterruptedException {
    // specs/0005 [백엔드 요구 ②]: 멤버별 assignedTotal 합산은 다중 담당자 투두를 중복 집계한다 —
    // 방 단위 todoDone/todoTotal은 그 함정을 피해 투두 1건은 정확히 1건으로 센다.
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User a = user("uid-dash-multi-a");
    User b = user("uid-dash-multi-b");
    join(room, a);
    join(room, b);

    Todo shared = todo(room, "shared");
    assign(shared, a);
    assign(shared, b);
    shared.complete();
    todoRepository.save(shared);
    todo(room, "solo-incomplete");

    DashboardResponse response =
        dashboardService.getDashboard(a.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.todoTotal()).isEqualTo(2);
    assertThat(response.todoDone()).isEqualTo(1);
  }

  @Test
  void roomCoverImageIsExposedWhenSetAndNullWhenNot() {
    Room withCover =
        roomRepository.save(
            new Room(
                "커버있음",
                "https://cdn.test/cover.jpg",
                "목표",
                null,
                LocalDate.now(),
                LocalDate.now().plusDays(10)));
    Room withoutCover = room(LocalDate.now(), LocalDate.now().plusDays(10));
    User me = user("uid-dash-cover");
    join(withCover, me);
    join(withoutCover, me);

    DashboardResponse withCoverResponse =
        dashboardService.getDashboard(
            me.getId(), withCover.getId(), LocalDate.now(), LocalDate.now());
    DashboardResponse withoutCoverResponse =
        dashboardService.getDashboard(
            me.getId(), withoutCover.getId(), LocalDate.now(), LocalDate.now());

    assertThat(withCoverResponse.room().coverImage()).isEqualTo("https://cdn.test/cover.jpg");
    assertThat(withoutCoverResponse.room().coverImage()).isNull();
  }

  @Test
  void weekSchedulesFilteredByDateRange() {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-sched");
    join(room, me);

    LocalDate weekStart = LocalDate.now();
    LocalDate weekEnd = weekStart.plusDays(6);
    scheduleRepository.save(
        new Schedule(room, "지난주", weekStart.minusDays(3), LocalTime.NOON, null, null, null, null));
    Schedule inRange =
        scheduleRepository.save(
            new Schedule(room, "이번주", weekStart.plusDays(2), null, null, null, null, null));
    scheduleRepository.save(
        new Schedule(room, "다음주", weekEnd.plusDays(3), null, null, null, null, null));

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), weekStart, weekEnd);

    assertThat(response.weekSchedules())
        .extracting(ScheduleBrief::id)
        .containsExactly(inRange.getId());
  }

  @Test
  void weekSchedulesIncludesMultiDaySpanningIntoTheWeekFromBefore() {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-sched-span");
    join(room, me);

    LocalDate weekStart = LocalDate.now();
    LocalDate weekEnd = weekStart.plusDays(6);
    // 주 시작 전에 시작해 주 안으로 걸치는 다중일 일정 — 단순 date BETWEEN이면 놓친다.
    Schedule spanning =
        scheduleRepository.save(
            new Schedule(
                room, "여행", weekStart.minusDays(2), null, weekStart.plusDays(1), null, null, null));

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), weekStart, weekEnd);

    assertThat(response.weekSchedules())
        .extracting(ScheduleBrief::id)
        .containsExactly(spanning.getId());
  }

  @Test
  void weekScheduleBriefIncludesEndTime() {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-sched-endtime");
    join(room, me);

    LocalDate weekStart = LocalDate.now();
    LocalDate weekEnd = weekStart.plusDays(6);
    Schedule withEndTime =
        scheduleRepository.save(
            new Schedule(
                room, "회의", weekStart, LocalTime.of(10, 0), null, LocalTime.of(12, 0), null, null));

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), weekStart, weekEnd);

    assertThat(response.weekSchedules())
        .filteredOn(brief -> brief.id().equals(withEndTime.getId()))
        .extracting(ScheduleBrief::endTime)
        .containsExactly(LocalTime.of(12, 0));
  }

  @Test
  void recentArchivesReturnTopFourNewestFirstWithLikeCount() throws InterruptedException {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-archive-me");
    User other = user("uid-dash-archive-other");
    join(room, me);
    join(room, other);
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItem item1 = archiveItem(folder, room, me, "자료1");
    ArchiveItem item2 = archiveItem(folder, room, me, "자료2");
    ArchiveItem item3 = archiveItem(folder, room, me, "자료3");
    ArchiveItem item4 = archiveItem(folder, room, me, "자료4");
    ArchiveItem item5 = archiveItem(folder, room, me, "자료5");
    archiveLikeRepository.save(new ArchiveLike(item5, me));
    archiveLikeRepository.save(new ArchiveLike(item5, other));

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.recentArchives())
        .extracting(ArchiveBrief::id)
        .containsExactly(item5.getId(), item4.getId(), item3.getId(), item2.getId());
    ArchiveBrief archive5 =
        response.recentArchives().stream()
            .filter(a -> a.id().equals(item5.getId()))
            .findFirst()
            .orElseThrow();
    assertThat(archive5.likeCount()).isEqualTo(2);
  }

  /**
   * 분석에 실패한(FAILED) 자료는 홈 미리보기에서 제외한다 — 2026-08-05 사용자 요청. 크롤링이 실패한 항목은 제목만 남아 미리보기에서 빈 카드처럼 보인다.
   *
   * <p>상위 N개를 먼저 자른 뒤 걸러내면 개수가 줄어들므로 <b>쿼리에서</b> 걸러야 한다 — 아래에서 FAILED 2건을 섞어도 정상 자료 4건이 그대로 나오는지로
   * 확인한다.
   */
  @Test
  void recentArchivesExcludeCrawlFailedItems() throws InterruptedException {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-archive-failed");
    join(room, me);
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItem ok1 = archiveItem(folder, room, me, "정상1");
    ArchiveItem ok2 = archiveItem(folder, room, me, "정상2");
    ArchiveItem ok3 = archiveItem(folder, room, me, "정상3");
    ArchiveItem ok4 = archiveItem(folder, room, me, "정상4");
    // 정상 자료보다 **나중에** 실패 자료를 넣는다 — 최신순 상위 4개를 실패분이 차지하는 상황.
    ArchiveItem failed1 = archiveItem(folder, room, me, "실패1");
    ArchiveItem failed2 = archiveItem(folder, room, me, "실패2");
    failed1.markCrawlFailed();
    failed2.markCrawlFailed();
    archiveItemRepository.saveAll(List.of(failed1, failed2));

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.recentArchives())
        .extracting(ArchiveBrief::id)
        .containsExactly(ok4.getId(), ok3.getId(), ok2.getId(), ok1.getId());
  }

  /** PENDING(분석 중)은 제외하지 않는다 — 곧 본문이 붙을 정상 자료다. FAILED만 영구 제외 대상이다. */
  @Test
  void recentArchivesKeepPendingItems() throws InterruptedException {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-archive-pending");
    join(room, me);
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    archiveItem(folder, room, me, "정상");
    ArchiveItem pending =
        archiveItemRepository.save(
            ArchiveItem.pending(folder, room, "분석중", "https://example.com/a", me));

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.recentArchives()).extracting(ArchiveBrief::id).contains(pending.getId());
  }

  /**
   * 아카이브 미리보기 — 핀 자료가 최신 비핀보다 앞에 온다. 핀 2건(그중 하나는 가장 오래됨)+비핀 3건 상황에서 핀 2건이 앞을 채우고 나머지 2자리를 최신 비핀 2건이
   * 채운다(최대 4개).
   */
  @Test
  void previewArchivesPutsPinnedItemsBeforeNewerUnpinnedOnes() throws InterruptedException {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-preview-pin");
    join(room, me);
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItem oldestPinned = archiveItem(folder, room, me, "가장 오래된 핀");
    ArchiveItem unpinned1 = archiveItem(folder, room, me, "비핀1");
    ArchiveItem newerPinned = archiveItem(folder, room, me, "더 최신 핀");
    ArchiveItem unpinned2 = archiveItem(folder, room, me, "비핀2");
    ArchiveItem unpinned3 = archiveItem(folder, room, me, "비핀3(최신)");
    oldestPinned.pin();
    newerPinned.pin();
    archiveItemRepository.saveAll(List.of(oldestPinned, newerPinned));

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.previewArchives())
        .extracting(ArchiveBrief::id)
        .containsExactly(
            newerPinned.getId(), oldestPinned.getId(), unpinned3.getId(), unpinned2.getId());
    assertThat(unpinned1.getId())
        .isNotIn(response.previewArchives().stream().map(ArchiveBrief::id).toList());
  }

  /** recentArchives는 핀 우선배치의 영향을 받지 않고 여전히 순수 최신순이다(회귀 확인). */
  @Test
  void recentArchivesStaysNewestFirstRegardlessOfPinned() throws InterruptedException {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-recent-unaffected");
    join(room, me);
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItem oldestPinned = archiveItem(folder, room, me, "오래된 핀");
    ArchiveItem newer = archiveItem(folder, room, me, "최신 비핀");
    oldestPinned.pin();
    archiveItemRepository.save(oldestPinned);

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.recentArchives())
        .extracting(ArchiveBrief::id)
        .containsExactly(newer.getId(), oldestPinned.getId());
  }

  /** pinnedArchives(백엔드 요청, 2026-08-07) — 순수 핀 필터. 핀 0개면 비핀 자료가 있어도 빈 배열이다. */
  @Test
  void pinnedArchivesIsEmptyWhenNoItemIsPinned() throws InterruptedException {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-pinned-empty");
    join(room, me);
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    archiveItem(folder, room, me, "비핀1");
    archiveItem(folder, room, me, "비핀2");

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.pinnedArchives()).isEmpty();
  }

  /** 핀한 자료만 최신순 최대 4개, 비핀 자료는 섞이지 않는다. */
  @Test
  void pinnedArchivesReturnsOnlyPinnedItemsNewestFirst() throws InterruptedException {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-pinned-only");
    join(room, me);
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItem oldestPinned = archiveItem(folder, room, me, "오래된 핀");
    archiveItem(folder, room, me, "비핀");
    ArchiveItem newestPinned = archiveItem(folder, room, me, "최신 핀");
    oldestPinned.pin();
    newestPinned.pin();
    archiveItemRepository.saveAll(List.of(oldestPinned, newestPinned));

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.pinnedArchives())
        .extracting(ArchiveBrief::id)
        .containsExactly(newestPinned.getId(), oldestPinned.getId());
  }

  /** FAILED 자료는 핀이어도 pinnedArchives에서 제외된다(다른 미리보기 필드와 같은 규칙). */
  @Test
  void pinnedArchivesExcludesCrawlFailedItemsEvenIfPinned() throws InterruptedException {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-pinned-failed");
    join(room, me);
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItem pinnedOk = archiveItem(folder, room, me, "핀+정상");
    ArchiveItem pinnedFailed = archiveItem(folder, room, me, "핀+실패");
    pinnedOk.pin();
    pinnedFailed.pin();
    pinnedFailed.markCrawlFailed();
    archiveItemRepository.saveAll(List.of(pinnedOk, pinnedFailed));

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.pinnedArchives())
        .extracting(ArchiveBrief::id)
        .containsExactly(pinnedOk.getId());
  }

  private ArchiveItem archiveItem(ArchiveFolder folder, Room room, User creator, String title)
      throws InterruptedException {
    ArchiveItem saved =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, title, null, "본문", null, null, creator));
    Thread.sleep(5);
    return saved;
  }

  /**
   * 4-3: end_date 경과 시 ENDED 전환은 홈 대시보드를 읽는 시점에도 적용된다(RoomService.refreshStatus 공유, 2026-07-30 확정).
   * room.end()를 수동으로 호출하지 않고 생성 시점부터 지난 end_date를 줘서 자동 전환을 검증한다.
   */
  /** 홈 활동 피드(2026-08-06, docs/backend/home-activity-feed.md)가 dashboard 응답에 실린다. */
  @Test
  void dashboardIncludesActivityFeed() throws InterruptedException {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-activity");
    join(room, me);
    Todo t = todo(room, "할일");
    assign(t, me);
    t.complete();
    todoRepository.save(t);

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.activities()).isNotEmpty();
  }

  /** 협업 캐릭터(specs/0016) 활동성 신호 — 대시보드 조회 시 ROOM_VIEW 로그가 남는다. */
  @Test
  void getDashboardRecordsRoomViewActivity() {
    Room room = room(LocalDate.now(), LocalDate.now().plusDays(30));
    User me = user("uid-dash-room-view-log");
    join(room, me);

    dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(
            userActivityRepository.countByUserIdAndKindAndCreatedAtAfter(
                me.getId(), UserActivityKind.ROOM_VIEW, Instant.now().minusSeconds(60)))
        .isEqualTo(1);
  }

  @Test
  void getDashboardReflectsAutoEndedStatusOnRead() {
    Room room = room(LocalDate.now().minusDays(20), LocalDate.now().minusDays(1));
    User me = user("uid-dash-autoend");
    join(room, me);

    DashboardResponse response =
        dashboardService.getDashboard(me.getId(), room.getId(), LocalDate.now(), LocalDate.now());

    assertThat(response.room().status()).isEqualTo(RoomStatus.ENDED);
    assertThat(roomRepository.findById(room.getId()).orElseThrow().getStatus())
        .isEqualTo(RoomStatus.ENDED);
  }
}
