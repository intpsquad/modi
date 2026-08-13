package com.nomara.modi.server.domain.archive.service;

import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.RejectedExecutionException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.PageRequest;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 재시도할 때가 된 자료를 다시 크롤링한다(2026-08-06).
 *
 * <p>🔴 <b>이것이 있어야 "분석 실패"가 실제로 사라진다.</b> {@code ArchiveCrawlProcessor} 는 다시 해볼 만한 실패를 {@code
 * PENDING} 으로 두고 {@code next_crawl_at} 만 찍는다 — 그것을 실제로 집어가는 것이 여기다. 없으면 항목이 "분석 중"에서 영원히 멈춘다.
 *
 * <p>{@code @Scheduled} 도입 배경은 {@link com.nomara.modi.server.global.config.SchedulingConfig} 참고. 이
 * 기능도 lazy 체크로 대체할 수 없다 — 아무도 앱을 열지 않아도 차단이 풀린 뒤 서버가 스스로 다시 긁어야 한다.
 *
 * <p><b>고정 지연(fixedDelay)이지 고정 주기가 아니다.</b> 한 tick 이 늦어져도 다음 tick 이 겹쳐 돌지 않는다. 스케줄러 스레드는 기본 1개라 이
 * 메서드끼리 겹칠 일도 없다.
 *
 * <p>⚠️ <b>인스턴스가 둘 이상이면 같은 항목을 둘이 집을 수 있다.</b> 조회와 예약 지우기가 한 원자 연산이 아니기 때문이다(JPQL 로는 {@code UPDATE
 * ... RETURNING} 을 쓸 수 없다). 지금은 단일 EC2 · 단일 컨테이너라 성립하지 않는다 — 스케일아웃할 때 이 주석을 먼저 볼 것.
 */
@Component
public class ArchiveCrawlRetryScheduler {

  private static final Logger log = LoggerFactory.getLogger(ArchiveCrawlRetryScheduler.class);

  /**
   * 한 tick 에 집어갈 최대 건수.
   *
   * <p>🔴 <b>상한이 없으면 이 기능이 스스로 차단을 부른다.</b> 차단이 길었던 뒤에는 밀린 항목이 쌓여 있는데, 그것이 한꺼번에 풀려 나가면 방금 풀린 차단을 다시
   * 부른다.
   *
   * <p>⚠️ <b>이것은 rate 가 아니라 burst 상한이다</b>(2026-08-06 리뷰). 한 tick 은 {@code archiveCrawlExecutor}
   * 큐(50)를 안 넘기지만, 처리기가 느리면 tick 세 번이 겹쳐 50 을 넘길 수 있다. 그때는 거부를 {@code rescheduleCrawl} 이 받아내므로 동작은
   * 안전하다 — 다만 "큐를 절대 안 넘긴다"고 읽으면 안 된다.
   */
  private static final int MAX_PER_TICK = 20;

  /** 큐가 차서 넘기지 못한 항목을 다시 줄 세우는 간격 — 다음 tick 무렵이다. */
  private static final Duration REQUEUE_DELAY = Duration.ofMinutes(5);

  private final ArchiveItemRepository archiveItemRepository;
  private final ArchiveCrawlProcessor archiveCrawlProcessor;

  public ArchiveCrawlRetryScheduler(
      ArchiveItemRepository archiveItemRepository, ArchiveCrawlProcessor archiveCrawlProcessor) {
    this.archiveItemRepository = archiveItemRepository;
    this.archiveCrawlProcessor = archiveCrawlProcessor;
  }

  /**
   * 5분마다 기한이 된 것을 집어 처리기에 넘긴다.
   *
   * <p><b>{@code @Transactional} 을 걸지 않는다.</b> 예약 지우기는 리포지토리의 벌크 UPDATE 가 자기 트랜잭션에서 끝내고(사유는 {@code
   * ArchiveItemRepository#clearNextCrawlAt}), 실제 처리는 {@code @Async} 라 어차피 이 트랜잭션 밖에서 돈다. 여기에 트랜잭션을
   * 걸면 tick 이 도는 내내 DB 커넥션 하나를 붙잡을 뿐이다.
   *
   * <p>재시도 간격이 20분인데 5분마다 도는 이유: 이 주기는 <b>지연의 상한</b>이다. 기한이 12:00 인 항목이 12:00~12:05 사이에 나간다.
   *
   * <p>주기를 프로퍼티로 뺀 것은 <b>테스트 격리</b> 때문이다(2026-08-06 리뷰). {@code fixedDelay} 는 컨텍스트가 뜨자마자 한 번 돌고 이후
   * 계속 도는데, 스프링 컨텍스트는 테스트 사이에 캐시된다 — 전체 스위트가 5분을 넘기면 이 배치가 다른 테스트 한가운데서 깨어나 그 테스트가 준비해 둔 상태를 집어간다.
   * 운영에서 바꿀 값이 아니다.
   */
  @Scheduled(fixedDelayString = "${modi.archive.crawl-retry-scan-interval:300000}")
  public void retryDueCrawls() {
    List<Long> due =
        archiveItemRepository.findIdsDueForCrawlRetry(
            Instant.now(), PageRequest.of(0, MAX_PER_TICK));
    if (due.isEmpty()) {
      return;
    }

    // 넘기기 **전에** 비운다 — 처리기가 느리면 다음 tick 이 같은 항목을 또 집어 외부 사이트를 두 배로 때린다.
    archiveItemRepository.clearNextCrawlAt(due);
    log.info("크롤링 재시도 대상 {}건을 집었다: itemIds={}", due.size(), due);

    for (int i = 0; i < due.size(); i++) {
      try {
        archiveCrawlProcessor.process(due.get(i));
      } catch (RejectedExecutionException e) {
        // 큐가 찼다. 뒤엣것도 마찬가지일 테니 이 tick 은 여기서 접고, 아직 못 넘긴 것을 다시 줄 세운다.
        // 안 그러면 예약이 지워진 채로 남아 영영 안 집히는 PENDING 이 된다.
        List<Long> notDispatched = List.copyOf(due.subList(i, due.size()));
        archiveItemRepository.rescheduleCrawl(notDispatched, Instant.now().plus(REQUEUE_DELAY));
        log.warn("크롤링 큐가 차서 {}건을 다시 줄 세운다: itemIds={}", notDispatched.size(), notDispatched, e);
        return;
      }
    }
  }
}
