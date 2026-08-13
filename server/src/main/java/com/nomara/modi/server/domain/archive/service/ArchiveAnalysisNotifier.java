package com.nomara.modi.server.domain.archive.service;

import com.nomara.modi.server.domain.archive.service.ArchiveAnalysisNotificationBuffer.Buffered;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.notification.PushNotifier;
import com.nomara.modi.server.global.notification.PushType;
import java.time.Duration;
import java.time.Instant;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 모아둔 분석 결과를 <b>사람당 한 번씩</b> 알린다(2026-08-06).
 *
 * <p>🔴 <b>왜 이 알림이 필요한가.</b> 자료 등록이 양쪽 경로(인앱 S-25-C · 공유 S-25-D) 모두 비동기가 되면서, "언제 분석이 끝났는지"를 알 방법이
 * 앱을 다시 여는 것뿐이 됐다. 등록 직후 신호(스낵바 · "분석 중 N건")는 등록됐다는 것만 말해 준다.
 *
 * <p><b>왜 묶어 보내나</b>(사용자 확정 2026-08-06): 공유로 5건을 연달아 넣으면 알림도 5개가 온다. 마지막 확정 뒤 {@link #QUIET_PERIOD}
 * 동안 조용하면 그때 한 번만 보낸다.
 *
 * <p><b>받는 사람은 등록한 본인뿐이다.</b> 방 전체에 보내면 남이 올린 링크의 분석 알림까지 오게 된다.
 *
 * <p>⚠️ <b>단일 인스턴스 전제다.</b> 여럿이면 같은 사용자 몫을 둘이 집어 알림이 두 번 갈 수 있다 — {@code
 * ArchiveCrawlRetryScheduler} 와 같은 한계이고, 지금은 단일 EC2 · 단일 컨테이너다.
 */
@Component
public class ArchiveAnalysisNotifier {

  private static final Logger log = LoggerFactory.getLogger(ArchiveAnalysisNotifier.class);

  /**
   * 마지막 확정 뒤 이만큼 조용하면 보낸다.
   *
   * <p>짧으면 묶는 의미가 없고(연달아 넣는 동안 여러 번 나간다), 길면 "끝났다"를 늦게 안다. 크롤링 한 건이 보통 수 초~수십 초라 1분이면 연속 등록을 대부분 한
   * 묶음으로 담는다. ⚠️ 실측이 아니라 추정값이다 — 실제 사용 패턴을 보고 고칠 것.
   */
  private static final Duration QUIET_PERIOD = Duration.ofMinutes(1);

  /** 한 tick 에 알릴 최대 인원 — 한꺼번에 몰릴 때 FCM 호출이 폭주하지 않게. */
  private static final int MAX_PER_TICK = 50;

  private final ArchiveAnalysisNotificationBuffer buffer;
  private final UserRepository userRepository;
  private final PushNotifier pushNotifier;

  public ArchiveAnalysisNotifier(
      ArchiveAnalysisNotificationBuffer buffer,
      UserRepository userRepository,
      PushNotifier pushNotifier) {
    this.buffer = buffer;
    this.userRepository = userRepository;
    this.pushNotifier = pushNotifier;
  }

  /**
   * 30초마다 훑는다 — 조용해진 사람만 골라 보낸다.
   *
   * <p>주기를 프로퍼티로 뺀 이유는 <b>테스트 격리</b>다({@code ArchiveCrawlRetryScheduler} 와 같은 사정). {@code
   * fixedDelay} 는 컨텍스트가 뜨자마자 한 번 돌고 계속 도는데, 스프링 컨텍스트는 테스트 사이에 캐시된다.
   */
  @Scheduled(fixedDelayString = "${modi.archive.analysis-notify-interval:30000}")
  public void flushQuietBuffers() {
    Set<String> pending = buffer.pendingUsers();
    if (pending.isEmpty()) {
      return;
    }
    long quietBefore = Instant.now().minus(QUIET_PERIOD).toEpochMilli();
    int sent = 0;
    for (String uid : pending) {
      if (sent >= MAX_PER_TICK) {
        log.info("분석 알림 한 tick 상한({})에 걸렸다 — 남은 사람은 다음 tick 에 보낸다", MAX_PER_TICK);
        break;
      }
      long last = buffer.lastConfirmedAt(uid);
      if (last == 0) {
        // 카운터는 없는데 목록에만 남은 경우(TTL 만료 등) — 정리하고 넘어간다.
        buffer.clear(uid);
        continue;
      }
      if (last > quietBefore) {
        continue; // 아직 처리 중이다. 다음 tick 에 다시 본다.
      }
      if (flushOne(uid)) {
        sent++;
      }
    }
  }

  /**
   * @return 실제로 보냈으면 {@code true}
   */
  private boolean flushOne(String uid) {
    Buffered buffered = buffer.takeFor(uid);
    if (buffered == null) {
      return false;
    }
    User target = userRepository.findById(uid).orElse(null);
    if (target == null) {
      // 그 사이 탈퇴했다. 버퍼는 takeFor 가 이미 비웠다.
      return false;
    }
    try {
      // room=null — 이 알림은 유저 단위로 여러 방의 결과를 묶을 수 있어 단일 room이 없다(specs/0017).
      pushNotifier.notify(
          target, PushType.ARCHIVE_ANALYSIS_DONE, null, title(buffered), body(buffered));
      return true;
    } catch (RuntimeException e) {
      // 버퍼는 이미 비웠으므로 이 건은 사라진다. 알림 하나 못 보내는 것이 배치를 멈추는 것보다 낫다.
      log.warn("분석 알림을 보내지 못했다: uid={}", uid, e);
      return false;
    }
  }

  /**
   * 알림 제목.
   *
   * <p>1건 성공이면 <b>고정 문구</b>를 쓴다(2026-08-09 사용자 확정) — 어떤 자료인지는 본문이 제목·방 이름으로 말해 준다. 1건 실패는 여전히 제목을
   * 그대로 써서 "무엇이 실패했는지"를 알린다.
   */
  static String title(Buffered b) {
    boolean onlyFailed = b.doneCount() == 0;
    if (b.total() == 1 && b.title() != null && !b.title().isBlank()) {
      // 1건 성공은 2026-08-09 사용자 확정으로 고정 문구를 쓴다 — 어떤 자료인지는 body()가 제목·방
      // 이름으로 말해 준다. 실패는 dev에서 합류한 이모지 카피(정리 완료 ✨/못 가져왔어요 😢 계열)를 유지한다.
      return onlyFailed ? "「" + b.title() + "」 못 가져왔어요 😢" : "AI로 자료 분석이 끝났어요";
    }
    if (onlyFailed) {
      return "자료 " + b.failedCount() + "건 못 가져왔어요 😢";
    }
    if (b.failedCount() == 0) {
      return "자료 " + b.doneCount() + "건 정리 완료 ✨";
    }
    return "자료 " + b.doneCount() + "건 완료 · " + b.failedCount() + "건 실패";
  }

  /**
   * 본문.
   *
   * <p>1건 성공이면 <b>제목·방 이름을 넣어</b> 어디 가서 볼지 바로 알려준다(2026-08-09 사용자 확정). 여러 건이면 여러 방에 걸칠 수 있어(§
   * {@code ArchiveAnalysisNotificationBuffer}) 방 이름을 쓰지 않고 기존 문구를 유지한다.
   */
  static String body(Buffered b) {
    boolean onlyFailed = b.doneCount() == 0;
    if (b.total() == 1
        && !onlyFailed
        && b.title() != null
        && !b.title().isBlank()
        && b.roomName() != null
        && !b.roomName().isBlank()) {
      return b.title() + "의 내용을 " + b.roomName() + " 모아보기에서 확인해보세요";
    }
    return onlyFailed ? "링크는 저장돼 있어요. 모아보기에서 확인해 보세요" : "모아보기에서 확인해 보세요";
  }
}
