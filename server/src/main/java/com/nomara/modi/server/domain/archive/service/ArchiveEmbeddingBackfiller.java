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
 * 이미 등록된 자료에 임베딩을 채운다. <b>기본적으로 돌지 않는다</b> — {@code modi.archive.backfill-embeddings=true}로 기동할 때만
 * 빈이 만들어진다.
 *
 * <p><b>왜 기본이 꺼짐인가.</b> 자료 1건마다 임베딩 호출 1회 = 게이트웨이 크레딧이다. 부팅할 때마다 도는 것도 아니고 한 번만 필요한 작업인데, 켜져 있으면
 * 배포할 때마다 "채울 게 없는지" 확인하는 쿼리가 돌고 실수로 모델을 바꾼 날에는 전부 다시 불린다. 운영자가 의도적으로 한 번 켜는 편이 맞다.
 *
 * <p><b>UPDATE는 한 건씩 각자 커밋한다.</b> 전체를 한 트랜잭션으로 묶으면 ① 200건짜리 백필 도중 한 건이 터졌을 때 앞의 199건이 함께 날아가고 ② 그동안
 * DB 커넥션 하나를 외부 호출 시간(건당 약 1.4초)만큼 붙잡는다. 백필은 중간에 멈춰도 다시 켜면 남은 것부터 이어서 하면 되는 작업이라 원자성이 필요 없다.
 *
 * <p><b>기동을 막지 않는다.</b> {@code ApplicationRunner}는 컨텍스트가 다 뜬 뒤 실행되고, 예외는 여기서 삼킨다 — 백필 실패로 서버가 안 뜨면
 * 그게 더 나쁘다.
 */
@Component
@ConditionalOnProperty(name = "modi.archive.backfill-embeddings", havingValue = "true")
class ArchiveEmbeddingBackfiller implements ApplicationRunner {

  private static final Logger log = LoggerFactory.getLogger(ArchiveEmbeddingBackfiller.class);

  private final ArchiveItemRepository archiveItemRepository;
  private final ArchiveEmbedder archiveEmbedder;

  ArchiveEmbeddingBackfiller(
      ArchiveItemRepository archiveItemRepository, ArchiveEmbedder archiveEmbedder) {
    this.archiveItemRepository = archiveItemRepository;
    this.archiveEmbedder = archiveEmbedder;
  }

  @Override
  public void run(ApplicationArguments args) {
    List<Long> ids = archiveItemRepository.findIdsWithoutEmbedding();
    log.info("자료 임베딩 백필 시작 — 대상 {}건", ids.size());

    int filled = 0;
    int skipped = 0;
    for (Long id : ids) {
      if (fillOne(id)) {
        filled++;
      } else {
        skipped++;
      }
    }
    // 남은 건수를 함께 남긴다 — "다 됐다"와 "임베딩할 텍스트가 없어 영영 안 채워진다"를 구분해야
    // 다음에 또 켰을 때 같은 건수가 나오는 것을 보고 놀라지 않는다.
    log.info("자료 임베딩 백필 완료 — 채움 {}건 · 건너뜀 {}건(임베딩할 텍스트 없음·호출 실패)", filled, skipped);
  }

  /**
   * 한 건을 채운다. 실패는 로그만 남기고 다음 건으로 넘어간다 — 자료 하나 때문에 나머지를 포기할 이유가 없다.
   *
   * @return 실제로 벡터를 저장했으면 {@code true}
   */
  private boolean fillOne(Long id) {
    try {
      ArchiveItem item = archiveItemRepository.findById(id).orElse(null);
      if (item == null) {
        // 백필이 도는 동안 사용자가 지운 항목.
        return false;
      }
      float[] embedding = archiveEmbedder.embed(item.getSummary(), item.getBodyText());
      if (embedding == null) {
        return false;
      }
      item.applyEmbedding(embedding);
      archiveItemRepository.save(item);
      return true;
    } catch (Exception e) {
      log.warn("자료 임베딩 백필 실패 — 이 항목만 건너뜁니다: itemId={}", id, e);
      return false;
    }
  }
}
