package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.archive.client.AiEmbeddingClient;
import com.nomara.modi.server.domain.archive.client.AiSummaryClient;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * 요약 백필의 진행 규칙. {@link ArchiveEmbeddingBackfillerTest}와 같은 성질(한 건이 실패해도 나머지를 계속 처리한다)에 더해, <b>이 백필의
 * 존재 이유인 재임베딩</b>을 못 박는다.
 *
 * <p>요약만 채우면 한 방 안에 "요약으로 만든 벡터"와 "본문으로 만든 벡터"가 섞여 추천의 유사도 축이 서로 다른 잣대로 비교하게 된다. 그런데 그 어긋남은 기존 임베딩
 * 백필러로 못 고친다(벡터가 이미 있어서 건너뛴다). 재임베딩이 빠지면 이 클래스를 만든 이유의 절반이 사라진다.
 */
class ArchiveSummaryBackfillerTest {

  private static final float[] FROM_SUMMARY = {0.9f, 0.9f};

  private final ArchiveItemRepository repository = mock(ArchiveItemRepository.class);

  private ArchiveSummaryBackfiller backfiller(AiSummaryClient summary, AiEmbeddingClient embed) {
    // 채우는 일 자체는 ArchiveSummaryFiller 가 한다(2026-08-06에 꺼냈다) — 여기서는 진짜
    // 컴포넌트를 꽂아 백필이 그 규칙을 그대로 타는지 함께 본다.
    return new ArchiveSummaryBackfiller(
        repository,
        new ArchiveSummaryFiller(
            repository,
            new ArchiveSummarizer(Optional.ofNullable(summary)),
            new ArchiveEmbedder(Optional.ofNullable(embed))));
  }

  /** 요약 없이 등록됐지만 <b>본문 기반 벡터는 이미 있는</b> 자료 — 백필 대상의 실제 모습이다. */
  private ArchiveItem itemWithBody(String bodyText) {
    ArchiveItem item = ArchiveItem.pending(null, null, "제목", "https://example.com", null);
    item.markCrawlDone(null, bodyText, null, null);
    item.applyEmbedding(new float[] {0.1f, 0.1f});
    return item;
  }

  @Test
  void fillsTheSummaryAndRebuildsTheVectorFromIt() {
    ArchiveItem item = itemWithBody("긴 본문");
    when(repository.findIdsWithoutSummary()).thenReturn(List.of(1L));
    when(repository.findById(1L)).thenReturn(Optional.of(item));

    // 임베딩 클라이언트가 받은 입력이 **본문이 아니라 요약**이어야 한다.
    backfiller(
            body -> "짧은 요약",
            text -> {
              assertThat(text).isEqualTo("짧은 요약");
              return FROM_SUMMARY;
            })
        .run(null);

    assertThat(item.getSummary()).isEqualTo("짧은 요약");
    assertThat(item.getEmbedding()).containsExactly(FROM_SUMMARY);
    verify(repository, times(1)).save(any());
  }

  @Test
  void keepsTheSummaryWhenReEmbeddingFails() {
    // 요약이 있는 편이 없는 편보다 낫다 — 프롬프트가 수만 자에서 수백 자로 줄어드는 것이 본론이다.
    ArchiveItem item = itemWithBody("긴 본문");
    when(repository.findIdsWithoutSummary()).thenReturn(List.of(1L));
    when(repository.findById(1L)).thenReturn(Optional.of(item));

    backfiller(
            body -> "짧은 요약",
            text -> {
              throw new IllegalStateException("embedding gateway down");
            })
        .run(null);

    assertThat(item.getSummary()).isEqualTo("짧은 요약");
    assertThat(item.getEmbedding()).containsExactly(0.1f, 0.1f); // 본문 기반 값이 남는다
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
            },
            text -> FROM_SUMMARY)
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
            },
            text -> FROM_SUMMARY)
        .run(null);

    verify(repository, never()).save(any());
  }

  @Test
  void skipsItemsDeletedWhileTheBackfillWasRunning() {
    when(repository.findIdsWithoutSummary()).thenReturn(List.of(1L));
    when(repository.findById(1L)).thenReturn(Optional.empty());

    backfiller(body -> "짧은 요약", text -> FROM_SUMMARY).run(null);

    verify(repository, never()).save(any());
  }
}
