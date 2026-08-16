package com.nomara.modi.server.domain.room.service;

import com.nomara.modi.server.domain.activity.entity.ActivityType;
import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
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
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.entity.RoomStatus;
import com.nomara.modi.server.domain.room.exception.InviteCodeNotFoundException;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.exception.RoomEndedException;
import com.nomara.modi.server.domain.room.exception.RoomNotFoundException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.BadRequestException;
import com.nomara.modi.server.global.notification.PushNotifier;
import com.nomara.modi.server.global.notification.PushType;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RoomService {

  /**
   * 방의 "오늘"은 <b>한국 시간</b> 기준이다.
   *
   * <p>🔴 <b>{@code private} 이 아닌 이유: 테스트가 같은 기준을 써야 하기 때문</b> — {@code
   * ScheduleReminderService.KST} 와 같은 이유다(그쪽 주석 참고). 값을 복사해 쓰면 어긋남이 다시 난다.
   *
   * <p>2026-08-16 추가. 그전에는 무인자 {@code LocalDate.now()} 였고, 운영 컨테이너에 {@code TZ} 가 없어 JVM 이
   * <b>UTC</b> 로 돌았다 — KST 00:00~09:00 구간에서 서버의 "오늘"이 사용자보다 하루 뒤처져 방 자동 종료가 최대 9시간 늦었다. 컨테이너에도
   * {@code TZ=Asia/Seoul} 을 넣었지만(deploy/docker-compose.app.yml) <b>환경변수에 기대지 않도록</b> 코드에서도 명시한다.
   */
  static final ZoneId KST = ZoneId.of("Asia/Seoul");

  private final RoomRepository roomRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final UserRepository userRepository;
  private final InviteCodeService inviteCodeService;
  private final TodoAssigneeRepository todoAssigneeRepository;
  private final TodoRepository todoRepository;
  private final PushNotifier pushNotifier;
  private final ActivityService activityService;
  private final ArchiveFolderRepository archiveFolderRepository;

  public RoomService(
      RoomRepository roomRepository,
      RoomMemberRepository roomMemberRepository,
      UserRepository userRepository,
      InviteCodeService inviteCodeService,
      TodoAssigneeRepository todoAssigneeRepository,
      TodoRepository todoRepository,
      PushNotifier pushNotifier,
      ActivityService activityService,
      ArchiveFolderRepository archiveFolderRepository) {
    this.roomRepository = roomRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.userRepository = userRepository;
    this.inviteCodeService = inviteCodeService;
    this.todoAssigneeRepository = todoAssigneeRepository;
    this.todoRepository = todoRepository;
    this.pushNotifier = pushNotifier;
    this.activityService = activityService;
    this.archiveFolderRepository = archiveFolderRepository;
  }

  @Transactional
  public RoomResponse createRoom(String uid, String displayName, CreateRoomRequest request) {
    if (request.startDate().isAfter(request.endDate())) {
      throw new BadRequestException("시작일은 종료일보다 늦을 수 없어요");
    }

    User creator = ensureUser(uid, displayName);
    Room room =
        roomRepository.save(
            new Room(
                request.name(),
                request.coverImage(),
                request.goal(),
                request.goalDetail(),
                request.startDate(),
                request.endDate()));
    roomMemberRepository.save(new RoomMember(room, creator));
    // 방마다 폴더 최소 1개 보장(백엔드 요청, 2026-08-07) — 생성 즉시 "기본" 폴더를 만든다.
    archiveFolderRepository.save(new ArchiveFolder(room, ArchiveFolder.DEFAULT_FOLDER_NAME));
    String inviteCode = inviteCodeService.generate(room.getId());
    activityService.record(room, ActivityType.MEMBER_JOINED, creator, null, null, null);

    return RoomResponse.of(room, inviteCode);
  }

  @Transactional
  public InviteCodePreviewResponse previewInvite(String code) {
    Room room = resolveRoom(code);
    int memberCount = (int) roomMemberRepository.countByRoomId(room.getId());
    return new InviteCodePreviewResponse(
        room.getId(),
        room.getName(),
        room.getGoal(),
        room.getStatus(),
        memberCount,
        room.getStartDate(),
        room.getEndDate());
  }

  /**
   * S-11 초대코드로 방 참여.
   *
   * <p><b>{@code noRollbackFor}가 필요한 이유</b>(2026-07-30, 4-3 테스트 실패로 발견): {@link #resolveRoom}이
   * {@link #refreshStatus}를 통해 기간이 지난 방을 {@code ENDED}로 전환하고 저장한다. 그런데 바로 아래에서 {@link
   * RoomEndedException}(런타임 예외)을 던지면 <b>그 전환까지 함께 롤백된다</b> — 방을 종료시킨 계기가 참여 시도인데 하필 그 요청에서만 기록이 안
   * 남는다. 다음 요청이 다시 전환을 시도하므로 사용자에게 보이는 증상은 없지만, "요청 시점 lazy 체크"(specs/OPEN.md 4-3 확정)가 그 경로에서 무효가
   * 된다.
   *
   * <p>이 예외 시점까지 쓰기는 <b>자동 종료 전환뿐</b>이다({@code ensureUser}·멤버 저장은 그 뒤에 있다). 그래서 커밋해도 남는 것이 정확히 의도한
   * 상태 하나다. 반대로 예외를 던지지 않는 {@link #previewInvite}는 원래부터 정상 커밋된다.
   */
  @Transactional(noRollbackFor = RoomEndedException.class)
  public RoomResponse joinRoom(String uid, String displayName, String code) {
    Room room = resolveRoom(code);
    if (room.getStatus() == RoomStatus.ENDED) {
      throw new RoomEndedException();
    }

    User joiner = ensureUser(uid, displayName);
    RoomMemberId memberId = new RoomMemberId(room.getId(), joiner.getId());
    if (!roomMemberRepository.existsById(memberId)) {
      // 알림 대상은 "참여 전" 멤버 스냅샷이라 참여자 본인은 자연히 빠진다. 이미 멤버인 재참여(no-op)는
      // 이 분기에 들어오지 않으므로 알림도 없다(full_spec.md:205, specs/0015-알림-트리거.md).
      List<RoomMember> existingMembers = roomMemberRepository.findMembersByRoomId(room.getId());
      roomMemberRepository.save(new RoomMember(room, joiner));
      notifyMembers(
          existingMembers,
          PushType.ROOM_MEMBER_JOINED,
          room,
          "새 팀원이 왔어요 🎉",
          joiner.getNickname() + "님이 합류했어요 · " + room.getName());
      activityService.record(room, ActivityType.MEMBER_JOINED, joiner, null, null, null);
    }

    return RoomResponse.of(room, null);
  }

  @Transactional
  public List<RoomSummaryResponse> listMyRooms(String uid) {
    return roomMemberRepository.findRoomsByUserId(uid).stream()
        .map(this::refreshStatus)
        .map(RoomSummaryResponse::of)
        .toList();
  }

  /** S-40-D — 종료된 방 중 내가 속했던 방만(listMyRooms와 동일한 보안 모델). */
  @Transactional
  public List<PastRoomSummaryResponse> listPastRooms(String uid) {
    return roomMemberRepository.findRoomsByUserId(uid).stream()
        .map(this::refreshStatus)
        .filter(room -> room.getStatus() == RoomStatus.ENDED)
        .map(this::toPastRoomSummary)
        .toList();
  }

  /**
   * 4-3: {@code end_date} 경과 시 {@code ENDED}로 lazy 전환(요청 시점 체크, 배치 없음 — 2026-07-30 확정,
   * specs/OPEN.md). 방을 읽는 모든 진입점(초대 미리보기·참여·목록·지난 방·홈 대시보드)이 이 메서드를 거친다. 이미 {@code ENDED}거나 아직
   * {@code endDate}가 지나지 않았으면 아무 것도 하지 않는다.
   */
  public Room refreshStatus(Room room) {
    if (room.getStatus() == RoomStatus.ACTIVE && LocalDate.now(KST).isAfter(room.getEndDate())) {
      room.end();
      roomRepository.save(room);
    }
    return room;
  }

  private PastRoomSummaryResponse toPastRoomSummary(Room room) {
    long total = todoRepository.countByRoomId(room.getId());
    long done = todoRepository.countByRoomIdAndCompletedTrue(room.getId());
    double completionRate = total == 0 ? 0.0 : (double) done / total;
    return new PastRoomSummaryResponse(
        room.getId(), room.getName(), room.getStartDate(), room.getEndDate(), completionRate);
  }

  /** S-40-B — 현재 초대코드를 조회한다. 만료된 경우에만 새 코드를 발급한다. */
  @Transactional
  public InviteCodeResponse getInviteCode(String uid, Long roomId) {
    requireMembership(uid, roomId);
    roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
    return new InviteCodeResponse(inviteCodeService.getOrCreate(roomId));
  }

  /** S-40-B — 이전 코드는 즉시 무효화되고 새 코드가 발급된다(specs/0002-data-model.md). */
  @Transactional(readOnly = true)
  public InviteCodeResponse reissueInviteCode(String uid, Long roomId) {
    requireMembership(uid, roomId);
    roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
    return new InviteCodeResponse(inviteCodeService.reissue(roomId));
  }

  /**
   * S-40-C — 마지막 멤버가 나가면 방을 즉시 하드 삭제한다(유예 기간·배치 없음, specs/OPEN.md 2026-07-30 확정). 하위 데이터는 DB 레벨
   * CASCADE로 함께 정리된다.
   */
  @Transactional
  public void leaveRoom(String uid, Long roomId) {
    requireMembership(uid, roomId);
    User leaver = userRepository.findById(uid).orElseThrow();
    Room room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
    roomMemberRepository.deleteById(new RoomMemberId(roomId, uid));
    if (roomMemberRepository.countByRoomId(roomId) == 0) {
      roomRepository.deleteById(roomId);
      return;
    }
    // 남은 멤버에게만 알림 — 마지막 멤버가 나가 방이 삭제되는 경우는 남은 멤버가 없어 자연히 스킵된다.
    notifyMembers(
        roomMemberRepository.findMembersByRoomId(roomId),
        PushType.ROOM_MEMBER_LEFT,
        room,
        leaver.getNickname() + "님이 방을 나갔어요",
        room.getName());
  }

  public List<MemberBriefResponse> listMembers(String uid, Long roomId) {
    requireMembership(uid, roomId);
    return roomMemberRepository.findMembersByRoomId(roomId).stream()
        .map(MemberBriefResponse::of)
        .toList();
  }

  /** S-40-A: 방 정보 수정 — S-10과 동일 필드를 통째로 받는 풀 업데이트. */
  @Transactional
  public RoomResponse updateRoom(String uid, Long roomId, UpdateRoomRequest request) {
    requireMembership(uid, roomId);
    if (request.startDate().isAfter(request.endDate())) {
      throw new BadRequestException("시작일은 종료일보다 늦을 수 없어요");
    }

    Room room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
    room.update(
        request.name(),
        request.coverImage(),
        request.goal(),
        request.goalDetail(),
        request.startDate(),
        request.endDate());
    if (room.getStatus() == RoomStatus.ENDED) {
      room.restart(request.startDate(), request.endDate());
    }
    return RoomResponse.of(room, null);
  }

  /**
   * full_spec.md §3(멤버 아바타줄 진행률 링)·specs/0002-data-model.md("개인 진행률") — 진행률 내림차순, 동률은 가입순 유지(stable
   * sort). {@code DashboardService.getDashboard}도 홈 응답 조립에 이 메서드를 그대로 재사용한다.
   */
  @Transactional(readOnly = true)
  public List<MemberProgress> listMemberProgress(String uid, Long roomId) {
    requireMembership(uid, roomId);

    Map<String, long[]> progressByUserId = new HashMap<>();
    for (Object[] row : todoAssigneeRepository.aggregateProgressByRoomId(roomId)) {
      String userId = (String) row[0];
      long total = ((Number) row[1]).longValue();
      long done = ((Number) row[2]).longValue();
      progressByUserId.put(userId, new long[] {total, done});
    }

    List<RoomMember> members = roomMemberRepository.findMembersByRoomId(roomId);
    List<MemberProgress> result = new ArrayList<>(members.size());
    for (RoomMember member : members) {
      long[] counts = progressByUserId.getOrDefault(member.getUser().getId(), new long[] {0, 0});
      result.add(
          new MemberProgress(
              member.getUser().getId(),
              member.getUser().getNickname(),
              member.getUser().getProfileImage(),
              counts[0],
              counts[1]));
    }
    result.sort(Comparator.comparingDouble(MemberProgress::completionRate).reversed());
    return result;
  }

  private Room resolveRoom(String code) {
    Long roomId =
        inviteCodeService.resolveRoomId(code).orElseThrow(InviteCodeNotFoundException::new);
    Room room = roomRepository.findById(roomId).orElseThrow(InviteCodeNotFoundException::new);
    return refreshStatus(room);
  }

  private void requireMembership(String uid, Long roomId) {
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, uid))) {
      throw new NotRoomMemberException();
    }
  }

  private void notifyMembers(
      List<RoomMember> members, PushType type, Room room, String title, String body) {
    pushNotifier.notifyEach(
        members.stream().map(RoomMember::getUser).toList(), type, room, title, body);
  }

  private User ensureUser(String uid, String displayName) {
    return userRepository
        .findById(uid)
        .orElseGet(
            () ->
                userRepository.save(new User(uid, displayName != null ? displayName : uid, null)));
  }
}
