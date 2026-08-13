package com.nomara.modi.server.domain.schedule.service;

import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.schedule.entity.Schedule;
import com.nomara.modi.server.domain.schedule.repository.ScheduleRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.global.notification.PushNotifier;
import com.nomara.modi.server.global.notification.PushType;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * 일정 전날(D-1)/디데이(D-day) 푸시 배치(full_spec.md:205, specs/0015-알림-트리거.md). 방 {@code ENDED} 전환이나 방 삭제와
 * 달리 lazy 체크(요청 시점 확인)로 대체할 수 없다 — 아무도 앱을 열지 않아도 정해진 시각에 나가야 하는 알림이라, 이 기능에 한해 {@code @Scheduled}
 * 배치를 처음 도입한다({@link com.nomara.modi.server.global.config.SchedulingConfig}).
 *
 * <p><b>타임존</b>: 배포 컨테이너에 {@code TZ}가 없어 JVM이 UTC로 돈다(server/Dockerfile 확인, 2026-08-05). cron의
 * {@code zone}과 날짜 계산 모두 KST를 명시해야 실제로 08:00 KST에 도는 배치가 된다.
 *
 * <p><b>디데이 기준</b>: 다중일 일정이어도 시작일({@code date})만 본다 — {@code endDate}는 확인하지 않는다(2026-08-05 확정).
 * <b>방이 아직 끝나지 않았는지</b>는 {@code Room.status}가 아니라 {@code Room.endDate}로 직접 판단한다 — status는 {@code
 * RoomService.refreshStatus}가 요청 시점에만 lazy 갱신하므로, 아무도 열어보지 않은 방은 실제로 끝났어도 DB엔 여전히 ACTIVE로 남아 있을 수
 * 있기 때문이다({@link ScheduleRepository#findByDateForActiveRooms}).
 */
@Service
public class ScheduleReminderService {

  private static final Logger log = LoggerFactory.getLogger(ScheduleReminderService.class);

  /**
   * 이 배치가 "오늘"을 판단하는 기준 시간대.
   *
   * <p>🔴 <b>{@code private} 이 아닌 이유: 테스트가 같은 기준을 써야 하기 때문</b>(2026-08-06). 테스트가 {@code
   * LocalDate.now()} (JVM 기본 시간대)로 픽스처를 만들고 있었는데, CI 컨테이너는 <b>UTC</b> 라 KST 09:00 이전에 빌드가 돌면 하루가
   * 어긋나 5개가 전부 깨졌다 — 실제로 {@code 2026-08-05 20:10Z}(= KST 08-06 05:10) 빌드에서 dev 가 막혔다.
   *
   * <p>값을 복사해 쓰면 같은 어긋남이 다시 난다. 여기를 바꾸면 테스트도 같이 움직이도록 <b>하나만 둔다.</b>
   */
  static final ZoneId KST = ZoneId.of("Asia/Seoul");

  /** 08:00 직후 재기동·수동 재실행에도 같은 날 같은 일정이 두 번 나가지 않도록 이 기간만큼 Redis에 발송 사실을 남긴다. */
  private static final Duration DEDUP_TTL = Duration.ofDays(2);

  private final ScheduleRepository scheduleRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final PushNotifier pushNotifier;
  private final StringRedisTemplate redisTemplate;

  public ScheduleReminderService(
      ScheduleRepository scheduleRepository,
      RoomMemberRepository roomMemberRepository,
      PushNotifier pushNotifier,
      StringRedisTemplate redisTemplate) {
    this.scheduleRepository = scheduleRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.pushNotifier = pushNotifier;
    this.redisTemplate = redisTemplate;
  }

  private static final String DDAY_TITLE = "오늘이에요! 일정 잊지 마세요 ⏰";
  private static final String DAY_BEFORE_TITLE = "내일 일정 미리 알려드려요 📅";

  @Scheduled(cron = "0 0 8 * * *", zone = "Asia/Seoul")
  public void sendDailyScheduleReminders() {
    LocalDate today = LocalDate.now(KST);
    remind(today, today, PushType.SCHEDULE_DDAY, "dday", DDAY_TITLE);
    remind(today.plusDays(1), today, PushType.SCHEDULE_DAY_BEFORE, "day-before", DAY_BEFORE_TITLE);
  }

  /**
   * 조회 자체가 실패해도(DB 순단 등) 다음 실행은 보장돼야 하고, 한 일정 처리 중 실패가 같은 날 다른 일정·다른 타입(D-1/D-day)의 발송까지 막으면 안
   * 된다(2026-08-05 리뷰 지적) — 그래서 조회와 일정 1건 처리를 각각 별도로 방어한다.
   */
  private void remind(
      LocalDate scheduleDate, LocalDate today, PushType type, String dedupPrefix, String title) {
    List<Schedule> schedules;
    try {
      schedules = scheduleRepository.findByDateForActiveRooms(scheduleDate, today);
    } catch (Exception e) {
      log.warn("일정 알림 대상 조회 실패: date={}", scheduleDate, e);
      return;
    }
    for (Schedule schedule : schedules) {
      try {
        remindOne(schedule, today, type, dedupPrefix, title);
      } catch (Exception e) {
        log.warn("일정 알림 처리 중 오류: scheduleId={}", schedule.getId(), e);
      }
    }
  }

  /**
   * 실패할 수 있는 조회(회원 목록)를 전부 끝낸 뒤에야 Redis 클레임을 남긴다 — 순서를 반대로 하면(클레임 먼저) 그 사이 조회가 실패해도 이 일정은 "발송됨"으로
   * 찍혀, 같은 날 수동으로 재실행해도 다시 시도되지 않는다(2026-08-05 리뷰 지적).
   */
  private void remindOne(
      Schedule schedule, LocalDate today, PushType type, String dedupPrefix, String title) {
    List<RoomMember> members = roomMemberRepository.findMembersByRoomId(schedule.getRoom().getId());
    List<User> targets = members.stream().map(RoomMember::getUser).toList();
    if (!claim(dedupPrefix, schedule.getId(), today)) {
      return;
    }
    pushNotifier.notifyEach(targets, type, schedule.getRoom(), title, body(schedule));
  }

  /**
   * 2026-08-09 문구 개편(docs/backend/notification-handoff.md §B) — 1줄은 {@code 제목 · 방이름}, 2번째 줄은 시간·장소
   * 중 있는 것만 ` · `로 이어 붙인다. 둘 다 없으면 2번째 줄 자체를 생략한다.
   */
  private static String body(Schedule schedule) {
    String firstLine = schedule.getTitle() + " · " + schedule.getRoom().getName();
    String secondLine =
        Stream.of(formatTime(schedule.getTime()), schedule.getPlace())
            .filter(part -> part != null && !part.isBlank())
            .collect(Collectors.joining(" · "));
    return secondLine.isEmpty() ? firstLine : firstLine + "\n" + secondLine;
  }

  /** {@code "오전/오후 h시"}, 분이 있으면 {@code "오전/오후 h시 m분"}. 시간 미지정 일정이면 {@code null}. */
  private static String formatTime(LocalTime time) {
    if (time == null) {
      return null;
    }
    String period = time.getHour() < 12 ? "오전" : "오후";
    int hour12 = time.getHour() % 12 == 0 ? 12 : time.getHour() % 12;
    return time.getMinute() == 0
        ? period + " " + hour12 + "시"
        : period + " " + hour12 + "시 " + time.getMinute() + "분";
  }

  private boolean claim(String dedupPrefix, Long scheduleId, LocalDate today) {
    String key = "schedule:reminder:" + dedupPrefix + ":" + scheduleId + ":" + today;
    Boolean claimed = redisTemplate.opsForValue().setIfAbsent(key, "1", DEDUP_TTL);
    return Boolean.TRUE.equals(claimed);
  }
}
