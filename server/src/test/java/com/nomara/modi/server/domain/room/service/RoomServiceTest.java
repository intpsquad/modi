package com.nomara.modi.server.domain.room.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.activity.dto.ActivityResponse;
import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.notification.entity.NotificationSetting;
import com.nomara.modi.server.domain.notification.repository.NotificationSettingRepository;
import com.nomara.modi.server.domain.room.dto.CreateRoomRequest;
import com.nomara.modi.server.domain.room.dto.InviteCodePreviewResponse;
import com.nomara.modi.server.domain.room.dto.InviteCodeResponse;
import com.nomara.modi.server.domain.room.dto.MemberBriefResponse;
import com.nomara.modi.server.domain.room.dto.MemberProgress;
import com.nomara.modi.server.domain.room.dto.PastRoomSummaryResponse;
import com.nomara.modi.server.domain.room.dto.RoomResponse;
import com.nomara.modi.server.domain.room.dto.RoomSummaryResponse;
import com.nomara.modi.server.domain.room.dto.UpdateRoomRequest;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.entity.RoomStatus;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.entity.TodoAssignee;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
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
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 방 생성/참여(specs/0004-방-생성-참여.md)를 실제 Postgres+Redis(Testcontainers)로 검증한다. HTTP 계층은 미인증 401만
 * 확인하고(실제 Firebase 토큰 없이는 인증 성공 경로를 재현할 수 없음), 나머지 비즈니스 로직은 서비스 레이어를 직접 호출해 검증한다.
 */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(FakePushSenderConfig.class)
class RoomServiceTest {

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

  private static final String ALLOWED_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

  @Autowired private TestRestTemplate restTemplate;
  @Autowired private RoomService roomService;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private TodoRepository todoRepository;
  @Autowired private TodoAssigneeRepository todoAssigneeRepository;
  @Autowired private NotificationSettingRepository notificationSettingRepository;
  @Autowired private RecordingPushSender pushSender;
  @Autowired private ActivityService activityService;
  @Autowired private ArchiveFolderRepository archiveFolderRepository;

  @BeforeEach
  void clearPushes() {
    pushSender.clear();
  }

  @Test
  void createRoomWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.postForEntity("/rooms", null, String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void joinWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.postForEntity("/invite-codes/ABCDEF/join", null, String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void createRoomAddsCreatorAsMemberAndIssuesInviteCode() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "스프린트 방", "매일 커밋", null, LocalDate.now(), LocalDate.now().plusDays(30), null);

    RoomResponse response = roomService.createRoom("uid-creator", "생성자", request);

    assertThat(response.inviteCode()).hasSize(6);
    assertThat(response.inviteCode().chars().allMatch(c -> ALLOWED_CODE_CHARS.indexOf(c) >= 0))
        .isTrue();
    assertThat(userRepository.existsById("uid-creator")).isTrue();
    assertThat(roomMemberRepository.existsById(new RoomMemberId(response.id(), "uid-creator")))
        .isTrue();
  }

  /** 방마다 폴더 최소 1개 보장(백엔드 요청, 2026-08-07) — 생성 즉시 "기본" 폴더가 함께 생긴다. */
  @Test
  void creatingRoomCreatesDefaultArchiveFolder() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "기본폴더 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);

    RoomResponse response = roomService.createRoom("uid-default-folder-creator", "생성자", request);

