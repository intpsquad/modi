package com.nomara.modi.server.domain.archive.service;

import com.nomara.modi.server.domain.archive.client.AiSummaryClient;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 본문 → AI 요약. 실패를 흡수하고 저장 가능한 길이로 잘라 준다.
 *
 * <p><b>왜 별도 컴포넌트인가.</b> 처음에는 {@link ArchiveItemService}와 {@link ArchiveCrawlProcessor}에 같은 10줄을
 * 복붙해뒀는데, 그러면 ① 두 곳이 조용히 갈라질 수 있고 ② <b>테스트할 시임이 없다</b>. 실제로 리뷰에서 "요약 호출이 던지면 등록은 성공한다"와 "500자를 넘기면
 * 잘린다"는 주장 둘 다 코멘트에만 있고 테스트가 0개라는 지적을 받았다. 여기로 모으면 두 규칙을 한 곳에서 검증할 수 있다.
 *
 * <p><b>길이 상한을 여기서 강제하는 이유.</b> {@code archive_items.summary}는 {@code VARCHAR(500)}이고 프롬프트는 300자를
 * 요구하지만 모델이 지킨다는 보장이 없다 — 실제로 프롬프트 v2에서 231자가 나온 적이 있다({@code ai/docs/EXPERIMENTS.md} #15). 상한을 넘긴
 * 값이 저장되면 비동기 경로에서 <b>커밋 시점에</b> INSERT가 터지는데, 그 예외는 {@code ArchiveCrawlProcessor.process}의 {@code
 * catch}에 걸리지 않아 {@code markCrawlFailed()}도 못 타고 항목이 영구 {@code PENDING}으로 남는다 — 그 사고는 에서 제목 길이로 이미
 * 한 번 겪었다.
 */
@Component
class ArchiveSummarizer {

  private static final Logger log = LoggerFactory.getLogger(ArchiveSummarizer.class);

  /** 키가 없으면(게이트웨이 미설정) 빈이 없다 — 그때는 요약 없이 등록을 진행한다. */
  private final Optional<AiSummaryClient> aiSummaryClient;

  ArchiveSummarizer(Optional<AiSummaryClient> aiSummaryClient) {
    this.aiSummaryClient = aiSummaryClient;
  }

  /**
   * 요약을 만든다. <b>절대 예외를 던지지 않는다</b> — 요약 실패는 자료 등록의 실패가 아니다(AI 태깅 실패 폴백과 같은 정책, specs/OPEN.md
   * 2026-07-27 확정).
   *
   * @return 500자 이내 요약, 또는 {@code null}(클라이언트 없음 · 빈 응답 · 호출 실패)
   */
  String summarize(String bodyText) {
    if (aiSummaryClient.isEmpty()) {
      return null;
    }
    try {
      return ArchiveTextLimits.truncate(
          aiSummaryClient.get().summarize(bodyText), ArchiveTextLimits.MAX_SUMMARY);
    } catch (Exception e) {
      // 조용히 삼키면 게이트웨이 장애를 운영자가 알 방법이 없으므로 로그는 남긴다.
      log.warn("AI 요약 실패 — 요약 없이 등록을 진행합니다", e);
      return null;
    }
  }
}
