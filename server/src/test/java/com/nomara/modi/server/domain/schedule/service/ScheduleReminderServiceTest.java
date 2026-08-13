package com.nomara.modi.server.domain.schedule.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.notification.entity.NotificationSetting;
import com.nomara.modi.server.domain.notification.repository.NotificationSettingRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.schedule.entity.Schedule;
import com.nomara.modi.server.domain.schedule.repository.ScheduleRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.support.FakePushSenderConfig;
import com.nomara.modi.server.support.RecordingPushSender;
import java.time.LocalDate;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 일정 전날/디데이 알림 배치(full_spec.md:205, specs/0015-알림-트리거.md)를 실제 Postgres+Redis(Testcontainers)로 검증한다.
 * cron을 기다리지 않고 {@link ScheduleReminderService#sendDailyScheduleReminders()}를 직접 호출한다.
 */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(FakePushSenderConfig.class)
class ScheduleReminderServiceTest {

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

  @Autowired private ScheduleReminderService scheduleReminderService;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private ScheduleRepository scheduleRepository;
  @Autowired private NotificationSettingRepository notificationSettingRepository;
  @Autowired private RecordingPushSender pushSender;

  private static int counter = 0;

  @BeforeEach
  void clearPushes() {
    pushSender.clear();
  }

  private Room activeRoom() {
    return roomRepository.save(
        new Room("방-" + (++counter), null, "목표", null, today().minusDays(5), today().plusDays(5)));
  }

  private User memberWithToken(Room room, String uid, String token) {
    User user = userRepository.save(new User(uid, uid, null));
    user.updateFcmToken(token);
    userRepository.save(user);
    roomMemberRepository.save(new RoomMember(room, user));
    return user;
  }

  /**
   * 🔴 <b>{@code LocalDate.now()} 를 쓰지 말 것.</b> 그건 JVM 기본 시간대이고, 서비스는 {@code
   * LocalDate.now(ScheduleReminderService.KST)} 로 판단한다. CI 컨테이너가 UTC 라 KST 09:00 이전에 빌드가 돌면 하루가 어긋나
   * 이 파일의 테스트가 <b>전부</b> 깨진다 — 2026-08-05 20:10Z(= KST 08-06 05:10) 빌드에서 실제로 dev 가 막혔다.
   *
   * <p>서비스와 <b>같은 상수</b>를 참조한다. 값을 복사하면 같은 어긋남이 다시 난다.
   */
  private static LocalDate today() {
    return LocalDate.now(ScheduleReminderService.KST);
  }

  @Test
  void todayScheduleSendsDdayReminderToAllRoomMembers() {
    Room room = activeRoom();
    memberWithToken(room, "uid-dday-a", "token-dday-a");
    memberWithToken(room, "uid-dday-b", "token-dday-b");
    scheduleRepository.save(new Schedule(room, "오늘 미팅", today(), null, null, null, null, null));

    scheduleReminderService.sendDailyScheduleReminders();

    assertThat(pushSender.sentToTokens()).containsExactlyInAnyOrder("token-dday-a", "token-dday-b");
    assertThat(pushSender.sent().getFirst().title()).isEqualTo("오늘이에요! 일정 잊지 마세요 ⏰");
    assertThat(pushSender.sent().getFirst().body()).isEqualTo("오늘 미팅 · " + room.getName());
  }

  /** 2026-08-09 문구 개편 — 시간·장소가 있으면 2번째 줄에 있는 것만 이어 붙인다. */
  @Test
  void scheduleWithTimeAndPlaceAddsSecondLine() {
    Room room = activeRoom();
    memberWithToken(room, "uid-dday-time-place", "token-dday-time-place");
    scheduleRepository.save(
        new Schedule(
            room, "정기 회의", today(), java.time.LocalTime.of(15, 0), null, null, null, "강남역 스터디카페"));

    scheduleReminderService.sendDailyScheduleReminders();

    assertThat(pushSender.sent().getFirst().body())
        .isEqualTo("정기 회의 · " + room.getName() + "\n오후 3시 · 강남역 스터디카페");
  }

  /** 시간만 있고 장소가 없으면 2번째 줄엔 시간만. 분이 0이 아니면 "m분"까지 붙는다. */
  @Test
  void scheduleWithOnlyTimeOmitsPlaceFromSecondLine() {
    Room room = activeRoom();
    memberWithToken(room, "uid-dday-time-only", "token-dday-time-only");
    scheduleRepository.save(
        new Schedule(
            room, "오전 스크럼", today(), java.time.LocalTime.of(9, 30), null, null, null, null));

    scheduleReminderService.sendDailyScheduleReminders();

    assertThat(pushSender.sent().getFirst().body())
        .isEqualTo("오전 스크럼 · " + room.getName() + "\n오전 9시 30분");
  }

  @Test
  void tomorrowScheduleSendsDayBeforeReminder() {
    Room room = activeRoom();
    memberWithToken(room, "uid-daybefore-a", "token-daybefore-a");
    scheduleRepository.save(
        new Schedule(room, "내일 워크숍", today().plusDays(1), null, null, null, null, null));

    scheduleReminderService.sendDailyScheduleReminders();

    assertThat(pushSender.sentToTokens()).containsExactly("token-daybefore-a");
    assertThat(pushSender.sent().getFirst().title()).isEqualTo("내일 일정 미리 알려드려요 📅");
    assertThat(pushSender.sent().getFirst().body()).isEqualTo("내일 워크숍 · " + room.getName());
  }

  @Test
  void scheduleTwoDaysAheadSendsNoReminderYet() {
    Room room = activeRoom();
    memberWithToken(room, "uid-future-a", "token-future-a");
    scheduleRepository.save(
        new Schedule(room, "모레 행사", today().plusDays(2), null, null, null, null, null));

    scheduleReminderService.sendDailyScheduleReminders();

    assertThat(pushSender.sentToTokens()).isEmpty();
  }

  /**
   * {@code Room.status}는 요청 시점에만 lazy 갱신되므로, 아무도 열어보지 않아 여전히 ACTIVE로 남아 있는 종료된 방도 실제 {@code
   * endDate} 기준으로는 제외돼야 한다({@link ScheduleRepository#findByDateForActiveRooms}).
   */
  @Test
  void scheduleInEndedRoomSendsNoReminder() {
    Room room =
        roomRepository.save(
            new Room(
                "종료된 방-" + (++counter),
                null,
                "목표",
                null,
                today().minusDays(20),
                today().minusDays(1)));
    memberWithToken(room, "uid-ended-a", "token-ended-a");
    scheduleRepository.save(new Schedule(room, "지난 일정", today(), null, null, null, null, null));

    scheduleReminderService.sendDailyScheduleReminders();

    assertThat(pushSender.sentToTokens()).isEmpty();
  }

  /** Redis SETNX 기반 멱등키(2026-08-05 확정) — 08:00 직후 재기동·수동 재실행에도 같은 날 같은 일정은 두 번 나가지 않는다. */
  @Test
  void callingBatchTwiceOnSameDaySendsReminderOnlyOnce() {
    Room room = activeRoom();
    memberWithToken(room, "uid-dedup-a", "token-dedup-a");
    scheduleRepository.save(new Schedule(room, "중복 방지 확인", today(), null, null, null, null, null));

    scheduleReminderService.sendDailyScheduleReminders();
    scheduleReminderService.sendDailyScheduleReminders();

    assertThat(pushSender.sentToTokens()).containsExactly("token-dedup-a");
  }

  @Test
  @Transactional
  void scheduleDdayDisabledForOneMemberSkipsOnlyThatMember() {
    Room room = activeRoom();
    User enabled = memberWithToken(room, "uid-dday-on", "token-dday-on");
    User disabled = memberWithToken(room, "uid-dday-off", "token-dday-off");
    NotificationSetting settings = new NotificationSetting(disabled);
    settings.updateSettings(true, true, true, false, true, true, true, true);
    notificationSettingRepository.save(settings);
    scheduleRepository.save(new Schedule(room, "설정 테스트", today(), null, null, null, null, null));

    scheduleReminderService.sendDailyScheduleReminders();

    assertThat(pushSender.sentToTokens()).containsExactly(enabled.getFcmToken());
    assertThat(pushSender.sentToTokens()).doesNotContain(disabled.getFcmToken());
  }
}
