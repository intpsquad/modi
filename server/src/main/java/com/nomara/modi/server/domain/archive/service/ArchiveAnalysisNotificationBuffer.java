package com.nomara.modi.server.domain.archive.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 자료 분석이 끝난 것을 <b>사람별로 모아 둔다</b> — 보내는 것은 {@code ArchiveAnalysisNotifier} 가 한다(2026-08-06).
 *
 * <p>🔴 <b>왜 바로 안 보내고 모으나.</b> 공유로 5건을 연달아 넣으면 알림도 5개가 온다. 사용자 확정(2026-08-06): <b>잠깐 모았다가 한 번</b>.
 * 마지막 확정 뒤 잠시 조용하면 그때 한 번만 보낸다.
 *
 * <p><b>왜 Redis 인가</b> — 이 상태는 잃어도 되는 것이다(알림 하나 못 보내는 것뿐). DB 테이블을 만들면 마이그레이션·정리 배치가 따라온다. 쿨다운과 같은
 * 판단이다.
 *
 * <p>🔴 <b>커밋된 뒤에 센다.</b> 처리기는 {@code @Transactional} 안에서 도는데, 거기서 바로 세면 <b>롤백된 작업까지 알림에
 * 들어간다</b>(항목이 삭제돼 FK 위반이 나는 경로가 실제로 있다). 트랜잭션이 열려 있으면 커밋 후로 미룬다.
 *
 * <p>⚠️ <b>Redis 가 죽으면 알림을 포기한다(fail-open).</b> 쿨다운과 같은 방향 — 알림 하나 못 보내는 것이 자료 등록을 막는 것보다 낫다. 대신
 * 조용히 넘어가지 않도록 로그를 남긴다.
 */
@Component
public class ArchiveAnalysisNotificationBuffer {

  private static final Logger log =
      LoggerFactory.getLogger(ArchiveAnalysisNotificationBuffer.class);

  /**
   * 버퍼 수명.
   *
   * <p>스위퍼가 정상이면 1~2분 안에 비워진다. TTL 은 <b>스위퍼가 죽었을 때</b>를 위한 것이다 — 서버가 몇 시간 뒤에 살아나 "6시간 전에 끝난 자료"를
   * 알리는 편보다 조용히 사라지는 편이 낫다.
   */
  private static final Duration TTL = Duration.ofHours(1);

  static final String PENDING_USERS = "archive:notify:pending";

  private final StringRedisTemplate redisTemplate;

  public ArchiveAnalysisNotificationBuffer(StringRedisTemplate redisTemplate) {
    this.redisTemplate = redisTemplate;
  }

  /** 분석이 끝났다(성공). {@code title}·{@code roomName} 은 1건일 때 문구에 쓴다. */
  public void recordDone(String uid, String title, String roomName) {
    record(uid, "done", title, roomName);
  }

  /**
   * 분석이 실패로 확정됐다.
   *
   * <p>⚠️ <b>재시도로 밀린 것은 여기 오면 안 된다.</b> 그건 아직 실패가 아니라서, 20분 뒤 성공할 것에 대해 실패를 먼저 알리게 된다. 호출 지점은
   * {@code ArchiveCrawlProcessor} 가 {@code markCrawlFailed()} 를 부르는 자리뿐이다.
   */
  public void recordFailed(String uid, String title, String roomName) {
    record(uid, "failed", title, roomName);
  }

  private void record(String uid, String kind, String title, String roomName) {
    if (uid == null) {
      // 작성자가 탈퇴하면 created_by 가 null 이 된다(V9). 보낼 곳이 없다.
      return;
    }
    afterCommit(
        () -> {
          try {
            redisTemplate.opsForValue().increment(key(uid, kind));
            redisTemplate.expire(key(uid, kind), TTL);
            if (title != null) {
              // 1건일 때 제목을 그대로 쓰려고 남긴다. 여러 건이면 개수만 쓰므로 덮어써도 무방하다.
              redisTemplate.opsForValue().set(key(uid, "title"), title, TTL);
            }
            if (roomName != null) {
              // title 과 같은 규칙 — 1건일 때만 쓰이고, 여러 건이면(여러 방 걸칠 수 있어) 안 쓰이므로 덮어써도 무방하다.
              redisTemplate.opsForValue().set(key(uid, "room"), roomName, TTL);
            }
            redisTemplate
                .opsForValue()
                .set(key(uid, "last"), String.valueOf(Instant.now().toEpochMilli()), TTL);
            redisTemplate.opsForSet().add(PENDING_USERS, uid);
            redisTemplate.expire(PENDING_USERS, TTL);
          } catch (RuntimeException e) {
            log.warn("분석 알림 버퍼에 적지 못했다 — 이 건은 알리지 않는다(fail-open): uid={}", uid, e);
          }
        });
  }

