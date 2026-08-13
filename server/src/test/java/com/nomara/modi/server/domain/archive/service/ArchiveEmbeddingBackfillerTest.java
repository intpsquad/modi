package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.archive.client.AiEmbeddingClient;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * 백필의 진행 규칙. 여기서 지켜야 할 것은 하나다 — <b>한 건이 실패해도 나머지를 계속 처리한다.</b> 백필은 자료 전체를 훑는 작업이라 첫 실패에서 멈추면 운영자가
 * 그걸 알아채지 못한 채 "백필했다"고 믿게 된다.
 *
 * <p>플래그가 꺼져 있을 때 아예 안 도는 것은 {@code @ConditionalOnProperty}가 보장하므로(빈 자체가 없다) 여기서 검증할 것이 없다 — 스프링 없이
 * 도는 테스트라 그 조건을 재현할 수도 없다.
 */
class ArchiveEmbeddingBackfillerTest {

  private static final float[] VECTOR = {0.1f, 0.2f};

  private final ArchiveItemRepository repository = mock(ArchiveItemRepository.class);

  private ArchiveEmbeddingBackfiller backfiller(AiEmbeddingClient client) {
    return new ArchiveEmbeddingBackfiller(repository, new ArchiveEmbedder(Optional.of(client)));
  }

  private ArchiveItem itemWithBody(String bodyText) {
    ArchiveItem item = ArchiveItem.pending(null, null, "제목", "https://example.com", null);
    item.markCrawlDone(null, bodyText, null, null);
    return item;
  }

  @Test
  void fillsEveryItemThatHasNoEmbedding() {
    ArchiveItem first = itemWithBody("본문1");
    ArchiveItem second = itemWithBody("본문2");
    when(repository.findIdsWithoutEmbedding()).thenReturn(List.of(1L, 2L));
    when(repository.findById(1L)).thenReturn(Optional.of(first));
    when(repository.findById(2L)).thenReturn(Optional.of(second));

    backfiller(text -> VECTOR).run(null);

    assertThat(first.getEmbedding()).containsExactly(VECTOR);
    assertThat(second.getEmbedding()).containsExactly(VECTOR);
    verify(repository, times(2)).save(any());
  }

  @Test
  void keepsGoingWhenOneItemFails() {
    // 첫 건에서 게이트웨이가 터져도 두 번째는 채워져야 한다.
    ArchiveItem failing = itemWithBody("터지는 본문");
    ArchiveItem ok = itemWithBody("멀쩡한 본문");
    when(repository.findIdsWithoutEmbedding()).thenReturn(List.of(1L, 2L));
    when(repository.findById(1L)).thenReturn(Optional.of(failing));
    when(repository.findById(2L)).thenReturn(Optional.of(ok));

    backfiller(
            text -> {
              if (text.contains("터지는")) {
                throw new IllegalStateException("gateway down");
              }
              return VECTOR;
            })
        .run(null);

    assertThat(failing.getEmbedding()).isNull();
    assertThat(ok.getEmbedding()).containsExactly(VECTOR);
    verify(repository, times(1)).save(any());
  }

  @Test
  void doesNotSaveWhenThereIsNothingToEmbed() {
    // 본문도 요약도 없는 자료 — 불러 봐야 null 이라 UPDATE 를 만들지 않는다.
    when(repository.findIdsWithoutEmbedding()).thenReturn(List.of(1L));
    when(repository.findById(1L)).thenReturn(Optional.of(itemWithBody(null)));

    backfiller(text -> VECTOR).run(null);

    verify(repository, never()).save(any());
  }

  @Test
  void skipsItemsDeletedWhileTheBackfillWasRunning() {
    when(repository.findIdsWithoutEmbedding()).thenReturn(List.of(1L));
    when(repository.findById(1L)).thenReturn(Optional.empty());

    backfiller(text -> VECTOR).run(null);

    verify(repository, never()).save(any());
  }
}
