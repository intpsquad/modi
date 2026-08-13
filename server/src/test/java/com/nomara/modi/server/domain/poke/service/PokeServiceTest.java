package com.nomara.modi.server.domain.poke.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.notification.entity.Notification;
import com.nomara.modi.server.domain.notification.entity.NotificationSetting;
import com.nomara.modi.server.domain.notification.repository.NotificationRepository;
import com.nomara.modi.server.domain.notification.repository.NotificationSettingRepository;
import com.nomara.modi.server.domain.poke.dto.PokeResponse;
import com.nomara.modi.server.domain.poke.entity.Poke;
import com.nomara.modi.server.domain.poke.entity.PokeType;
import com.nomara.modi.server.domain.poke.repository.PokeRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
import com.nomara.modi.server.support.FakePushSenderConfig;
import com.nomara.modi.server.support.RecordingPushSender;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Import;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * specs/0011-멤버-투두-콕찌르기.md 콕찌르기 발송 로직. 실제 FCM을 부르지 않고 호출을 기록하는 가짜({@link RecordingPushSender})로
 * 대체한다(전례: TodoSuggestionServiceTest의 RecordingClient). 스키마 자체는 SchemaValidationTest가 검증하므로 H2로 빠르게
 * 돈다. 레이트리밋은 진짜 Redis(Testcontainers)가 있어야 검증되므로 컨테이너를 띄운다.
 */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(FakePushSenderConfig.class)
class PokeServiceTest {

