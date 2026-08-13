package com.nomara.modi.server.domain.character.service;

import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveLikeRepository;
import com.nomara.modi.server.domain.character.dto.ActivityStatsResponse;
import com.nomara.modi.server.domain.character.dto.CharacterResponse;
import com.nomara.modi.server.domain.character.dto.CharacterResponse.Confidence;
import com.nomara.modi.server.domain.character.entity.CharacterId;
import com.nomara.modi.server.domain.character.repository.UserActivityRepository;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 협업 캐릭터 판정(specs/0016-협업-캐릭터.md 3장) — 프로젝트를 넘나드는 <b>전역(방 무관)</b> 신호로 계산한다. 결과는 저장하지 않고 매 요청마다 즉석에서
 * 산출한다("이번 시즌", 가변).
 *
 * <p>문서가 임계값·정규화 방식을 구체적으로 안 정한 지점은 이 프로젝트의 기존 관행(예: {@code ActivityService}의 {@code
 * MILESTONE_STEP=5})을 따라 <b>저리스크 기본값</b>을 이름 붙은 상수로 정했다 — 근거는 {@code specs/OPEN.md}.
 */
@Service
public class CharacterService {

  private static final ZoneId KST = ZoneId.of("Asia/Seoul");

  /** 3-5: 데이터 희박 가드 — 억지 배정 방지. */
  private static final long MIN_COMPLETED_FOR_CHARACTER = 5;

  /** confidence LOW/HIGH 경계(저리스크 기본값, 문서에 수치 없음). */
  private static final long MIN_COMPLETED_FOR_HIGH_CONFIDENCE = 10;

  // 3-2: 신호 세기 가중치.
  private static final double DUE_DATE_WEIGHT = 1.0;
  private static final double LEAD_TIME_WEIGHT = 0.5;

  /** 마감 대비 며칠 차이를 "완전히 미룸/미리"(±1.0)로 볼지의 스케일(저리스크 기본값). */
  private static final double DUE_DATE_SCALE_DAYS = 3.0;

  // 3-4 결정 트리 경계값(저리스크 기본값).
  private static final double TIMING_LATE_THRESHOLD = 0.3;
  private static final double TIMING_EARLY_THRESHOLD = -0.3;
  private static final double COMPLETION_RATE_HIGH = 0.7;
  private static final double COMPLETION_RATE_THE_J = 0.85;
  private static final double DEADLINE_KEPT_THE_J = 0.85;
  private static final int STEADY_STREAK_DAYS = 7;

  // GHOST/LURKER 판정(3-3 활동성, 저리스크 기본값).
  private static final int RECENT_WINDOW_DAYS = 30;
  private static final int GHOST_GAP_DAYS = 7;
  private static final long LURKER_MIN_RECENT_VIEWS = 10;
  private static final long LURKER_MAX_RECENT_COMPLETIONS = 1;

  /** CHEERLEADER(보조) — 문서는 "최상위"(percentile)를 암시하지만 전체 사용자 순위 쿼리 비용을 피해 고정 임계값으로 근사. */
  private static final long CHEERLEADER_LIKES_GIVEN_THRESHOLD = 20;

  private static final Map<CharacterId, CharacterId> EVOLUTION = new EnumMap<>(CharacterId.class);

  static {
    EVOLUTION.put(CharacterId.PROCRASTINATOR, CharacterId.SPRINTER);
    EVOLUTION.put(CharacterId.GHOST, CharacterId.STEADY);
    EVOLUTION.put(CharacterId.LURKER, CharacterId.STEADY);
    EVOLUTION.put(CharacterId.TURTLE, CharacterId.STEADY);
    EVOLUTION.put(CharacterId.SPRINTER, CharacterId.EARLYBIRD);
    EVOLUTION.put(CharacterId.STEADY, CharacterId.EARLYBIRD);
    EVOLUTION.put(CharacterId.EARLYBIRD, CharacterId.THE_J);
    // THE_J/CHEERLEADER/WARMING_UP은 더 이상 진화 경로가 없다(문서 2장에 화살표 없음).
  }

  private final TodoAssigneeRepository todoAssigneeRepository;
  private final ArchiveLikeRepository archiveLikeRepository;
  private final ArchiveItemRepository archiveItemRepository;
  private final UserActivityRepository userActivityRepository;
  private final RoomMemberRepository roomMemberRepository;

