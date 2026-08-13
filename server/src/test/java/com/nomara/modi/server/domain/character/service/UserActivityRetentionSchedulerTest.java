package com.nomara.modi.server.domain.character.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.character.entity.UserActivity;
import com.nomara.modi.server.domain.character.entity.UserActivityKind;
import com.nomara.modi.server.domain.character.repository.UserActivityRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
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

/** 접속·조회 로그 90일 보존(specs/0016-협업-캐릭터.md, 백엔드 요청 2026-08-07)을 실제 Postgres로 검증한다. */
@Testcontainers
@SpringBootTest
class UserActivityRetentionSchedulerTest {

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

  @Autowired private UserActivityRetentionScheduler scheduler;
  @Autowired private UserActivityRepository userActivityRepository;
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

  private void backdate(Long id, Instant when) {
    jdbcTemplate.update(
        "update user_activity set created_at = ? where id = ?", Timestamp.from(when), id);
  }

  @Test
  void purgesOnlyEventsOlderThanNinetyDays() {
    Room room = room();
    User user = user("uid-retention");
    UserActivity old =
        userActivityRepository.save(new UserActivity(user, room, UserActivityKind.ROOM_VIEW, null));
    UserActivity recent =
        userActivityRepository.save(new UserActivity(user, room, UserActivityKind.ROOM_VIEW, null));
    backdate(old.getId(), Instant.now().minus(Duration.ofDays(91)));
    backdate(recent.getId(), Instant.now().minus(Duration.ofDays(89)));

    scheduler.purgeOldEvents();

    assertThat(userActivityRepository.findById(old.getId())).isEmpty();
    assertThat(userActivityRepository.findById(recent.getId())).isPresent();
  }
}
