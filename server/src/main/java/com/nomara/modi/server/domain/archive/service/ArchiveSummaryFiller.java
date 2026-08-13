package com.nomara.modi.server.domain.archive.service;

import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 자료 하나에 <b>요약을 채우고 그 요약으로 벡터를 다시 만든다.</b>
 *
 * <p>{@code ArchiveSummaryBackfiller.fillOne} 에 있던 것을 꺼냈다(2026-08-06). 꺼낸 이유는 <b>같은 일을 사용자가 버튼으로도
 * 요청하게 됐기 때문</b>이다 — 텍스트 등록은 자동 요약을 하지 않고, 필요한 사람이 자료 상세에서 만든다({@code
 * ArchiveItemService.summarizeItem}). 백필과 버튼이 같은 규칙을 쓰려면 한 곳에 있어야 한다.
 *
 * <p>⚠️ <b>요약만 채우면 안 된다 — 벡터도 다시 만들어야 한다.</b> {@link ArchiveEmbedder} 는 <b>요약이 있으면 요약을, 없으면 본문을</b>
 * 임베딩한다. 요약만 채우면 한 방 안에 "요약으로 만든 벡터"와 "본문으로 만든 벡터"가 섞여, 추천의 유사도 축이 서로 다른 잣대로 만든 벡터를 비교하게 된다.
 *
 * <p><b>재임베딩이 실패해도 요약은 저장한다.</b> 요약이 있는 편이 없는 편보다 낫고(추천 프롬프트가 수만 자에서 수백 자로 준다), 벡터는 기존 본문 기반 값이 남아
 * 유사도 축이 죽지는 않는다.
 */
@Component
public class ArchiveSummaryFiller {

  private static final Logger log = LoggerFactory.getLogger(ArchiveSummaryFiller.class);

  private final ArchiveItemRepository archiveItemRepository;
  private final ArchiveSummarizer archiveSummarizer;
  private final ArchiveEmbedder archiveEmbedder;

  public ArchiveSummaryFiller(
      ArchiveItemRepository archiveItemRepository,
      ArchiveSummarizer archiveSummarizer,
      ArchiveEmbedder archiveEmbedder) {
    this.archiveItemRepository = archiveItemRepository;
    this.archiveSummarizer = archiveSummarizer;
    this.archiveEmbedder = archiveEmbedder;
  }

  /**
   * 이 항목의 요약을 만들어 저장한다.
   *
   * @return 실제로 요약을 저장했으면 {@code true}. 본문이 없거나 호출이 실패하면 {@code false} — <b>예외를 던지지 않는다</b>(백필이 한 건
   *     때문에 멈추지 않게 하려던 원래 계약이다). 사용자 요청 경로는 이 값을 보고 응답을 정한다.
   */
  public boolean fill(ArchiveItem item) {
    String bodyText = item.getBodyText();
    if (bodyText == null || bodyText.isBlank()) {
      return false;
    }
    try {
      // ArchiveSummarizer 는 예외를 던지지 않는다 — 실패는 null 로 온다.
      String summary = archiveSummarizer.summarize(bodyText);
      if (summary == null || summary.isBlank()) {
        return false;
      }
      item.applySummary(summary);

      float[] embedding = archiveEmbedder.embed(item.getSummary(), bodyText);
      if (embedding == null) {
        log.warn("요약은 채웠지만 재임베딩에 실패했습니다 — 벡터는 본문 기반으로 남습니다: itemId={}", item.getId());
      } else {
        item.applyEmbedding(embedding);
      }

      archiveItemRepository.save(item);
      return true;
    } catch (Exception e) {
      log.warn("자료 요약을 채우지 못했습니다: itemId={}", item.getId(), e);
      return false;
    }
  }
}
