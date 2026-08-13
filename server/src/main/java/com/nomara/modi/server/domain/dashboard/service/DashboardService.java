package com.nomara.modi.server.domain.dashboard.service;

import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveLikeRepository;
import com.nomara.modi.server.domain.character.entity.UserActivityKind;
import com.nomara.modi.server.domain.character.service.UserActivityRecorder;
import com.nomara.modi.server.domain.dashboard.dto.ArchiveBrief;
import com.nomara.modi.server.domain.dashboard.dto.DashboardResponse;
import com.nomara.modi.server.domain.dashboard.dto.RoomInfo;
import com.nomara.modi.server.domain.dashboard.dto.ScheduleBrief;
import com.nomara.modi.server.domain.dashboard.dto.TodoBrief;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.exception.RoomNotFoundException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.room.service.RoomService;
import com.nomara.modi.server.domain.schedule.repository.ScheduleRepository;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** specs/0005-홈-대시보드.md 집계 서비스. 홈은 읽기 위주 — 쓰기는 todo 완료 토글(별도 TodoService)만. */
@Service
public class DashboardService {

  private static final int TODAY_TODO_LIMIT = 5;
  private static final int RECENT_ARCHIVE_LIMIT = 4;

  private final RoomRepository roomRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final TodoAssigneeRepository todoAssigneeRepository;
  private final TodoRepository todoRepository;
  private final ScheduleRepository scheduleRepository;
  private final ArchiveItemRepository archiveItemRepository;
  private final ArchiveLikeRepository archiveLikeRepository;
  private final RoomService roomService;
  private final ActivityService activityService;
  private final UserActivityRecorder userActivityRecorder;

  public DashboardService(
      RoomRepository roomRepository,
      RoomMemberRepository roomMemberRepository,
      TodoAssigneeRepository todoAssigneeRepository,
      TodoRepository todoRepository,
      ScheduleRepository scheduleRepository,
      ArchiveItemRepository archiveItemRepository,
      ArchiveLikeRepository archiveLikeRepository,
      RoomService roomService,
      ActivityService activityService,
      UserActivityRecorder userActivityRecorder) {
    this.roomRepository = roomRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.todoAssigneeRepository = todoAssigneeRepository;
    this.todoRepository = todoRepository;
    this.scheduleRepository = scheduleRepository;
    this.archiveItemRepository = archiveItemRepository;
    this.archiveLikeRepository = archiveLikeRepository;
    this.roomService = roomService;
    this.activityService = activityService;
    this.userActivityRecorder = userActivityRecorder;
  }