  public CharacterService(
      TodoAssigneeRepository todoAssigneeRepository,
      ArchiveLikeRepository archiveLikeRepository,
      ArchiveItemRepository archiveItemRepository,
      UserActivityRepository userActivityRepository,
      RoomMemberRepository roomMemberRepository) {
    this.todoAssigneeRepository = todoAssigneeRepository;
    this.archiveLikeRepository = archiveLikeRepository;
    this.archiveItemRepository = archiveItemRepository;
    this.userActivityRepository = userActivityRepository;
    this.roomMemberRepository = roomMemberRepository;
  }

  /**
   * 방 멤버 화면에서 다른 멤버의 캐릭터를 본다(문서 4.3, 선택) — 같은 방 멤버일 때만 허용하고, 캐릭터 자체는 {@link #getCharacter}와 같은 전역
   * 판정을 그대로 재사용한다(방마다 다시 계산하지 않음 — 캐릭터는 "프로젝트를 넘나드는" 개념이라서다).
   */
  @Transactional(readOnly = true)
  public CharacterResponse getCharacterForRoomMember(
      String callerUid, Long roomId, String targetUserId) {
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, callerUid))) {
      throw new NotRoomMemberException();
    }
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, targetUserId))) {
      throw new NotRoomMemberException();
    }
    return getCharacter(targetUserId);
  }

  @Transactional(readOnly = true)
  public CharacterResponse getCharacter(String userId) {
    List<Todo> completedTodos = todoAssigneeRepository.findCompletedTodosByUserId(userId);
    long likesGiven = archiveLikeRepository.countByUserId(userId);
    long shared = archiveItemRepository.countByCreatedById(userId);

    if (completedTodos.size() < MIN_COMPLETED_FOR_CHARACTER) {
      return buildResponse(
          CharacterId.WARMING_UP,
          "투두를 " + MIN_COMPLETED_FOR_CHARACTER + "개 넘게 완료하면 캐릭터가 드러나요.",
          Confidence.LOW,
          new ActivityStatsResponse(completedTodos.size(), 0, 0.0, likesGiven, shared, 0));
    }

    List<Object[]> progress = todoAssigneeRepository.aggregateProgressByUserId(userId);
    long totalAssigned = progress.isEmpty() ? completedTodos.size() : (Long) progress.get(0)[0];
    double completionRate =
        totalAssigned == 0 ? 1.0 : (double) completedTodos.size() / totalAssigned;

    Timing timing = computeTiming(completedTodos);
    int streak = computeCurrentStreak(completedTodos);

    Instant windowStart = Instant.now().minus(RECENT_WINDOW_DAYS, ChronoUnit.DAYS);
    long recentCompleted =
        completedTodos.stream().filter(t -> t.getCompletedAt().isAfter(windowStart)).count();
    long recentViews = userActivityRepository.countByUserIdAndCreatedAtAfter(userId, windowStart);

    CharacterId characterId;
    String why;
    if (recentViews >= LURKER_MIN_RECENT_VIEWS
        && recentCompleted <= LURKER_MAX_RECENT_COMPLETIONS) {
      characterId = CharacterId.LURKER;
      why = "자주 들여다보지만 완료는 뜸해요.";
    } else if (hasLongGap(completedTodos)) {
      characterId = CharacterId.GHOST;
      why = "한동안 안보이다가 몰아서 완료하는 편이에요.";
    } else if (timing.score > TIMING_LATE_THRESHOLD) {
      if (completionRate >= COMPLETION_RATE_HIGH) {
        characterId = CharacterId.SPRINTER;
        why = "마감 직전에 몰아서 하지만 결국 다 해내요.";
      } else {
        characterId = CharacterId.PROCRASTINATOR;
        why = "미루다 보니 아직 못 끝낸 투두가 쌓이고 있어요.";
      }
    } else if (timing.score < TIMING_EARLY_THRESHOLD) {
      if (completionRate >= COMPLETION_RATE_THE_J
          && streak >= STEADY_STREAK_DAYS
          && timing.deadlineKeptRate >= DEADLINE_KEPT_THE_J) {
        characterId = CharacterId.THE_J;
        why = "완료율·마감 준수·꾸준함 전부 최상위예요.";
      } else {
        characterId = CharacterId.EARLYBIRD;
        why = "항상 남들보다 먼저 끝내고 여유를 즐겨요.";
      }
    } else if (streak >= STEADY_STREAK_DAYS) {
      characterId = CharacterId.STEADY;
      why = "하루도 안 빼먹고 매일 완료하고 있어요.";
    } else {
      characterId = CharacterId.TURTLE;
      why = "속도는 느긋해도 결국엔 다 완료해요.";
    }

    if (likesGiven >= CHEERLEADER_LIKES_GIVEN_THRESHOLD) {
      characterId = CharacterId.CHEERLEADER;
      why = "팀원 자료에 좋아요를 아낌없이 눌러줘요.";
    }

    Confidence confidence =
        (completedTodos.size() < MIN_COMPLETED_FOR_HIGH_CONFIDENCE
                || timing.dueDateCompletedCount == 0)
            ? Confidence.LOW
            : Confidence.HIGH;

    ActivityStatsResponse stats =
        new ActivityStatsResponse(
            completedTodos.size(),
            streak,
            timing.deadlineKeptRate,
            likesGiven,
            shared,
            timing.dueDateCompletedCount);
    return buildResponseWithEvolution(
        characterId, why, confidence, stats, completionRate, timing, streak);
  }

  private CharacterResponse buildResponse(
      CharacterId characterId, String why, Confidence confidence, ActivityStatsResponse stats) {
    return new CharacterResponse(
        characterId,
        CharacterCatalog.name(characterId),
        CharacterCatalog.copy(characterId),
        why,
        null,
        null,
        null,
        confidence,
        stats);
  }

  private CharacterResponse buildResponseWithEvolution(
      CharacterId characterId,
      String why,
      Confidence confidence,
      ActivityStatsResponse stats,
      double completionRate,
      Timing timing,
      int streak) {
    CharacterId evolveTo = EVOLUTION.get(characterId);
    Double evolveProgress = null;
    String evolveHint = null;
    if (evolveTo != null) {
      evolveProgress = evolveProgress(characterId, completionRate, timing, streak);
      evolveHint = evolveHint(characterId);
    }
    return new CharacterResponse(
        characterId,
        CharacterCatalog.name(characterId),
        CharacterCatalog.copy(characterId),
        why,
        evolveTo,
        evolveProgress,
        evolveHint,
        confidence,
        stats);
  }

  /** "이르다"(-1)~"늦다"(+1) 방향의 종합 진행도 — SPRINTER/STEADY가 EARLYBIRD로 가는 진화 힌트에도 재사용한다. */
  private double earliness(Timing timing) {
    return clamp((1 - timing.score) / 2, 0, 1);
  }

  private Double evolveProgress(
      CharacterId characterId, double completionRate, Timing timing, int streak) {
    return switch (characterId) {
      case PROCRASTINATOR -> clamp(completionRate / COMPLETION_RATE_HIGH, 0, 1);
      case GHOST, LURKER, TURTLE -> clamp((double) streak / STEADY_STREAK_DAYS, 0, 1);
      case SPRINTER, STEADY -> earliness(timing);
      case EARLYBIRD ->
          clamp(
              Math.min(
                  completionRate / COMPLETION_RATE_THE_J,
                  Math.min(
                      (double) streak / STEADY_STREAK_DAYS,
                      timing.deadlineKeptRate / DEADLINE_KEPT_THE_J)),
              0,
              1);
      default -> null;
    };
  }

  private String evolveHint(CharacterId characterId) {
    return switch (characterId) {
      case PROCRASTINATOR -> "완료율을 더 끌어올리면 진화해요";
      case GHOST, LURKER, TURTLE -> STEADY_STREAK_DAYS + "일 연속 완료하면 진화해요";
      case SPRINTER, STEADY -> "마감보다 일찍 끝내는 습관을 들이면 진화해요";
      case EARLYBIRD -> "완료율·마감 준수·꾸준함을 함께 끌어올리면 진화해요";
      default -> null;
    };
  }

  private record Timing(double score, double deadlineKeptRate, long dueDateCompletedCount) {}

  /** 3-1·3-2: 투두별 타이밍 점수를 가중평균한다. 마감 없는 투두는 본인 리드타임 중앙값 대비로 정규화한다(저리스크 기본값). */
  private Timing computeTiming(List<Todo> completedTodos) {
    List<Todo> withDueDate = completedTodos.stream().filter(t -> t.getDueDate() != null).toList();
    List<Todo> withoutDueDate =
        completedTodos.stream().filter(t -> t.getDueDate() == null).toList();

    long medianLeadHours = medianLeadHours(withoutDueDate);

    double weightedSum = 0;
    double weightTotal = 0;
    long keptDeadline = 0;
    for (Todo todo : withDueDate) {
      LocalDate completedDate = todo.getCompletedAt().atZone(KST).toLocalDate();
      long dayDiff = ChronoUnit.DAYS.between(todo.getDueDate(), completedDate);
      weightedSum += clamp(dayDiff / DUE_DATE_SCALE_DAYS, -1, 1) * DUE_DATE_WEIGHT;
      weightTotal += DUE_DATE_WEIGHT;
      if (dayDiff <= 0) {
        keptDeadline++;
      }
    }
    for (Todo todo : withoutDueDate) {
      long leadHours = Duration.between(todo.getCreatedAt(), todo.getCompletedAt()).toHours();
      double baseline = Math.max(medianLeadHours, 1);
      double relative = (leadHours - medianLeadHours) / baseline;
      weightedSum += clamp(relative, -1, 1) * LEAD_TIME_WEIGHT;
      weightTotal += LEAD_TIME_WEIGHT;
    }

    double score = weightTotal == 0 ? 0 : weightedSum / weightTotal;
    double deadlineKeptRate =
        withDueDate.isEmpty() ? 0.0 : (double) keptDeadline / withDueDate.size();
    return new Timing(score, deadlineKeptRate, withDueDate.size());
  }

  private long medianLeadHours(List<Todo> withoutDueDate) {
    List<Long> hours =
        withoutDueDate.stream()
            .map(t -> Duration.between(t.getCreatedAt(), t.getCompletedAt()).toHours())
            .sorted()
            .toList();
    if (hours.isEmpty()) {
      return 0;
    }
    int mid = hours.size() / 2;
    return hours.size() % 2 == 0 ? (hours.get(mid - 1) + hours.get(mid)) / 2 : hours.get(mid);
  }

  /** 3-4 STEADY 신호 — KST 달력 날짜 기준, 오늘(또는 어제)부터 거슬러 연속 완료가 있는 날 수. */
  private int computeCurrentStreak(List<Todo> completedTodos) {
    TreeSet<LocalDate> dates =
        completedTodos.stream()
            .map(t -> t.getCompletedAt().atZone(KST).toLocalDate())
            .collect(java.util.stream.Collectors.toCollection(TreeSet::new));
    LocalDate today = LocalDate.now(KST);
    LocalDate cursor = dates.contains(today) ? today : today.minusDays(1);
    int streak = 0;
    while (dates.contains(cursor)) {
      streak++;
      cursor = cursor.minusDays(1);
    }
    return streak;
  }

  /** GHOST 신호 — 완료일 사이 최대 공백이 크면서, 최근({@link #RECENT_WINDOW_DAYS}일)은 조용했던 경우. */
  private boolean hasLongGap(List<Todo> completedTodos) {
    TreeSet<LocalDate> dates =
        completedTodos.stream()
            .map(t -> t.getCompletedAt().atZone(KST).toLocalDate())
            .collect(java.util.stream.Collectors.toCollection(TreeSet::new));
    if (dates.size() < 2) {
      return false;
    }
    LocalDate previous = null;
    long maxGap = 0;
    for (LocalDate date : dates) {
      if (previous != null) {
        maxGap = Math.max(maxGap, ChronoUnit.DAYS.between(previous, date));
      }
      previous = date;
    }
    LocalDate today = LocalDate.now(KST);
    long daysSinceLast = ChronoUnit.DAYS.between(dates.last(), today);
    return maxGap >= GHOST_GAP_DAYS && daysSinceLast < GHOST_GAP_DAYS;
  }

  private static double clamp(double value, double min, double max) {
    return Math.max(min, Math.min(max, value));
  }
}