  /** 모아둔 것을 읽고 지운다. 없으면 {@code null}. */
  public Buffered takeFor(String uid) {
    try {
      String done = redisTemplate.opsForValue().get(key(uid, "done"));
      String failed = redisTemplate.opsForValue().get(key(uid, "failed"));
      String title = redisTemplate.opsForValue().get(key(uid, "title"));
      String roomName = redisTemplate.opsForValue().get(key(uid, "room"));
      String last = redisTemplate.opsForValue().get(key(uid, "last"));
      clear(uid);
      int doneCount = parse(done);
      int failedCount = parse(failed);
      if (doneCount == 0 && failedCount == 0) {
        return null;
      }
      return new Buffered(doneCount, failedCount, title, roomName, parseLong(last));
    } catch (RuntimeException e) {
      log.warn("분석 알림 버퍼를 읽지 못했다(fail-open): uid={}", uid, e);
      return null;
    }
  }

  /** 마지막으로 확정된 시각(epoch millis). 없으면 0. */
  public long lastConfirmedAt(String uid) {
    try {
      return parseLong(redisTemplate.opsForValue().get(key(uid, "last")));
    } catch (RuntimeException e) {
      log.warn("분석 알림 버퍼 시각을 읽지 못했다(fail-open): uid={}", uid, e);
      return 0;
    }
  }

  /** 알림을 기다리는 사람들. */
  public Set<String> pendingUsers() {
    try {
      Set<String> members = redisTemplate.opsForSet().members(PENDING_USERS);
      return members == null ? Set.of() : members;
    } catch (RuntimeException e) {
      log.warn("분석 알림 대기자 목록을 읽지 못했다(fail-open)", e);
      return Set.of();
    }
  }

  public void clear(String uid) {
    try {
      redisTemplate.delete(
          java.util.List.of(
              key(uid, "done"),
              key(uid, "failed"),
              key(uid, "title"),
              key(uid, "room"),
              key(uid, "last")));
      redisTemplate.opsForSet().remove(PENDING_USERS, uid);
    } catch (RuntimeException e) {
      log.warn("분석 알림 버퍼를 비우지 못했다 — 다음 tick 에 중복 발송될 수 있다: uid={}", uid, e);
    }
  }

  /**
   * 트랜잭션이 열려 있으면 커밋 뒤에, 아니면 지금 실행한다.
   *
   * <p>롤백되면 아예 실행하지 않는다 — 그것이 이 래퍼의 목적이다.
   */
  private static void afterCommit(Runnable action) {
    if (!TransactionSynchronizationManager.isSynchronizationActive()) {
      action.run();
      return;
    }
    TransactionSynchronizationManager.registerSynchronization(
        new TransactionSynchronization() {
          @Override
          public void afterCommit() {
            action.run();
          }
        });
  }

  private static int parse(String value) {
    try {
      return value == null ? 0 : Integer.parseInt(value);
    } catch (NumberFormatException e) {
      return 0;
    }
  }

  private static long parseLong(String value) {
    try {
      return value == null ? 0 : Long.parseLong(value);
    } catch (NumberFormatException e) {
      return 0;
    }
  }

  private static String key(String uid, String kind) {
    return "archive:notify:" + uid + ":" + kind;
  }

  /** 한 사람 몫으로 모인 결과. {@code roomName}은 1건일 때만 의미가 있다(여러 건이면 여러 방 걸칠 수 있어 안 쓴다). */
  public record Buffered(
      int doneCount, int failedCount, String title, String roomName, long lastConfirmedAt) {

    public int total() {
      return doneCount + failedCount;
    }
  }
}