  @Transactional
  public DashboardResponse getDashboard(
      String uid, Long roomId, LocalDate weekStart, LocalDate weekEnd) {
    // 멤버십을 방 존재 여부보다 먼저 확인 — 비멤버에게 "존재하지 않는 방"과 "남의 방"을 구분해 알려주지 않는다.
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, uid))) {
      throw new NotRoomMemberException();
    }
    Room room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
    // 4-3: end_date 경과 시 ENDED로 lazy 전환(RoomService.refreshStatus, specs/OPEN.md 2026-07-30 확정).
    room = roomService.refreshStatus(room);
    // 협업 캐릭터 활동성 신호(specs/0016) — 방 진입 조회 로그.
    userActivityRecorder.record(uid, UserActivityKind.ROOM_VIEW, room, null);

    return new DashboardResponse(
        RoomInfo.of(room),
        // 계산 로직은 RoomService.listMemberProgress로 통합됨 — 여기서는 이미 멤버십을
        // 확인했으므로 그 메서드 내부의 재검증은 저비용 중복 쿼리 한 번뿐이다.
        roomService.listMemberProgress(uid, roomId),
        buildWeekSchedules(roomId, weekStart, weekEnd),
        buildTodayTodos(roomId, uid),
        buildRecentArchives(roomId),
        buildPreviewArchives(roomId),
        buildPinnedArchives(roomId),
        // 히어로 진행률 바: 방 단위로 직접 집계 — 멤버별 assignedTotal 합산은 다중 담당자
        // 투두가 중복 집계된다(specs/0005 [백엔드 요구 ②]).
        todoRepository.countByRoomIdAndCompletedTrue(roomId),
        todoRepository.countByRoomId(roomId),
        activityService.getRecentActivities(room));
  }

  private List<ScheduleBrief> buildWeekSchedules(
      Long roomId, LocalDate weekStart, LocalDate weekEnd) {
    return scheduleRepository.findOverlappingByRoomId(roomId, weekStart, weekEnd).stream()
        .map(ScheduleBrief::of)
        .toList();
  }

  private List<TodoBrief> buildTodayTodos(Long roomId, String uid) {
    // specs/0005-홈-대시보드.md 2026-07-27 패치: 방 전체 보충 로직 폐기 — 내 담당 미완료만 노출.
    return todoAssigneeRepository
        .findMyIncompleteTodos(roomId, uid, PageRequest.of(0, TODAY_TODO_LIMIT))
        .stream()
        .map(todo -> new TodoBrief(todo.getId(), todo.getTitle(), todo.isCompleted()))
        .toList();
  }

  /**
   * 홈 아카이브 미리보기.
   *
   * <p><b>분석 실패(FAILED) 자료는 뺀다</b>(2026-08-05 사용자 요청) — 크롤링이 실패하면 제목만 남아 미리보기에서 빈 카드처럼 보인다. {@code
   * PENDING}은 빼지 않는다(곧 본문이 붙는 정상 자료다). 응답 스키마는 그대로라 앱·OpenAPI 변경은 없다.
   */
  private List<ArchiveBrief> buildRecentArchives(Long roomId) {
    List<ArchiveItem> items =
        archiveItemRepository.findByRoomIdAndCrawlStatusNotOrderByCreatedAtDesc(
            roomId, ArchiveItem.CrawlStatus.FAILED, PageRequest.of(0, RECENT_ARCHIVE_LIMIT));
    return toArchiveBriefs(items);
  }

  /**
   * 아카이브 미리보기(specs/0005-홈-대시보드.md 2026-08-06) — 핀 우선→최신순 최대 4개. 핀 자료로 앞을 채우고 부족분은 최신 비핀으로 자동
   * 보충된다({@code pinned desc, createdAt desc} 정렬 + LIMIT 한 번으로 충분).
   */
  private List<ArchiveBrief> buildPreviewArchives(Long roomId) {
    List<ArchiveItem> items =
        archiveItemRepository.findByRoomIdAndCrawlStatusNotOrderByPinnedDescCreatedAtDesc(
            roomId, ArchiveItem.CrawlStatus.FAILED, PageRequest.of(0, RECENT_ARCHIVE_LIMIT));
    return toArchiveBriefs(items);
  }

  /**
   * 핀 고정 자료만(백엔드 요청, 2026-08-07) — 순수 필터, 최대 4개, 핀이 없으면 빈 배열. {@code buildPreviewArchives}와 달리 비핀
   * 자료로 채우지 않는다.
   */
  private List<ArchiveBrief> buildPinnedArchives(Long roomId) {
    List<ArchiveItem> items =
        archiveItemRepository.findByRoomIdAndCrawlStatusNotAndPinnedTrueOrderByCreatedAtDesc(
            roomId, ArchiveItem.CrawlStatus.FAILED, PageRequest.of(0, RECENT_ARCHIVE_LIMIT));
    return toArchiveBriefs(items);
  }

  private List<ArchiveBrief> toArchiveBriefs(List<ArchiveItem> items) {
    List<ArchiveBrief> result = new ArrayList<>(items.size());
    for (ArchiveItem item : items) {
      result.add(ArchiveBrief.of(item, archiveLikeRepository.countByItemId(item.getId())));
    }
    return result;
  }
}
