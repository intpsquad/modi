package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.RejectedExecutionException;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.springframework.data.domain.Pageable;

/**
 * 재시도 배치가 재는 것은 <b>집는 규칙</b>이다 — 크롤링 자체는 {@code ArchiveCrawlProcessor} 의 몫이다.
 *
 * <p>스프링을 띄우지 않는다. 여기서 확인할 것이 "무엇을, 몇 건, 어떤 순서로 넘기는가"뿐이라 컨테이너가 필요 없다.
 */
class ArchiveCrawlRetrySchedulerTest {

  private final ArchiveItemRepository archiveItemRepository = mock(ArchiveItemRepository.class);
  private final ArchiveCrawlProcessor archiveCrawlProcessor = mock(ArchiveCrawlProcessor.class);

  private final ArchiveCrawlRetryScheduler scheduler =
      new ArchiveCrawlRetryScheduler(archiveItemRepository, archiveCrawlProcessor);

  @Test
  void 기한이_된_항목을_처리기에_넘긴다() {
    givenDue(11L, 22L);

    scheduler.retryDueCrawls();

    verify(archiveCrawlProcessor).process(11L);
    verify(archiveCrawlProcessor).process(22L);
  }

  @Test
  void 지금_시각까지_기한이_된_것만_묻는다() {
    givenDue(11L);
    Instant before = Instant.now();

    scheduler.retryDueCrawls();

    ArgumentCaptor<Instant> dueBy = ArgumentCaptor.forClass(Instant.class);
    verify(archiveItemRepository).findIdsDueForCrawlRetry(dueBy.capture(), any());
    // 미래까지 당겨오면 20분 간격이 무의미해진다 — 예약하자마자 다시 긁는다.
    assertThat(dueBy.getValue()).isBetween(before, before.plusSeconds(60));
  }

  @Test
  void 집을_때_다음_시도_예약을_먼저_비운다() {
    // 순서가 요점이다. 넘긴 뒤에 비우면 그 사이 다음 tick 이 같은 항목을 또 집어
    // 외부 사이트를 두 배로 때린다 — 이 기능이 없애려던 차단을 이 기능이 부른다.
    givenDue(11L, 22L);

    scheduler.retryDueCrawls();

    InOrder order = inOrder(archiveItemRepository, archiveCrawlProcessor);
    order.verify(archiveItemRepository).clearNextCrawlAt(List.of(11L, 22L));
    order.verify(archiveCrawlProcessor).process(11L);
  }

  @Test
  void 한_tick_에_집는_건수에_상한이_있다() {
    // 차단이 길었던 뒤 밀린 항목이 한꺼번에 풀려 나가면 방금 풀린 차단을 다시 부른다.
    givenDue(11L);

    scheduler.retryDueCrawls();

    ArgumentCaptor<Pageable> pageable = ArgumentCaptor.forClass(Pageable.class);
    verify(archiveItemRepository).findIdsDueForCrawlRetry(any(), pageable.capture());
    assertThat(pageable.getValue().getPageSize()).isEqualTo(20);
  }

  @Test
  void 집을_것이_없으면_아무것도_건드리지_않는다() {
    when(archiveItemRepository.findIdsDueForCrawlRetry(any(), any())).thenReturn(List.of());

    scheduler.retryDueCrawls();

    // 빈 목록으로 UPDATE 를 날리면 "where id in ()" 이라 DB 방언에 따라 터진다.
    verify(archiveItemRepository, never()).clearNextCrawlAt(any());
    verify(archiveCrawlProcessor, never()).process(anyLong());
  }

  @Test
  void 큐가_차면_아직_못_넘긴_것을_다시_줄_세운다() {
    // 예약을 이미 지웠으므로 여기서 아무것도 안 하면 영영 안 집히는 PENDING 이 된다 —
    // 재시도가 없애려던 상태(영구 "분석 중")를 재시도가 만드는 꼴이다.
    givenDue(11L, 22L, 33L);
    doThrow(new RejectedExecutionException("큐 참")).when(archiveCrawlProcessor).process(22L);
    Instant before = Instant.now();

    scheduler.retryDueCrawls();

    ArgumentCaptor<Instant> next = ArgumentCaptor.forClass(Instant.class);
    verify(archiveItemRepository).rescheduleCrawl(eq(List.of(22L, 33L)), next.capture());
    assertThat(Duration.between(before, next.getValue()))
        .isBetween(Duration.ofMinutes(5), Duration.ofMinutes(6));
  }

  @Test
  void 큐가_차면_그_tick_은_거기서_멈춘다() {
    // 뒤엣것도 어차피 거절된다 — 계속 밀어봐야 예외만 쌓인다.
    givenDue(11L, 22L, 33L);
    doThrow(new RejectedExecutionException("큐 참")).when(archiveCrawlProcessor).process(22L);

    scheduler.retryDueCrawls();

    verify(archiveCrawlProcessor).process(11L);
    verify(archiveCrawlProcessor, never()).process(33L);
  }

  private void givenDue(Long... ids) {
    when(archiveItemRepository.findIdsDueForCrawlRetry(any(), any())).thenReturn(List.of(ids));
  }
}
