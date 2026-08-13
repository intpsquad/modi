package com.nomara.modi.server.domain.archive.service;

import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * 이미 등록된 자료에 요약을 채우고 <b>그 요약으로 벡터를 다시 만든다</b>. {@link ArchiveEmbeddingBackfiller}와 같은 구조이며 그쪽
 * javadoc의 설계 결정 셋(기본 꺼짐 · 건별 커밋 · 기동을 막지 않음)이 여기에도 그대로 유효하다.
 *
 * <p><b>왜 필요한가.</b> 요약이 없으면 추천 프롬프트에 본문 전체가 실린다. 실측(부산 여행 방, 자료 8건): 요약 있는 4건이 529자인데 요약 없는 4건이
 * 34,206자로 <b>프롬프트의 98%</b>였고, 그 본문은 크롤링에 딸려온 블로그 UI 텍스트({@code "본문 폰트 크기 조정 … URL복사 신고"})가 섞인
 * 원문이었다. 모델이 읽는 것의 대부분이 잡음이면 후보 품질이 그만큼 나빠진다.
 *
 * <p><b>⚠️ 요약만 채우면 안 된다 — 벡터도 다시 만들어야 한다.</b> {@link ArchiveEmbedder}는 <b>요약이 있으면 요약을, 없으면 본문을</b>
 * 임베딩한다. 요약만 채우면 한 방 안에 "요약으로 만든 벡터"와 "본문으로 만든 벡터"가 섞여, 추천의 유사도 축이 <b>서로 다른 잣대로 만든 벡터를 비교</b>하게 된다.
 * 그리고 이 어긋남은 {@link ArchiveEmbeddingBackfiller}로는 못 고친다 — 그쪽은 {@code embedding is null}인 것만 찾는데 이
 * 항목들은 이미 (본문 기반) 벡터를 갖고 있어 건너뛰기 때문이다. 그래서 여기서 직접 다시 임베딩한다.
 */
@Component
@ConditionalOnProperty(name = "modi.archive.backfill-summaries", havingValue = "true")
class ArchiveSummaryBackfiller implements ApplicationRunner {

  private static final Logger log = LoggerFactory.getLogger(ArchiveSummaryBackfiller.class);

  private final ArchiveItemRepository archiveItemRepository;
  private final ArchiveSummaryFiller summaryFiller;

  ArchiveSummaryBackfiller(
      ArchiveItemRepository archiveItemRepository, ArchiveSummaryFiller summaryFiller) {
    this.archiveItemRepository = archiveItemRepository;
    this.summaryFiller = summaryFiller;
  }

  @Override
  public void run(ApplicationArguments args) {
    List<Long> ids = archiveItemRepository.findIdsWithoutSummary();
    log.info("자료 요약 백필 시작 — 대상 {}건", ids.size());

    int filled = 0;
    int skipped = 0;
    for (Long id : ids) {
      if (fillOne(id)) {
        filled++;
      } else {
        skipped++;
      }
    }
    // 임베딩 백필과 같은 이유로 남은 건수를 함께 남긴다 — "다 됐다"와 "요약할 본문이 없어 영영
    // 안 채워진다"를 구분해야 다음에 또 켰을 때 같은 건수를 보고 놀라지 않는다.
    log.info("자료 요약 백필 완료 — 채움 {}건 · 건너뜀 {}건(본문 없음·호출 실패)", filled, skipped);
  }

  /**
   * 한 건을 채운다. 실패는 로그만 남기고 다음 건으로 넘어간다.
   *
   * <p>실제 채우는 일은 {@link ArchiveSummaryFiller} 가 한다 — 사용자가 자료 상세에서 버튼으로 요청하는 경로와 <b>같은 규칙</b>을 써야 하기
   * 때문이다(2026-08-06에 꺼냈다).
   *
   * @return 실제로 요약을 저장했으면 {@code true}
   */
  private boolean fillOne(Long id) {
    ArchiveItem item = archiveItemRepository.findById(id).orElse(null);
    if (item == null) {
      // 백필이 도는 동안 사용자가 지운 항목.
      return false;
    }
    return summaryFiller.fill(item);
  }
}
