package com.nomara.modi.server.domain.activity.service;

import com.nomara.modi.server.domain.activity.dto.ActivityResponse;
import com.nomara.modi.server.domain.activity.entity.Activity;
import com.nomara.modi.server.domain.activity.entity.ActivityType;
import com.nomara.modi.server.domain.activity.repository.ActivityRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.schedule.entity.Schedule;
import com.nomara.modi.server.domain.schedule.repository.ScheduleRepository;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import com.nomara.modi.server.domain.user.entity.User;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 홈 활동 피드(docs/backend/home-activity-feed.md) — 적재형 이벤트 기록 + 조회 시 파생형 이벤트를 합쳐 반환한다.
 *
 * <p><b>적재형(10종)</b>은 {@link #record}로 각 도메인 서비스(TodoService·ScheduleService·
 * ArchiveItemService·PokeService·RoomService)가 액션이 일어나는 순간 호출해 {@code activities} 테이블에 남긴다.
 *
 * <p><b>파생형(5종, {@code SCHEDULE_SOON}·{@code WEEKLY_SUMMARY}·{@code NUDGE_NONE_TODAY}·{@code
 * NUDGE_QUIET_MEMBER}·{@code NUDGE_UNASSIGNED})</b>은 저장하지 않고 {@link #getRecentActivities}가 조회 시점에
 * 계산해 합류시킨다 — "현재 상태"에 대한 질문이라 append할 단일 트리거가 없다(대시보드가 이미 프론트로 넘기는 {@code
 * MILESTONE_PROGRESS}/{@code DDAY}와 같은 성격).
 */
@Service
public class ActivityService {

  private static final Logger log = LoggerFactory.getLogger(ActivityService.class);

  /**
   * {@code ARCHIVE_LIKE_MILESTONE}·{@code POKE_ACCUMULATED} 둘 다 이 배수에 도달할 때만 기록한다 (5, 10, 15...).
   * 문서(docs/backend/home-activity-feed.md)에 구체적인 수치가 없어 저리스크 기본값으로 정했다 — 필요하면 나중에 조정.
   */
  static final int MILESTONE_STEP = 5;

  /**
   * {@code NUDGE_QUIET_MEMBER} 판정 기준(일). 로그인 로그가 없어 "활동 로그의 최신 시각·담당 투두 최근 완료 시각 중 더 늦은 쪽"으로 근사한다 —
   * 완전한 판정이 아니다(specs/OPEN.md에 기록).
   */
  private static final int QUIET_THRESHOLD_DAYS = 3;

  private static final int DEFAULT_LIMIT = 20;

  private static final ZoneId KST = ZoneId.of("Asia/Seoul");

  private final ActivityRepository activityRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final TodoRepository todoRepository;
  private final TodoAssigneeRepository todoAssigneeRepository;
  private final ScheduleRepository scheduleRepository;

  public ActivityService(
      ActivityRepository activityRepository,
      RoomMemberRepository roomMemberRepository,
      TodoRepository todoRepository,
      TodoAssigneeRepository todoAssigneeRepository,
      ScheduleRepository scheduleRepository) {
    this.activityRepository = activityRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.todoRepository = todoRepository;
    this.todoAssigneeRepository = todoAssigneeRepository;
    this.scheduleRepository = scheduleRepository;
  }

  /**
   * 적재형 이벤트를 한 건 남긴다. <b>실패해도 예외를 던지지 않는다</b> — 활동 기록은 부수 효과라, 여기서 문제가 생겨 투두 완료·자료 등록 같은 핵심 동작까지
   * 롤백되면 안 된다(AI 태깅 실패 폴백과 같은 방향, specs/OPEN.md 2026-07-27 확정 사례 참고).
   */
  @Transactional
  public void record(
      Room room, ActivityType type, User actor, User target, String targetName, Integer count) {
    try {
      activityRepository.save(new Activity(room, type, actor, target, targetName, count));
    } catch (Exception e) {
      log.warn("활동 기록 실패(무시하고 계속): room={} type={}", room.getId(), type, e);
    }
  }

  /** {@code count}가 {@link #MILESTONE_STEP}의 배수(0 제외)면 마일스톤이다. */
  public boolean isMilestone(long count) {
    return count > 0 && count % MILESTONE_STEP == 0;
  }

  @Transactional(readOnly = true)
  public List<ActivityResponse> getRecentActivities(Room room) {
    return getRecentActivities(room, DEFAULT_LIMIT);
  }

  @Transactional(readOnly = true)
  public List<ActivityResponse> getRecentActivities(Room room, int limit) {
    List<Activity> persisted =
        activityRepository.findRecentByRoomIdWithPokesDeduped(
            room.getId(), PageRequest.of(0, limit));

    List<ActivityResponse> merged = new ArrayList<>(groupAndMap(persisted));
    merged.addAll(deriveScheduleSoon(room));
    merged.addAll(deriveWeeklySummary(room));
    merged.addAll(deriveNudgeNoneToday(room));
    merged.addAll(deriveNudgeUnassigned(room));
    deriveNudgeQuietMember(room).ifPresent(merged::add);

    merged.sort(Comparator.comparing(ActivityResponse::createdAt).reversed());
    return merged.size() > limit ? merged.subList(0, limit) : merged;
  }

  /**
   * 너무 잦은 이벤트는 묶어서 보여준다(문서 4절) — 같은 날 같은 사람의 {@code TODO_COMPLETED}는 "3개 완료"처럼 한 줄로 합친다. 그 외 타입은 한
   * 행이 곧 한 번의 실제 액션이라 묶지 않는다.
   */
  private List<ActivityResponse> groupAndMap(List<Activity> rows) {
    List<ActivityResponse> result = new ArrayList<>();
    Map<String, ActivityResponse> completedByActorDay = new LinkedHashMap<>();
    for (Activity a : rows) {
      if (a.getType() == ActivityType.TODO_COMPLETED && a.getActorUser() != null) {
        String key = a.getActorUser().getId() + ":" + LocalDate.ofInstant(a.getCreatedAt(), KST);
        completedByActorDay.merge(key, toResponse(a), this::mergeCompleted);
      } else {
        result.add(toResponse(a));
      }
    }
    result.addAll(completedByActorDay.values());
    return result;
  }

  private ActivityResponse mergeCompleted(ActivityResponse existing, ActivityResponse incoming) {
    int mergedCount =
        (existing.count() == null ? 0 : existing.count())
            + (incoming.count() == null ? 0 : incoming.count());
    Instant latest =
        existing.createdAt().isAfter(incoming.createdAt())
            ? existing.createdAt()
            : incoming.createdAt();
    return new ActivityResponse(
        existing.type(),
        existing.actorNickname(),
        existing.actorUserId(),
        mergedCount,
        existing.targetName(),
        existing.secondaryCount(),
        latest);
  }

  private ActivityResponse toResponse(Activity a) {
    String targetName =
        a.getTargetUser() != null ? a.getTargetUser().getNickname() : a.getTargetName();
    return new ActivityResponse(
        a.getType().name(),
        a.getActorUser() != null ? a.getActorUser().getNickname() : null,
        a.getActorUser() != null ? a.getActorUser().getId() : null,
        a.getCount(),
        targetName,
        null,
        a.getCreatedAt());
  }

  /** 오늘·내일 일정이 있으면 1건. 방 전체 대상이라 actor 없음. */
  private List<ActivityResponse> deriveScheduleSoon(Room room) {
    LocalDate today = LocalDate.now(KST);
    List<Schedule> soon =
        scheduleRepository.findOverlappingByRoomId(room.getId(), today, today.plusDays(1));
    if (soon.isEmpty()) {
      return List.of();
    }
    return List.of(
        new ActivityResponse(
            ActivityType.SCHEDULE_SOON.name(), null, null, null, null, null, Instant.now()));
  }

  /** 이번 주(월~일) 완료 수와 저번 주 대비 증감. 방 전체 집계라 actor 없음. */
  private List<ActivityResponse> deriveWeeklySummary(Room room) {
    LocalDate thisWeekStart = LocalDate.now(KST).with(DayOfWeek.MONDAY);
    LocalDate lastWeekStart = thisWeekStart.minusWeeks(1);
    long thisWeekCount = countCompletedBetween(room, thisWeekStart, thisWeekStart.plusDays(7));
    long lastWeekCount = countCompletedBetween(room, lastWeekStart, thisWeekStart);
    if (thisWeekCount == 0 && lastWeekCount == 0) {
      return List.of();
    }
    return List.of(
        new ActivityResponse(
            ActivityType.WEEKLY_SUMMARY.name(),
            null,
            null,
            (int) thisWeekCount,
            null,
            (int) (thisWeekCount - lastWeekCount),
            Instant.now()));
  }

  /** 오늘(KST) 방 전체 완료가 0건이면 1건. */
  private List<ActivityResponse> deriveNudgeNoneToday(Room room) {
    LocalDate today = LocalDate.now(KST);
    long todayCount = countCompletedBetween(room, today, today.plusDays(1));
    if (todayCount > 0) {
      return List.of();
    }
    return List.of(
        new ActivityResponse(
            ActivityType.NUDGE_NONE_TODAY.name(), null, null, null, null, null, Instant.now()));
  }

  /** 방에 담당자 없는(미지정) 미완료 투두가 있으면 그 개수를 1건으로(docs/backend/live-banner-copy-handoff.md §4). */
  private List<ActivityResponse> deriveNudgeUnassigned(Room room) {
    long unassignedCount = todoRepository.countUnassignedIncompleteByRoomId(room.getId());
    if (unassignedCount == 0) {
      return List.of();
    }
    return List.of(
        new ActivityResponse(
            ActivityType.NUDGE_UNASSIGNED.name(),
            null,
            null,
            (int) unassignedCount,
            null,
            null,
            Instant.now()));
  }

  private long countCompletedBetween(Room room, LocalDate startInclusive, LocalDate endExclusive) {
    Instant start = startInclusive.atStartOfDay(KST).toInstant();
    Instant end = endExclusive.atStartOfDay(KST).toInstant();
    return todoRepository.countByRoomIdAndCompletedAtBetween(room.getId(), start, end);
  }

  /**
   * 방 멤버 중 가장 조용한(활동 로그 최신 시각도, 담당 투두 최근 완료 시각도 없거나 오래된) 사람이 {@link #QUIET_THRESHOLD_DAYS}일 이상이면 그
   * 한 명만 노출한다. 여럿을 한꺼번에 찌르면 소음이 된다(문서 4절 "개인정보/노이즈").
   */
  private Optional<ActivityResponse> deriveNudgeQuietMember(Room room) {
    List<RoomMember> members = roomMemberRepository.findMembersByRoomId(room.getId());
    Instant threshold = Instant.now().minus(Duration.ofDays(QUIET_THRESHOLD_DAYS));

    RoomMember quietest = null;
    Instant quietestLastSeen = null;
    for (RoomMember member : members) {
      Instant lastSeen = lastSeenAt(room, member);
      if (!lastSeen.isBefore(threshold)) {
        continue;
      }
      if (quietestLastSeen == null || lastSeen.isBefore(quietestLastSeen)) {
        quietest = member;
        quietestLastSeen = lastSeen;
      }
    }
    if (quietest == null) {
      return Optional.empty();
    }
    long quietDays = Duration.between(quietestLastSeen, Instant.now()).toDays();
    return Optional.of(
        new ActivityResponse(
            ActivityType.NUDGE_QUIET_MEMBER.name(),
            quietest.getUser().getNickname(),
            quietest.getUser().getId(),
            (int) quietDays,
            null,
            null,
            Instant.now()));
  }

  private Instant lastSeenAt(Room room, RoomMember member) {
    String userId = member.getUser().getId();
    Instant lastActivity =
        activityRepository.findMaxCreatedAtByRoomIdAndActorUserId(room.getId(), userId);
    Instant lastCompletion =
        todoAssigneeRepository.findMaxCompletedAtByRoomIdAndUserId(room.getId(), userId);
    Instant lastSeen = member.getJoinedAt();
    if (lastActivity != null && lastActivity.isAfter(lastSeen)) {
      lastSeen = lastActivity;
    }
    if (lastCompletion != null && lastCompletion.isAfter(lastSeen)) {
      lastSeen = lastCompletion;
    }
    return lastSeen;
  }
}