  @Container
  @ServiceConnection(name = "redis")
  static GenericContainer<?> redis =
      new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
  }

  @Autowired private PokeService pokeService;
  @Autowired private RecordingPushSender pushSender;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private PokeRepository pokeRepository;
  @Autowired private NotificationSettingRepository notificationSettingRepository;
  @Autowired private NotificationRepository notificationRepository;
  @Autowired private ActivityService activityService;

  private static int counter = 0;

  @BeforeEach
  void clearPushes() {
    pushSender.clear();
  }

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter), null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10)));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  @Test
  void sendPokeCreatesPokeRowWithPokeType() {
    Room room = room();
    User from = user("uid-poke-from");
    User to = user("uid-poke-to");
    roomMemberRepository.save(new RoomMember(room, from));
    roomMemberRepository.save(new RoomMember(room, to));

    PokeResponse response = pokeService.sendPoke(from.getId(), room.getId(), to.getId());

    Poke saved = pokeRepository.findById(response.id()).orElseThrow();
    assertThat(saved.getType()).isEqualTo(PokeType.POKE);
    assertThat(saved.getFromUser().getId()).isEqualTo(from.getId());
    assertThat(saved.getToUser().getId()).isEqualTo(to.getId());
  }

  /** 홈 활동 피드(2026-08-06, docs/backend/home-activity-feed.md) POKE — actor=보낸 사람. */
  @Test
  void sendPokeRecordsPokeActivityWithSenderAsActorAndTargetAsTargetName() {
    Room room = room();
    User from = user("uid-poke-activity-from");
    User to = user("uid-poke-activity-to");
    roomMemberRepository.save(new RoomMember(room, from));
    roomMemberRepository.save(new RoomMember(room, to));

    pokeService.sendPoke(from.getId(), room.getId(), to.getId());

    assertThat(activityService.getRecentActivities(room))
        .anySatisfy(
            a -> {
              assertThat(a.type()).isEqualTo("POKE");
              assertThat(a.actorUserId()).isEqualTo(from.getId());
              assertThat(a.targetName()).isEqualTo(to.getNickname());
            });
  }

  /** POKE_ACCUMULATED — 5의 배수(마일스톤)에서만 기록되고, actor는 "받은" 쪽이다. */
  @Test
  void pokeAccumulatedOnlyRecordsAtMilestoneWithReceiverAsActor() {
    Room room = room();
    User from = user("uid-poke-milestone-from");
    User to = user("uid-poke-milestone-to");
    roomMemberRepository.save(new RoomMember(room, from));
    roomMemberRepository.save(new RoomMember(room, to));

    for (int i = 0; i < 4; i++) {
      pokeService.sendPoke(from.getId(), room.getId(), to.getId());
    }
    assertThat(activityService.getRecentActivities(room))
        .noneMatch(a -> a.type().equals("POKE_ACCUMULATED"));

    pokeService.sendPoke(from.getId(), room.getId(), to.getId());

    assertThat(activityService.getRecentActivities(room))
        .anySatisfy(
            a -> {
              assertThat(a.type()).isEqualTo("POKE_ACCUMULATED");
              assertThat(a.actorUserId()).isEqualTo(to.getId());
              assertThat(a.count()).isEqualTo(5);
            });
  }

  @Test
  void sendPokeCallsPushSenderWhenEnabledAndTokenPresent() {
    Room room = room();
    User from = user("uid-poke-notify-from");
    User to = user("uid-poke-notify-to");
    to.updateFcmToken("token-abc");
    userRepository.save(to);
    roomMemberRepository.save(new RoomMember(room, from));
    roomMemberRepository.save(new RoomMember(room, to));

    pokeService.sendPoke(from.getId(), room.getId(), to.getId());

    assertThat(pushSender.sentToTokens()).containsExactly("token-abc");
    assertThat(pushSender.sent().getFirst().title()).isEqualTo(from.getNickname() + "님이 콕! 👀");
    assertThat(pushSender.sent().getFirst().body())
        .isEqualTo(room.getName() + " · 아직 안 끝난 투두 확인해볼까요?");

    // 알림 내역(specs/0017)에도 같은 문구·방으로 기록된다 — PushNotifier 배선 확인(다른 4개
    // 발송 지점은 NotificationHistoryServiceTest가 서비스 단위로 직접 검증한다).
    List<Notification> history =
        notificationRepository.findByUserIdOrderByCreatedAtDesc(to.getId(), PageRequest.of(0, 10));
    assertThat(history).hasSize(1);
    assertThat(history.getFirst().getType()).isEqualTo("POKE");
    assertThat(history.getFirst().getTitle()).isEqualTo(from.getNickname() + "님이 콕! 👀");
    assertThat(history.getFirst().getRoom().getId()).isEqualTo(room.getId());
  }

  /**
   * NotificationSetting을 미리 신규 저장해야 하는 유일한 테스트라 트랜잭션 경계를 명시한다 — 그래야 User 연관관계가 detach되지 않는다(실측: 미지정
   * 시 Hibernate가 이미 존재하는 User를 다시 insert하려다 PK 충돌).
   */
  @Test
  @Transactional
  void sendPokeSkipsPushWhenPokeDisabledButStillCreatesRow() {
    Room room = room();
    User from = user("uid-poke-disabled-from");
    User to = user("uid-poke-disabled-to");
    to.updateFcmToken("token-xyz");
    userRepository.save(to);
    roomMemberRepository.save(new RoomMember(room, from));
    roomMemberRepository.save(new RoomMember(room, to));
    NotificationSetting settings = new NotificationSetting(to);
    settings.updateSettings(true, false);
    notificationSettingRepository.save(settings);

    PokeResponse response = pokeService.sendPoke(from.getId(), room.getId(), to.getId());

    assertThat(pokeRepository.findById(response.id())).isPresent();
    assertThat(pushSender.sentToTokens()).isEmpty();
  }

  /**
   * specs/0012-설정.md — "전체 알림"은 개별을 막는 마스터 스위치가 아니라 일괄 스위치일 뿐이다(2026-08-08 결정). 전체가 꺼져 있어도
   * pokeEnabled=true면 발송한다 — notification-handoff.md E항목의 핵심 회귀 포인트("전체 OFF + 개별 일부만 ON → 켠 것만
   * 수신"). 이 테스트는 원래 반대(전체 꺼지면 개별 무시하고 차단)를 검증했으나, 그 마스터 스위치 동작 자체가 폐기됐다.
   */
  @Test
  @Transactional
  void sendPokeSendsPushWhenAllDisabledButPokeEnabled() {
    Room room = room();
    User from = user("uid-poke-alloff-from");
    User to = user("uid-poke-alloff-to");
    to.updateFcmToken("token-alloff");
    userRepository.save(to);
    roomMemberRepository.save(new RoomMember(room, from));
    roomMemberRepository.save(new RoomMember(room, to));
    NotificationSetting settings = new NotificationSetting(to);
    settings.updateSettings(false, true);
    notificationSettingRepository.save(settings);

    PokeResponse response = pokeService.sendPoke(from.getId(), room.getId(), to.getId());

    assertThat(pokeRepository.findById(response.id())).isPresent();
    assertThat(pushSender.sentToTokens()).containsExactly("token-alloff");
  }

  @Test
  void sendPokeSkipsPushWhenTargetHasNoFcmToken() {
    Room room = room();
    User from = user("uid-poke-notoken-from");
    User to = user("uid-poke-notoken-to");
    roomMemberRepository.save(new RoomMember(room, from));
    roomMemberRepository.save(new RoomMember(room, to));

    pokeService.sendPoke(from.getId(), room.getId(), to.getId());

    assertThat(pushSender.sentToTokens()).isEmpty();
  }

  @Test
  void nonMemberTargetReturnsNotFound() {
    Room room = room();
    User from = user("uid-poke-target-missing");
    roomMemberRepository.save(new RoomMember(room, from));

    ApiException ex =
        catchThrowableOfType(
            () -> pokeService.sendPoke(from.getId(), room.getId(), "uid-not-a-member"),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void nonMemberRequesterIsForbidden() {
    Room room = room();
    User to = user("uid-poke-outsider-target");
    roomMemberRepository.save(new RoomMember(room, to));

    ApiException ex =
        catchThrowableOfType(
            () -> pokeService.sendPoke("uid-poke-outsider", room.getId(), to.getId()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  /** 발신자+대상 쌍 기준 30초당 10회(2026-08-03 확정, specs/OPEN.md) — 11번째부터 429. */
  @Test
  void eleventhPokeToSamePairWithinWindowIsRateLimited() {
    Room room = room();
    User from = user("uid-poke-rate-from");
    User to = user("uid-poke-rate-to");
    roomMemberRepository.save(new RoomMember(room, from));
    roomMemberRepository.save(new RoomMember(room, to));

    for (int i = 0; i < 10; i++) {
      pokeService.sendPoke(from.getId(), room.getId(), to.getId());
    }

    ApiException ex =
        catchThrowableOfType(
            () -> pokeService.sendPoke(from.getId(), room.getId(), to.getId()), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
  }

  @Test
  void rateLimitIsScopedPerSenderTargetPair() {
    Room room = room();
    User from = user("uid-poke-rate-pair-from");
    User toA = user("uid-poke-rate-pair-to-a");
    User toB = user("uid-poke-rate-pair-to-b");
    roomMemberRepository.save(new RoomMember(room, from));
    roomMemberRepository.save(new RoomMember(room, toA));
    roomMemberRepository.save(new RoomMember(room, toB));

    for (int i = 0; i < 10; i++) {
      pokeService.sendPoke(from.getId(), room.getId(), toA.getId());
    }

    // toA는 막혀 있어야 하고, 같은 발신자라도 다른 대상(toB)이나 반대 방향(toA→from)은 별도 카운터라 정상 동작해야 한다.
    ApiException blocked =
        catchThrowableOfType(
            () -> pokeService.sendPoke(from.getId(), room.getId(), toA.getId()),
            ApiException.class);
    assertThat(blocked.getStatus()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);

    PokeResponse toDifferentTarget = pokeService.sendPoke(from.getId(), room.getId(), toB.getId());
    PokeResponse reverseDirection = pokeService.sendPoke(toA.getId(), room.getId(), from.getId());

    assertThat(pokeRepository.findById(toDifferentTarget.id())).isPresent();
    assertThat(pokeRepository.findById(reverseDirection.id())).isPresent();
  }
}
