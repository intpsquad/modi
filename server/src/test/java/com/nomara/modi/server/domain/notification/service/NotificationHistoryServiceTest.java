package com.nomara.modi.server.domain.notification.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.notification.dto.NotificationResponse;
import com.nomara.modi.server.domain.notification.repository.NotificationRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.notification.PushType;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** 알림 내역(specs/0017-알림-내역.md, S-41)을 실제 Postgres(Testcontainers)로 검증한다. */
@Testcontainers
@SpringBootTest
class NotificationHistoryServiceTest {

  @Container @ServiceConnection
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.enabled", () -> "true");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
  }

  @Autowired private NotificationHistoryService notificationHistoryService;
  @Autowired private NotificationRepository notificationRepository;
  @Autowired private RoomRepository roomRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private JdbcTemplate jdbcTemplate;

  private static int counter = 0;

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter), null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10)));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  @Test
  void recordedNotificationAppearsInListUnread() {
    Room room = room();
    User target = user("uid-noti-record");

    notificationHistoryService.record(target, PushType.POKE, room, "제목", "본문");

    List<NotificationResponse> list = notificationHistoryService.list(target.getId());
    assertThat(list).hasSize(1);
    NotificationResponse item = list.getFirst();
    assertThat(item.type()).isEqualTo("POKE");
    assertThat(item.title()).isEqualTo("제목");
    assertThat(item.body()).isEqualTo("본문");
    assertThat(item.roomId()).isEqualTo(room.getId());
    assertThat(item.read()).isFalse();
  }

  @Test
  void roomNullIsAllowedForArchiveAnalysisDone() {
    User target = user("uid-noti-no-room");

    notificationHistoryService.record(
        target, PushType.ARCHIVE_ANALYSIS_DONE, null, "「자료」 분석이 끝났어요", "모아보기에서 확인해 보세요");

    NotificationResponse item = notificationHistoryService.list(target.getId()).getFirst();
    assertThat(item.roomId()).isNull();
  }

  @Test
  void listIsOrderedNewestFirst() {
    Room room = room();
    User target = user("uid-noti-order");
    notificationHistoryService.record(target, PushType.POKE, room, "먼저", "본문");
    notificationHistoryService.record(target, PushType.POKE, room, "나중", "본문");
    // 같은 트랜잭션 안에서 연달아 저장되면 created_at이 같은 순간일 수 있어, id 순서로 시각을 벌려
    // 순서를 확정한다(CharacterServiceTest의 jdbcTemplate 보정과 같은 이유).
    List<NotificationResponse> beforeFix = notificationHistoryService.list(target.getId());
    Instant now = Instant.now();
    for (int i = 0; i < beforeFix.size(); i++) {
      jdbcTemplate.update(
          "update notifications set created_at = ? where id = ?",
          Timestamp.from(now.minus(beforeFix.size() - i, ChronoUnit.MINUTES)),
          beforeFix.get(beforeFix.size() - 1 - i).id());
    }

    List<NotificationResponse> list = notificationHistoryService.list(target.getId());

    assertThat(list.get(0).title()).isEqualTo("나중");
    assertThat(list.get(1).title()).isEqualTo("먼저");
  }

  @Test
  void unreadCountAndMarkAllReadRoundTrip() {
    Room room = room();
    User target = user("uid-noti-unread");
    notificationHistoryService.record(target, PushType.POKE, room, "1", "본문");
    notificationHistoryService.record(target, PushType.ASSIGNED_TODO_ADDED, room, "2", "본문");

    assertThat(notificationHistoryService.unreadCount(target.getId()).count()).isEqualTo(2);

    notificationHistoryService.markAllRead(target.getId());

    assertThat(notificationHistoryService.unreadCount(target.getId()).count()).isEqualTo(0);
    assertThat(notificationHistoryService.list(target.getId()))
        .allMatch(NotificationResponse::read);
  }

  @Test
  void markAllReadDoesNotAffectOtherUsers() {
    Room room = room();
    User target = user("uid-noti-isolated-a");
    User other = user("uid-noti-isolated-b");
    notificationHistoryService.record(target, PushType.POKE, room, "본인", "본문");
    notificationHistoryService.record(other, PushType.POKE, room, "타인", "본문");

    notificationHistoryService.markAllRead(target.getId());

    assertThat(notificationHistoryService.unreadCount(other.getId()).count()).isEqualTo(1);
  }

  /** 방이 삭제돼도 알림 기록 자체는 남고 roomId만 null이 된다(V24 마이그레이션 SET NULL). */
  @Test
  void roomIdBecomesNullWhenRoomIsDeleted() {
    Room room = room();
    User target = user("uid-noti-room-deleted");
    notificationHistoryService.record(target, PushType.ROOM_MEMBER_JOINED, room, "제목", "본문");

    roomRepository.delete(room);

    NotificationResponse item = notificationHistoryService.list(target.getId()).getFirst();
    assertThat(item.roomId()).isNull();
  }

  /**
   * {@code deleteByCreatedAtBefore}는 파생 delete 쿼리라 엔티티를 로드해 {@code EntityManager.remove}를 호출한다 —
   * 트랜잭션이 열려 있어야 한다(운영에서는 {@code NotificationRetentionScheduler}의 {@code @Transactional}이 연다,
   * {@code UserActivityRepository.deleteByCreatedAtBefore}와 같은 제약).
   */
  @Test
  @Transactional
  void oldNotificationsArePurgedByRetentionCutoff() {
    Room room = room();
    User target = user("uid-noti-retention");
    notificationHistoryService.record(target, PushType.POKE, room, "오래됨", "본문");
    Long oldId = notificationHistoryService.list(target.getId()).getFirst().id();
    jdbcTemplate.update(
        "update notifications set created_at = ? where id = ?",
        Timestamp.from(Instant.now().minus(91, ChronoUnit.DAYS)),
        oldId);
    notificationHistoryService.record(target, PushType.POKE, room, "최근", "본문");

    long deleted =
        notificationRepository.deleteByCreatedAtBefore(Instant.now().minus(90, ChronoUnit.DAYS));

    assertThat(deleted).isEqualTo(1);
    List<NotificationResponse> remaining = notificationHistoryService.list(target.getId());
    assertThat(remaining).hasSize(1);
    assertThat(remaining.getFirst().title()).isEqualTo("최근");
  }
}
