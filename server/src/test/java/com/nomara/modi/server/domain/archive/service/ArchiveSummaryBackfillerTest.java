package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.archive.client.AiSummaryClient;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * 요약 백필의 진행 규칙 — 한 건이 실패해도 나머지를 계속 처리하고, 본문이 없으면 모델을 부르지 않는다.
 *
 * <p>(2026-10-18 까지는 요약으로 벡터를 다시 만드는 것도 여기서 못 박았다. #129 로 임베딩을 만들지 않게 되어 그 단언을 지웠다.)
 */
class ArchiveSummaryBackfillerTest {

  private final ArchiveItemRepository repository = mock(ArchiveItemRepository.class);

  private ArchiveSummaryBackfiller backfiller(AiSummaryClient summary) {
    // 채우는 일 자체는 ArchiveSummaryFiller 가 한다(2026-08-06에 꺼냈다) — 여기서는 진짜
    // 컴포넌트를 꽂아 백필이 그 규칙을 그대로 타는지 함께 본다.
    return new ArchiveSummaryBackfiller(
        repository,
        new ArchiveSummaryFiller(repository, new ArchiveSummarizer(Optional.ofNullable(summary))));
  }

  /** 요약 없이 등록된 자료 — 백필 대상의 실제 모습이다. */
  private ArchiveItem itemWithBody(String bodyText) {
    ArchiveItem item = ArchiveItem.pending(null, null, "제목", "https://example.com", null);
    item.markCrawlDone(null, bodyText, null, null);
    return item;
  }

  @Test
  void fillsTheSummary() {
    ArchiveItem item = itemWithBody("긴 본문");
    when(repository.findIdsWithoutSummary()).thenReturn(List.of(1L));
    when(repository.findById(1L)).thenReturn(Optional.of(item));

    backfiller(body -> "짧은 요약").run(null);

    assertThat(item.getSummary()).isEqualTo("짧은 요약");
    verify(repository, times(1)).save(any());
  }

  @Test
  void keepsGoingWhenOneItemFails() {
    ArchiveItem failing = itemWithBody("터지는 본문");
    ArchiveItem ok = itemWithBody("멀쩡한 본문");
    when(repository.findIdsWithoutSummary()).thenReturn(List.of(1L, 2L));
    when(repository.findById(1L)).thenReturn(Optional.of(failing));
    when(repository.findById(2L)).thenReturn(Optional.of(ok));

    backfiller(
            body -> {
              if (body.contains("터지는")) {
                throw new IllegalStateException("summary gateway down");
              }
              return "짧은 요약";
            })
        .run(null);

    assertThat(failing.getSummary()).isNull();
    assertThat(ok.getSummary()).isEqualTo("짧은 요약");
    verify(repository, times(1)).save(any());
  }

  @Test
  void doesNotCallTheModelWhenThereIsNoBody() {
    when(repository.findIdsWithoutSummary()).thenReturn(List.of(1L));
    when(repository.findById(1L)).thenReturn(Optional.of(itemWithBody(null)));

    backfiller(
            body -> {
              throw new AssertionError("본문이 없는데 요약을 불렀다");
            })
        .run(null);

    verify(repository, never()).save(any());
  }

  @Test
  void skipsItemsDeletedWhileTheBackfillWasRunning() {
    when(repository.findIdsWithoutSummary()).thenReturn(List.of(1L));
    when(repository.findById(1L)).thenReturn(Optional.empty());

    backfiller(body -> "짧은 요약").run(null);

    verify(repository, never()).save(any());
  }
}
