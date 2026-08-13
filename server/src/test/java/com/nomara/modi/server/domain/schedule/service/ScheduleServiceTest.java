package com.nomara.modi.server.domain.schedule.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.schedule.dto.CreateScheduleRequest;
import com.nomara.modi.server.domain.schedule.dto.ScheduleResponse;
import com.nomara.modi.server.domain.schedule.dto.UpdateScheduleRequest;
import com.nomara.modi.server.domain.schedule.entity.Schedule;
import com.nomara.modi.server.domain.schedule.repository.ScheduleRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
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

/** 일정 CRUD(specs/0009-일정-탭.md, S-20~20-B)를 실제 Postgres+Redis(Testcontainers)로 검증한다. */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ScheduleServiceTest {

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
  @Autowired private ScheduleService scheduleService;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private ScheduleRepository scheduleRepository;
  @Autowired private ActivityService activityService;

  private static int counter = 0;

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter), null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10)));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  /** 홈 활동 피드(2026-08-06, docs/backend/home-activity-feed.md) SCHEDULE_ADDED. */
  @Test
  void creatingScheduleRecordsScheduleAddedActivityWithCreatorAsActor() {
    Room room = room();
    User member = user("uid-sched-activity");
    roomMemberRepository.save(new RoomMember(room, member));

    scheduleService.createSchedule(
        member.getId(),
        room.getId(),
        new CreateScheduleRequest("새 일정", LocalDate.of(2026, 7, 20), null, null, null, null, null));

    assertThat(activityService.getRecentActivities(room))
        .anySatisfy(
            a -> {
              assertThat(a.type()).isEqualTo("SCHEDULE_ADDED");
              assertThat(a.actorUserId()).isEqualTo(member.getId());
            });
  }

  @Test
  void listWithoutAuthReturnsUnauthorized() {
    var response =
        restTemplate.getForEntity(
            "/rooms/1/schedules?start=2026-01-01&end=2026-01-31", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void createThenListOrdersByDateThenTimeWithNullsFirst() {
    Room room = room();
    User member = user("uid-sched-a");
    roomMemberRepository.save(new RoomMember(room, member));
    LocalDate day = LocalDate.of(2026, 7, 15);

    ScheduleResponse afternoon =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest("오후 일정", day, LocalTime.of(14, 30), null, null, null, null));
    ScheduleResponse allDay =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest("종일 일정", day, null, null, null, null, null));
    ScheduleResponse morning =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest("오전 일정", day, LocalTime.of(9, 0), null, null, null, null));

    List<ScheduleResponse> schedules =
        scheduleService.listSchedules(
            member.getId(), room.getId(), day.minusDays(1), day.plusDays(1));

    assertThat(schedules)
        .extracting(ScheduleResponse::id)
        .containsExactly(allDay.id(), morning.id(), afternoon.id());
  }

  @Test
  void updateScheduleChangesAllFields() {
    Room room = room();
    User member = user("uid-sched-b");
    roomMemberRepository.save(new RoomMember(room, member));
    ScheduleResponse created =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest(
                "원래 제목", LocalDate.of(2026, 7, 1), null, null, null, null, null));

    ScheduleResponse updated =
        scheduleService.updateSchedule(
            member.getId(),
            room.getId(),
            created.id(),
            new UpdateScheduleRequest(
                "바뀐 제목",
                LocalDate.of(2026, 7, 2),
                LocalTime.of(10, 0),
                null,
                null,
                "상세 추가",
                "회의실 A"));

    assertThat(updated.title()).isEqualTo("바뀐 제목");
    assertThat(updated.date()).isEqualTo(LocalDate.of(2026, 7, 2));
    assertThat(updated.time()).isEqualTo(LocalTime.of(10, 0));
    assertThat(updated.detail()).isEqualTo("상세 추가");
    assertThat(updated.place()).isEqualTo("회의실 A");
  }

  @Test
  void createScheduleWithPlacePersistsAndListsIt() {
    Room room = room();
    User member = user("uid-sched-place");
    roomMemberRepository.save(new RoomMember(room, member));
    LocalDate day = LocalDate.of(2026, 8, 3);

    ScheduleResponse created =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest(
                "스터디", day, LocalTime.of(19, 0), null, null, null, "학교 스터디룸"));

    assertThat(created.place()).isEqualTo("학교 스터디룸");
    List<ScheduleResponse> schedules =
        scheduleService.listSchedules(member.getId(), room.getId(), day, day);
    assertThat(schedules).extracting(ScheduleResponse::place).containsExactly("학교 스터디룸");
  }

  @Test
  void createScheduleWithoutPlaceLeavesItNull() {
    Room room = room();
    User member = user("uid-sched-no-place");
    roomMemberRepository.save(new RoomMember(room, member));

    ScheduleResponse created =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest("장소 없음", LocalDate.now(), null, null, null, null, null));

    assertThat(created.place()).isNull();
  }

  @Test
  void updateScheduleCanClearPlaceBackToNull() {
    Room room = room();
    User member = user("uid-sched-clear-place");
    roomMemberRepository.save(new RoomMember(room, member));
    ScheduleResponse created =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest("일정", LocalDate.now(), null, null, null, null, "원래 장소"));

    ScheduleResponse updated =
        scheduleService.updateSchedule(
            member.getId(),
            room.getId(),
            created.id(),
            new UpdateScheduleRequest("일정", LocalDate.now(), null, null, null, null, null));

    assertThat(updated.place()).isNull();
  }

  @Test
  void deleteScheduleRemovesIt() {
    Room room = room();
    User member = user("uid-sched-c");
    roomMemberRepository.save(new RoomMember(room, member));
    ScheduleResponse created =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest("삭제될 일정", LocalDate.now(), null, null, null, null, null));

    scheduleService.deleteSchedule(member.getId(), room.getId(), created.id());

    assertThat(scheduleRepository.findById(created.id())).isEmpty();
  }

  @Test
  void nonMemberCannotCreateSchedule() {
    Room room = room();
    User member = user("uid-sched-owner");
    roomMemberRepository.save(new RoomMember(room, member));

    ApiException ex =
        catchThrowableOfType(
            () ->
                scheduleService.createSchedule(
                    "uid-sched-outsider",
                    room.getId(),
                    new CreateScheduleRequest("이름", LocalDate.now(), null, null, null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void scheduleFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-sched-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    Schedule scheduleOfRoomB =
        scheduleRepository.save(
            new Schedule(roomB, "남의 일정", LocalDate.now(), null, null, null, null, null));

    ApiException ex =
        catchThrowableOfType(
            () ->
                scheduleService.updateSchedule(
                    member.getId(),
                    roomA.getId(),
                    scheduleOfRoomB.getId(),
                    new UpdateScheduleRequest(
                        "바꾸기", LocalDate.now(), null, null, null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void deletingScheduleFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-sched-cross-delete");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    Schedule scheduleOfRoomB =
        scheduleRepository.save(
            new Schedule(roomB, "남의 일정", LocalDate.now(), null, null, null, null, null));

    ApiException ex =
        catchThrowableOfType(
            () ->
                scheduleService.deleteSchedule(
                    member.getId(), roomA.getId(), scheduleOfRoomB.getId()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(scheduleRepository.findById(scheduleOfRoomB.getId())).isPresent();
  }

  @Test
  void endDateBeforeDateIsRejectedAsBadRequest() {
    Room room = room();
    User member = user("uid-sched-range-a");
    roomMemberRepository.save(new RoomMember(room, member));
    LocalDate day = LocalDate.of(2026, 8, 10);

    ApiException ex =
        catchThrowableOfType(
            () ->
                scheduleService.createSchedule(
                    member.getId(),
                    room.getId(),
                    new CreateScheduleRequest("여행", day, null, day.minusDays(1), null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void endTimeWithoutStartTimeIsRejectedAsBadRequest() {
    Room room = room();
    User member = user("uid-sched-range-b");
    roomMemberRepository.save(new RoomMember(room, member));

    ApiException ex =
        catchThrowableOfType(
            () ->
                scheduleService.createSchedule(
                    member.getId(),
                    room.getId(),
                    new CreateScheduleRequest(
                        "회의", LocalDate.now(), null, null, LocalTime.of(11, 0), null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void sameDayEndTimeNotAfterStartTimeIsRejectedAsBadRequest() {
    Room room = room();
    User member = user("uid-sched-range-c");
    roomMemberRepository.save(new RoomMember(room, member));

    ApiException ex =
        catchThrowableOfType(
            () ->
                scheduleService.createSchedule(
                    member.getId(),
                    room.getId(),
                    new CreateScheduleRequest(
                        "회의",
                        LocalDate.now(),
                        LocalTime.of(10, 0),
                        null,
                        LocalTime.of(10, 0),
                        null,
                        null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void multiDayScheduleAllowsEndTimeWithoutOrderingAgainstStartTime() {
    Room room = room();
    User member = user("uid-sched-range-d");
    roomMemberRepository.save(new RoomMember(room, member));
    LocalDate day = LocalDate.of(2026, 8, 10);

    // 다중일이면 종료 시간이 다른 날짜(종료일)에 속하므로 시작 시간보다 이르더라도 통과해야 한다.
    ScheduleResponse created =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest(
                "여행", day, LocalTime.of(18, 0), day.plusDays(2), LocalTime.of(9, 0), null, null));

    assertThat(created.endDate()).isEqualTo(day.plusDays(2));
    assertThat(created.endTime()).isEqualTo(LocalTime.of(9, 0));
  }

  @Test
  void creatingWithEndDateEqualToDateNormalizesToNull() {
    Room room = room();
    User member = user("uid-sched-range-e");
    roomMemberRepository.save(new RoomMember(room, member));
    LocalDate day = LocalDate.now();

    ScheduleResponse created =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest("일정", day, null, day, null, null, null));

    assertThat(created.endDate()).isNull();
  }

  @Test
  void updatingCanClearEndDateAndEndTimeBackToNull() {
    Room room = room();
    User member = user("uid-sched-range-f");
    roomMemberRepository.save(new RoomMember(room, member));
    LocalDate day = LocalDate.of(2026, 8, 10);
    ScheduleResponse created =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest(
                "여행", day, LocalTime.of(9, 0), day.plusDays(1), LocalTime.of(18, 0), null, null));

    ScheduleResponse updated =
        scheduleService.updateSchedule(
            member.getId(),
            room.getId(),
            created.id(),
            new UpdateScheduleRequest("여행", day, LocalTime.of(9, 0), null, null, null, null));

    assertThat(updated.endDate()).isNull();
    assertThat(updated.endTime()).isNull();
  }

  @Test
  void listSchedulesIncludesMultiDayScheduleStartingBeforeTheQueriedRange() {
    Room room = room();
    User member = user("uid-sched-range-g");
    roomMemberRepository.save(new RoomMember(room, member));
    LocalDate rangeStart = LocalDate.of(2026, 8, 10);
    LocalDate rangeEnd = LocalDate.of(2026, 8, 16);
    ScheduleResponse spanning =
        scheduleService.createSchedule(
            member.getId(),
            room.getId(),
            new CreateScheduleRequest(
                "여행", rangeStart.minusDays(2), null, rangeStart.plusDays(1), null, null, null));

    List<ScheduleResponse> schedules =
        scheduleService.listSchedules(member.getId(), room.getId(), rangeStart, rangeEnd);

    assertThat(schedules).extracting(ScheduleResponse::id).containsExactly(spanning.id());
  }
}