    assertThat(archiveFolderRepository.findByRoomIdOrderByCreatedAtAsc(response.id()))
        .extracting(ArchiveFolder::getName)
        .containsExactly(ArchiveFolder.DEFAULT_FOLDER_NAME);
  }

  /** 홈 활동 피드(2026-08-06, docs/backend/home-activity-feed.md) MEMBER_JOINED — 방 생성자도 대상. */
  @Test
  void creatingRoomRecordsMemberJoinedActivityForCreator() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "활동피드 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);

    RoomResponse response = roomService.createRoom("uid-activity-creator", "생성자", request);

    Room room = roomRepository.findById(response.id()).orElseThrow();
    assertThat(activityService.getRecentActivities(room))
        .anySatisfy(
            a -> {
              assertThat(a.type()).isEqualTo("MEMBER_JOINED");
              assertThat(a.actorUserId()).isEqualTo("uid-activity-creator");
            });
  }

  /** 초대코드로 참여한 사람도 MEMBER_JOINED가 남는다(재참여는 no-op이라 다시 남지 않음). */
  @Test
  void joiningRoomRecordsMemberJoinedActivityForJoinerOnlyOnce() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "활동피드 참여 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-activity-join-creator", "생성자", request);

    roomService.joinRoom("uid-activity-joiner", "참여자", created.inviteCode());
    roomService.joinRoom("uid-activity-joiner", "참여자", created.inviteCode());

    Room room = roomRepository.findById(created.id()).orElseThrow();
    List<ActivityResponse> joinedByJoiner =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("MEMBER_JOINED"))
            .filter(a -> "uid-activity-joiner".equals(a.actorUserId()))
            .toList();
    assertThat(joinedByJoiner).hasSize(1);
  }

  @Test
  void previewInviteReturnsRoomSummaryForValidCode() {
    LocalDate startDate = LocalDate.now();
    LocalDate endDate = startDate.plusDays(10);
    CreateRoomRequest request =
        new CreateRoomRequest("미리보기 방", "목표 달성", null, startDate, endDate, null);
    RoomResponse created = roomService.createRoom("uid-preview-creator", "생성자", request);

    InviteCodePreviewResponse preview = roomService.previewInvite(created.inviteCode());

    assertThat(preview.roomId()).isEqualTo(created.id());
    assertThat(preview.name()).isEqualTo("미리보기 방");
    assertThat(preview.goal()).isEqualTo("목표 달성");
    // S-11 확인 모달의 "멤버 N명 · 기간" 표기용 필드.
    assertThat(preview.memberCount()).isEqualTo(1);
    assertThat(preview.startDate()).isEqualTo(startDate);
    assertThat(preview.endDate()).isEqualTo(endDate);
  }

  @Test
  void previewInviteWithUnknownCodeThrowsNotFound() {
    ApiException ex =
        catchThrowableOfType(() -> roomService.previewInvite("ZZZZZZ"), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void joinRoomAddsMemberAndIsIdempotentOnRetry() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "참여 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-join-creator", "생성자", request);

    roomService.joinRoom("uid-joiner", "참여자", created.inviteCode());
    roomService.joinRoom("uid-joiner", "참여자", created.inviteCode());

    assertThat(roomMemberRepository.existsById(new RoomMemberId(created.id(), "uid-joiner")))
        .isTrue();
  }

  /** full_spec.md:205, specs/0015-알림-트리거.md — 참여 시 기존 멤버에게만 알림, 참여자 본인은 대상에서 빠진다. */
  @Test
  void joinRoomNotifiesExistingMembersButNotTheJoiner() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "입장 알림 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-join-notify-creator", "생성자", request);
    User creator = userRepository.findById("uid-join-notify-creator").orElseThrow();
    creator.updateFcmToken("token-join-creator");
    userRepository.save(creator);
    // 참여자도 토큰을 갖게 해둔다 — "토큰이 없어서" 안 간 게 아니라 "대상 목록에서 빠져서" 안 갔음을 증명하기 위해서다.
    User joiner = userRepository.save(new User("uid-join-notify-joiner", "참여자", null));
    joiner.updateFcmToken("token-join-joiner");
    userRepository.save(joiner);

    roomService.joinRoom("uid-join-notify-joiner", "참여자", created.inviteCode());

    assertThat(pushSender.sentToTokens()).containsExactly("token-join-creator");
    assertThat(pushSender.sent().getFirst().title()).isEqualTo("새 팀원이 왔어요 🎉");
    assertThat(pushSender.sent().getFirst().body())
        .isEqualTo(joiner.getNickname() + "님이 합류했어요 · " + created.name());
  }

  @Test
  void joinRoomIsIdempotentAndSendsNoNotificationOnRepeatedJoin() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "재참여 알림 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-rejoin-creator", "생성자", request);
    User creator = userRepository.findById("uid-rejoin-creator").orElseThrow();
    creator.updateFcmToken("token-rejoin-creator");
    userRepository.save(creator);
    roomService.joinRoom("uid-rejoin-joiner", "참여자", created.inviteCode());
    assertThat(pushSender.sentToTokens()).containsExactly("token-rejoin-creator");
    pushSender.clear();

    roomService.joinRoom("uid-rejoin-joiner", "참여자", created.inviteCode());

    assertThat(pushSender.sentToTokens()).isEmpty();
  }

  @Test
  @Transactional
  void joinRoomSkipsNotificationWhenRoomMemberJoinedDisabled() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "입장 알림 끔 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-join-off-creator", "생성자", request);
    User creator = userRepository.findById("uid-join-off-creator").orElseThrow();
    creator.updateFcmToken("token-join-off-creator");
    userRepository.save(creator);
    NotificationSetting settings = new NotificationSetting(creator);
    settings.updateSettings(true, true, true, true, false, true, true, true);
    notificationSettingRepository.save(settings);

    roomService.joinRoom("uid-join-off-joiner", "참여자", created.inviteCode());

    assertThat(pushSender.sentToTokens()).isEmpty();
  }

  @Test
  void joinEndedRoomThrowsConflict() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "종료 방", "목표", null, LocalDate.now().minusDays(20), LocalDate.now().minusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-ended-creator", "생성자", request);
    Room room = roomRepository.findById(created.id()).orElseThrow();
    room.end();
    roomRepository.save(room);

    ApiException ex =
        catchThrowableOfType(
            () -> roomService.joinRoom("uid-late-joiner", "참여자", created.inviteCode()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.CONFLICT);
  }

  @Test
  void joinWithUnknownCodeThrowsNotFound() {
    ApiException ex =
        catchThrowableOfType(
            () -> roomService.joinRoom("uid-x", "x", "ZZZZZZ"), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void listMyRoomsReturnsOnlyRoomsUserBelongsTo() {
    CreateRoomRequest ownRequest =
        new CreateRoomRequest(
            "내 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse ownRoom = roomService.createRoom("uid-list-owner", "생성자", ownRequest);

    CreateRoomRequest otherRequest =
        new CreateRoomRequest(
            "남의 방", "목표2", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    roomService.createRoom("uid-list-other", "다른유저", otherRequest);

    var summaries = roomService.listMyRooms("uid-list-owner");

    assertThat(summaries).extracting(RoomSummaryResponse::id).containsExactly(ownRoom.id());
  }

  @Test
  void listMyRoomsIncludesFieldsNeededToPrefillRoomSettings() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "상세 설정 방",
            "짧은 목표",
            "기존 목표 상세 설명",
            LocalDate.now(),
            LocalDate.now().plusDays(10),
            "https://example.com/cover.jpg");
    roomService.createRoom("uid-settings-owner", "생성자", request);

    RoomSummaryResponse summary = roomService.listMyRooms("uid-settings-owner").getFirst();

    assertThat(summary.goalDetail()).isEqualTo("기존 목표 상세 설명");
    assertThat(summary.coverImage()).isEqualTo("https://example.com/cover.jpg");
  }

  @Test
  void listMyRoomsWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.getForEntity("/rooms", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void listMembersReturnsAllRoomMembers() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "멤버 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-members-creator", "생성자", request);
    roomService.joinRoom("uid-members-joiner", "참여자", created.inviteCode());

    var members = roomService.listMembers("uid-members-creator", created.id());

    assertThat(members)
        .extracting(MemberBriefResponse::userId)
        .containsExactlyInAnyOrder("uid-members-creator", "uid-members-joiner");
  }

  @Test
  void nonMemberCannotListMembers() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "비멤버 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-members-owner", "생성자", request);

    ApiException ex =
        catchThrowableOfType(
            () -> roomService.listMembers("uid-members-outsider", created.id()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void listMembersWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.getForEntity("/rooms/1/members", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void listMemberProgressSortsByCompletionRateDescendingAndIncludesZeroAssignedMembers() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "진행률 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-progress-half", "절반담당", request);
    roomService.joinRoom("uid-progress-full", "전부완료", created.inviteCode());
    roomService.joinRoom("uid-progress-none", "미배정", created.inviteCode());
    Room room = roomRepository.findById(created.id()).orElseThrow();
    User half = userRepository.findById("uid-progress-half").orElseThrow();
    User full = userRepository.findById("uid-progress-full").orElseThrow();

    Todo halfDone = todoRepository.save(new Todo(room, null, "half-done", null));
    halfDone.complete();
    todoRepository.save(halfDone);
    todoAssigneeRepository.save(new TodoAssignee(halfDone, half));
    Todo halfTodo = todoRepository.save(new Todo(room, null, "half-todo", null));
    todoAssigneeRepository.save(new TodoAssignee(halfTodo, half));

    Todo fullDone = todoRepository.save(new Todo(room, null, "full-done", null));
    fullDone.complete();
    todoRepository.save(fullDone);
    todoAssigneeRepository.save(new TodoAssignee(fullDone, full));

    var progress = roomService.listMemberProgress("uid-progress-half", created.id());

    assertThat(progress)
        .extracting(MemberProgress::userId)
        .containsExactly("uid-progress-full", "uid-progress-half", "uid-progress-none");
    MemberProgress none =
        progress.stream()
            .filter(p -> p.userId().equals("uid-progress-none"))
            .findFirst()
            .orElseThrow();
    assertThat(none.assignedTotal()).isZero();
    assertThat(none.assignedDone()).isZero();
  }

  @Test
  void nonMemberCannotListMemberProgress() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "진행률 비멤버 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-progress-owner", "생성자", request);

    ApiException ex =
        catchThrowableOfType(
            () -> roomService.listMemberProgress("uid-progress-outsider", created.id()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void listMemberProgressWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.getForEntity("/rooms/1/members/progress", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void updateRoomChangesFieldsAndPersists() {
    CreateRoomRequest createRequest =
        new CreateRoomRequest(
            "원래 이름", "원래 목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-update-owner", "생성자", createRequest);

    UpdateRoomRequest updateRequest =
        new UpdateRoomRequest(
            "바뀐 이름",
            "바뀐 목표",
            "바뀐 설명",
            LocalDate.now().plusDays(1),
            LocalDate.now().plusDays(20),
            "https://example.com/cover.png");
    RoomResponse updated = roomService.updateRoom("uid-update-owner", created.id(), updateRequest);

    assertThat(updated.name()).isEqualTo("바뀐 이름");
    assertThat(updated.goal()).isEqualTo("바뀐 목표");
    assertThat(updated.goalDetail()).isEqualTo("바뀐 설명");
    assertThat(updated.coverImage()).isEqualTo("https://example.com/cover.png");

    Room persisted = roomRepository.findById(created.id()).orElseThrow();
    assertThat(persisted.getName()).isEqualTo("바뀐 이름");
    assertThat(persisted.getStartDate()).isEqualTo(LocalDate.now().plusDays(1));
    assertThat(persisted.getEndDate()).isEqualTo(LocalDate.now().plusDays(20));
  }

  @Test
  void updatingEndedRoomRestartsItWithExistingMembers() {
    CreateRoomRequest createRequest =
        new CreateRoomRequest(
            "종료된 방",
            "원래 목표",
            null,
            LocalDate.now().minusDays(20),
            LocalDate.now().minusDays(1),
            null);
    RoomResponse created = roomService.createRoom("uid-restart-owner", "생성자", createRequest);
    roomService.listMyRooms("uid-restart-owner");
    assertThat(roomRepository.findById(created.id()).orElseThrow().getStatus())
        .isEqualTo(RoomStatus.ENDED);

    LocalDate restartedAt = LocalDate.now();
    roomService.updateRoom(
        "uid-restart-owner",
        created.id(),
        new UpdateRoomRequest(
            "재시작한 방", "새 목표", "새 설명", restartedAt, restartedAt.plusDays(30), null));

    Room restarted = roomRepository.findById(created.id()).orElseThrow();
    assertThat(restarted.getStatus()).isEqualTo(RoomStatus.ACTIVE);
    assertThat(restarted.getStartDate()).isEqualTo(restartedAt);
    assertThat(roomMemberRepository.existsById(new RoomMemberId(created.id(), "uid-restart-owner")))
        .isTrue();
  }

  @Test
  void updateRoomRejectsInvalidDateOrder() {
    CreateRoomRequest createRequest =
        new CreateRoomRequest(
            "날짜 검증 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-update-baddate", "생성자", createRequest);

    UpdateRoomRequest updateRequest =
        new UpdateRoomRequest(
            "이름", "목표", null, LocalDate.now().plusDays(10), LocalDate.now(), null);

    ApiException ex =
        catchThrowableOfType(
            () -> roomService.updateRoom("uid-update-baddate", created.id(), updateRequest),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void nonMemberCannotUpdateRoom() {
    CreateRoomRequest createRequest =
        new CreateRoomRequest(
            "비멤버 수정 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-update-room-owner", "생성자", createRequest);

    UpdateRoomRequest updateRequest =
        new UpdateRoomRequest(
            "이름", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);

    ApiException ex =
        catchThrowableOfType(
            () -> roomService.updateRoom("uid-update-room-outsider", created.id(), updateRequest),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void reissueInviteCodeInvalidatesOldCodeAndIssuesNew() {
    CreateRoomRequest createRequest =
        new CreateRoomRequest(
            "재발급 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-reissue-owner", "생성자", createRequest);
    String oldCode = created.inviteCode();

    InviteCodeResponse reissued = roomService.reissueInviteCode("uid-reissue-owner", created.id());

    assertThat(reissued.inviteCode()).hasSize(6);
    assertThat(reissued.inviteCode()).isNotEqualTo(oldCode);

    ApiException ex =
        catchThrowableOfType(
            () -> roomService.joinRoom("uid-reissue-late-joiner", "참여자", oldCode),
            ApiException.class);
    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);

    roomService.joinRoom("uid-reissue-new-joiner", "참여자", reissued.inviteCode());
    assertThat(
            roomMemberRepository.existsById(
                new RoomMemberId(created.id(), "uid-reissue-new-joiner")))
        .isTrue();
  }

  @Test
  void getInviteCodeReturnsCurrentCodeWithoutRotatingIt() {
    CreateRoomRequest createRequest =
        new CreateRoomRequest(
            "초대코드 조회 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-code-owner", "생성자", createRequest);

    InviteCodeResponse current = roomService.getInviteCode("uid-code-owner", created.id());

    assertThat(current.inviteCode()).isEqualTo(created.inviteCode());
    roomService.joinRoom("uid-code-joiner", "참여자", created.inviteCode());
  }

  @Test
  void nonMemberCannotReissueInviteCode() {
    CreateRoomRequest createRequest =
        new CreateRoomRequest(
            "재발급 비멤버 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-reissue-room-owner", "생성자", createRequest);

    ApiException ex =
        catchThrowableOfType(
            () -> roomService.reissueInviteCode("uid-reissue-outsider", created.id()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void leaveRoomRemovesMembershipWhenOtherMembersRemain() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "나가기 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-leave-stayer", "생성자", request);
    roomService.joinRoom("uid-leave-leaver", "나갈사람", created.inviteCode());

    roomService.leaveRoom("uid-leave-leaver", created.id());

    assertThat(roomMemberRepository.existsById(new RoomMemberId(created.id(), "uid-leave-leaver")))
        .isFalse();
    assertThat(roomMemberRepository.existsById(new RoomMemberId(created.id(), "uid-leave-stayer")))
        .isTrue();
    assertThat(roomRepository.findById(created.id())).isPresent();
  }

  @Test
  void leaveRoomDeletesRoomWhenLastMemberLeaves() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "마지막 나가기 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-leave-last", "생성자", request);
    Room room = roomRepository.findById(created.id()).orElseThrow();
    Todo todo = todoRepository.save(new Todo(room, null, "남을 리 없는 투두", null));

    roomService.leaveRoom("uid-leave-last", created.id());

    assertThat(roomRepository.findById(created.id())).isEmpty();
    assertThat(roomMemberRepository.existsById(new RoomMemberId(created.id(), "uid-leave-last")))
        .isFalse();
    assertThat(todoRepository.findById(todo.getId())).isEmpty();
  }

  /** full_spec.md:205, specs/0015-알림-트리거.md — 퇴장 시 남은 멤버에게만 알림, 나간 사람 본인은 대상에서 빠진다. */
  @Test
  void leaveRoomNotifiesRemainingMembersButNotTheLeaver() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "퇴장 알림 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-leave-notify-stayer", "생성자", request);
    User stayer = userRepository.findById("uid-leave-notify-stayer").orElseThrow();
    stayer.updateFcmToken("token-leave-stayer");
    userRepository.save(stayer);
    roomService.joinRoom("uid-leave-notify-leaver", "나갈사람", created.inviteCode());
    User leaver = userRepository.findById("uid-leave-notify-leaver").orElseThrow();
    leaver.updateFcmToken("token-leave-leaver");
    userRepository.save(leaver);
    pushSender.clear(); // 위 참여 알림을 걷어내고 퇴장 알림만 본다.

    roomService.leaveRoom("uid-leave-notify-leaver", created.id());

    assertThat(pushSender.sentToTokens()).containsExactly("token-leave-stayer");
    assertThat(pushSender.sent().getFirst().title()).isEqualTo(leaver.getNickname() + "님이 방을 나갔어요");
    assertThat(pushSender.sent().getFirst().body()).isEqualTo(created.name());
  }

  @Test
  void leaveRoomDeletingLastMemberSendsNoNotification() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "마지막 나가기 알림 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-leave-lastpush", "생성자", request);
    User creator = userRepository.findById("uid-leave-lastpush").orElseThrow();
    creator.updateFcmToken("token-leave-lastpush");
    userRepository.save(creator);
    pushSender.clear();

    roomService.leaveRoom("uid-leave-lastpush", created.id());

    assertThat(pushSender.sentToTokens()).isEmpty();
  }

  @Test
  void nonMemberCannotLeaveRoom() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "나가기 비멤버 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    RoomResponse created = roomService.createRoom("uid-leave-room-owner", "생성자", request);

    ApiException ex =
        catchThrowableOfType(
            () -> roomService.leaveRoom("uid-leave-outsider", created.id()), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void leaveRoomWithoutAuthReturnsUnauthorized() {
    var response =
        restTemplate.exchange("/rooms/1/members/me", HttpMethod.DELETE, null, String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void listPastRoomsReturnsOnlyEndedRoomsWithCompletionRate() {
    CreateRoomRequest activeRequest =
        new CreateRoomRequest(
            "진행중 방", "목표", null, LocalDate.now(), LocalDate.now().plusDays(10), null);
    roomService.createRoom("uid-past-owner", "생성자", activeRequest);

    CreateRoomRequest endedRequest =
        new CreateRoomRequest(
            "종료된 방",
            "목표",
            null,
            LocalDate.now().minusDays(20),
            LocalDate.now().minusDays(10),
            null);
    RoomResponse ended = roomService.createRoom("uid-past-owner", "생성자", endedRequest);
    Room endedRoom = roomRepository.findById(ended.id()).orElseThrow();
    endedRoom.end();
    roomRepository.save(endedRoom);
    Todo done = todoRepository.save(new Todo(endedRoom, null, "완료된 투두", null));
    done.complete();
    todoRepository.save(done);
    todoRepository.save(new Todo(endedRoom, null, "미완료 투두", null));

    List<PastRoomSummaryResponse> pastRooms = roomService.listPastRooms("uid-past-owner");

    assertThat(pastRooms).extracting(PastRoomSummaryResponse::id).containsExactly(ended.id());
    assertThat(pastRooms.get(0).completionRate()).isEqualTo(0.5);
  }

  @Test
  void listPastRoomsExcludesRoomsUserIsNotMemberOf() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "남의 종료된 방",
            "목표",
            null,
            LocalDate.now().minusDays(20),
            LocalDate.now().minusDays(10),
            null);
    RoomResponse created = roomService.createRoom("uid-past-other-owner", "생성자", request);
    Room room = roomRepository.findById(created.id()).orElseThrow();
    room.end();
    roomRepository.save(room);

    List<PastRoomSummaryResponse> pastRooms = roomService.listPastRooms("uid-past-outsider");

    assertThat(pastRooms).isEmpty();
  }

  @Test
  void listPastRoomsWithNoTodosReturnsZeroCompletionRate() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "투두 없는 종료된 방",
            "목표",
            null,
            LocalDate.now().minusDays(20),
            LocalDate.now().minusDays(10),
            null);
    RoomResponse created = roomService.createRoom("uid-past-empty-owner", "생성자", request);
    Room room = roomRepository.findById(created.id()).orElseThrow();
    room.end();
    roomRepository.save(room);

    List<PastRoomSummaryResponse> pastRooms = roomService.listPastRooms("uid-past-empty-owner");

    assertThat(pastRooms).hasSize(1);
    assertThat(pastRooms.get(0).completionRate()).isZero();
  }

  /**
   * 4-3: end_date 경과 시 ENDED 전환은 배치가 아니라 요청 시점 lazy 체크다(2026-07-30 확정, specs/OPEN.md). 위의 *Ended*
   * 테스트들과 달리 여기서는 {@code room.end()}를 수동으로 호출하지 않는다 — 생성 시점에 이미 지난 end_date를 줘서, 읽는 순간 자동으로 전환되는지를
   * 검증한다.
   */
  @Test
  void joinRoomWithPastEndDateIsAutoEndedOnReadAndBlocksJoin() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "자동 종료 방",
            "목표",
            null,
            LocalDate.now().minusDays(20),
            LocalDate.now().minusDays(1),
            null);
    RoomResponse created = roomService.createRoom("uid-autoend-creator", "생성자", request);
    assertThat(roomRepository.findById(created.id()).orElseThrow().getStatus())
        .isEqualTo(RoomStatus.ACTIVE);

    ApiException ex =
        catchThrowableOfType(
            () -> roomService.joinRoom("uid-autoend-joiner", "참여자", created.inviteCode()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.CONFLICT);
    assertThat(roomRepository.findById(created.id()).orElseThrow().getStatus())
        .isEqualTo(RoomStatus.ENDED);
  }

  /**
   * 자동 종료의 "오늘"은 <b>한국 시간</b>이어야 한다(2026-08-16).
   *
   * <p>🔴 <b>{@code LocalDate.now()} 를 쓰지 말 것</b> — 그건 JVM 기본 시간대이고, CI 러너도 운영 컨테이너도 <b>UTC</b> 다.
   * 픽스처를 {@code RoomService.KST} 로 만들어야 서비스와 같은 기준이 된다.
   *
   * <p>②가 이 회귀를 잡는 쪽이다: 무인자 {@code LocalDate.now()} 로 돌아가면 UTC JVM 의 KST 00:00~09:00 구간에서 "어제 끝난
   * 방"이 아직 ACTIVE 로 남아 실패한다. ①은 그 반대 경계(마지막 날은 아직 진행 중)를 고정한다.
   */
  @Test
  void autoEndBoundaryFollowsKoreanTimeNotJvmDefault() {
    LocalDate todayKst = LocalDate.now(RoomService.KST);

    // ① 마지막 날(end_date == 오늘)은 아직 진행 중이다.
    RoomResponse lastDay =
        roomService.createRoom(
            "uid-tz-lastday",
            "생성자",
            new CreateRoomRequest("오늘 끝나는 방", "목표", null, todayKst.minusDays(10), todayKst, null));

    assertThat(
            roomService
                .refreshStatus(roomRepository.findById(lastDay.id()).orElseThrow())
                .getStatus())
        .isEqualTo(RoomStatus.ACTIVE);

    // ② 어제 끝난 방은 읽는 순간 ENDED 로 넘어간다.
    RoomResponse yesterday =
        roomService.createRoom(
            "uid-tz-yesterday",
            "생성자",
            new CreateRoomRequest(
                "어제 끝난 방", "목표", null, todayKst.minusDays(10), todayKst.minusDays(1), null));

    assertThat(
            roomService
                .refreshStatus(roomRepository.findById(yesterday.id()).orElseThrow())
                .getStatus())
        .isEqualTo(RoomStatus.ENDED);
  }

  @Test
  void previewInviteWithPastEndDateReflectsAutoEndedStatus() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "자동 종료 미리보기 방",
            "목표",
            null,
            LocalDate.now().minusDays(20),
            LocalDate.now().minusDays(1),
            null);
    RoomResponse created = roomService.createRoom("uid-autoend-preview-creator", "생성자", request);

    InviteCodePreviewResponse preview = roomService.previewInvite(created.inviteCode());

    assertThat(preview.status()).isEqualTo(RoomStatus.ENDED);
  }

  @Test
  void listMyRoomsWithPastEndDateReflectsAutoEndedStatus() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "자동 종료 목록 방",
            "목표",
            null,
            LocalDate.now().minusDays(20),
            LocalDate.now().minusDays(1),
            null);
    RoomResponse created = roomService.createRoom("uid-autoend-list", "생성자", request);

    var summaries = roomService.listMyRooms("uid-autoend-list");

    assertThat(summaries).extracting(RoomSummaryResponse::id).contains(created.id());
    assertThat(
            summaries.stream()
                .filter(s -> s.id().equals(created.id()))
                .findFirst()
                .orElseThrow()
                .status())
        .isEqualTo(RoomStatus.ENDED);
  }

  @Test
  void listPastRoomsIncludesRoomAutoEndedOnRead() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "자동 종료 지난 방",
            "목표",
            null,
            LocalDate.now().minusDays(20),
            LocalDate.now().minusDays(1),
            null);
    RoomResponse created = roomService.createRoom("uid-autoend-pastlist", "생성자", request);

    List<PastRoomSummaryResponse> pastRooms = roomService.listPastRooms("uid-autoend-pastlist");

    assertThat(pastRooms).extracting(PastRoomSummaryResponse::id).containsExactly(created.id());
  }

  @Test
  void roomEndingTodayStaysActiveUntilDayAfter() {
    CreateRoomRequest request =
        new CreateRoomRequest(
            "오늘 종료 방", "목표", null, LocalDate.now().minusDays(10), LocalDate.now(), null);
    RoomResponse created = roomService.createRoom("uid-autoend-today", "생성자", request);

    var summaries = roomService.listMyRooms("uid-autoend-today");

    assertThat(
            summaries.stream()
                .filter(s -> s.id().equals(created.id()))
                .findFirst()
                .orElseThrow()
                .status())
        .isEqualTo(RoomStatus.ACTIVE);
  }
}
