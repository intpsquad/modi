package com.nomara.modi.server.domain.archive.service;

import com.nomara.modi.server.domain.archive.service.ArchiveAnalysisNotificationBuffer.Buffered;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.notification.PushNotifier;
import com.nomara.modi.server.global.notification.PushType;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 분석이 끝나면 <b>등록한 사람에게</b> 알린다(2026-08-06, 2026-10-18 개정).
 *
 * <p>🔴 <b>왜 이 알림이 필요한가.</b> 자료 등록이 양쪽 경로(인앱 S-25-C · 공유 S-25-D) 모두 비동기가 되면서, "언제 분석이 끝났는지"를 알 방법이
 * 앱을 다시 여는 것뿐이 됐다. 등록 직후 신호(스낵바 · "분석 중 N건")는 등록됐다는 것만 말해 준다.
 *
 * <p>🔴 <b>묶지 않고 바로 보낸다</b>(2026-10-18 사용자 확정, #110). 처음(2026-08-06)에는 "공유로 5건을 연달아 넣으면 알림도 5개가
 * 온다"는 이유로 마지막 확정 뒤 1분간 조용해야 보냈는데, 30초 주기까지 더해 <b>분석이 끝나고 1~1.5분 뒤에야</b> 알림이 왔다(분석 자체는 등록 뒤 약 13초면
 * 끝난다). 사용자가 "늦다"고 했고, 5건이면 5번 울리는 쪽을 택했다. 이제 다음 tick(최대 5초)에 보낸다.
 *
 * <p>⚠️ 같은 tick 사이(5초 안)에 여러 건이 끝나면 그 몫은 여전히 한 알림("자료 N건 정리 완료")으로 나간다 — 버퍼를 사람 단위로 비우기 때문이다. 일부러
 * 묶는 것이 아니라 주기의 부산물이고, 드물다.
 *
 * <p><b>받는 사람은 등록한 본인뿐이다.</b> 방 전체에 보내면 남이 올린 링크의 분석 알림까지 오게 된다.
 *
 * <p>⚠️ <b>단일 인스턴스 전제다.</b> 여럿이면 같은 사용자 몫을 둘이 집어 알림이 두 번 갈 수 있다 — {@code
 * ArchiveCrawlRetryScheduler} 와 같은 한계이고, 지금은 단일 EC2 · 단일 컨테이너다.
 */
@Component
public class ArchiveAnalysisNotifier {

  private static final Logger log = LoggerFactory.getLogger(ArchiveAnalysisNotifier.class);

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
   * 5초마다 훑어 기다리는 사람 모두에게 보낸다. 분석이 끝나고 알림이 가기까지의 최대 대기가 이 주기다.
   *
   * <p>대기자가 없으면 Redis 집합 하나만 읽고 끝나서 짧게 돌려도 부담이 없다.
   *
   * <p>주기를 프로퍼티로 뺀 이유는 <b>테스트 격리</b>다({@code ArchiveCrawlRetryScheduler} 와 같은 사정). {@code
   * fixedDelay} 는 컨텍스트가 뜨자마자 한 번 돌고 계속 도는데, 스프링 컨텍스트는 테스트 사이에 캐시된다.
   */
  @Scheduled(fixedDelayString = "${modi.archive.analysis-notify-interval:5000}")
  public void flushPendingBuffers() {
    Set<String> pending = buffer.pendingUsers();
    if (pending.isEmpty()) {
      return;
    }
    int sent = 0;
    for (String uid : pending) {
      if (sent >= MAX_PER_TICK) {
        log.info("분석 알림 한 tick 상한({})에 걸렸다 — 남은 사람은 다음 tick 에 보낸다", MAX_PER_TICK);
        break;
      }
      if (buffer.lastConfirmedAt(uid) == 0) {
        // 카운터는 없는데 목록에만 남은 경우(TTL 만료 등) — 정리하고 넘어간다.
        buffer.clear(uid);
        continue;
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
