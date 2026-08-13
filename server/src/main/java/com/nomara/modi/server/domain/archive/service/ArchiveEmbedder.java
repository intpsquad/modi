package com.nomara.modi.server.domain.archive.service;

import com.nomara.modi.server.domain.archive.client.AiEmbeddingClient;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 자료 텍스트 → 임베딩 벡터. 실패를 흡수하고 <b>무엇을 임베딩할지</b>를 정한다.
 *
 * <p>{@link ArchiveSummarizer}와 같은 이유로 별도 컴포넌트다 — 붙이는 자리가 셋(동기 등록 2경로 + 크롤링 비동기 1경로)이라 규칙을 복붙하면 조용히
 * 갈라지고, 무엇보다 <b>테스트할 시임이 없다.</b>
 */
@Component
class ArchiveEmbedder {

  private static final Logger log = LoggerFactory.getLogger(ArchiveEmbedder.class);

  /** 키가 없으면(게이트웨이 미설정) 빈이 없다 — 그때는 임베딩 없이 등록을 진행한다. */
  private final Optional<AiEmbeddingClient> aiEmbeddingClient;

  ArchiveEmbedder(Optional<AiEmbeddingClient> aiEmbeddingClient) {
    this.aiEmbeddingClient = aiEmbeddingClient;
  }

  /**
   * 자료의 임베딩을 만든다. <b>절대 예외를 던지지 않는다</b> — 임베딩 실패는 자료 등록의 실패가 아니다(태깅·요약 폴백과 같은 정책).
   *
   * @return 벡터, 또는 {@code null}(클라이언트 없음 · 넣을 텍스트 없음 · 호출 실패)
   */
  float[] embed(String summary, String bodyText) {
    if (aiEmbeddingClient.isEmpty()) {
      return null;
    }
    String input = pickInput(summary, bodyText);
    if (input == null) {
      return null;
    }
    try {
      return aiEmbeddingClient.get().embed(input);
    } catch (Exception e) {
      // 조용히 삼키면 게이트웨이 장애를 운영자가 알 방법이 없으므로 로그는 남긴다.
      log.warn("자료 임베딩 실패 — 임베딩 없이 등록을 진행합니다", e);
      return null;
    }
  }

  /**
   * <b>요약 우선, 없으면 본문(잘라서).</b> 추천 프롬프트가 쓰는 규칙({@code TodoSuggestionPayloadLoader.pickContent} —
   * 요약·본문 중 <b>짧은 쪽</b>)과 <b>일부러 다르다.</b> 그쪽 기준은 프롬프트 토큰 절약이고 여기 기준은 검색 품질이다:
   *
   * <ul>
   *   <li>질의가 <b>방 목표</b>(짧은 문장)다. 7,000토큰짜리 본문을 통째로 임베딩하면 벡터가 평균화되어 무엇과도 어중간하게 닮는다 — 긴 문서일수록 특정
   *       목표와의 유사도가 오히려 흐려진다.
   *   <li>요약(실측 115~236자)은 "이 자료가 무엇에 관한 것인가"로 이미 압축돼 있어 목표 매칭에 유리하다.
   * </ul>
   *
   * <p>그래서 요약이 <b>짧아서</b> 고르는 것이 아니라 <b>요약이라서</b> 고른다. 요약이 없는 경우(V5 이전 등록분 · {@code PENDING} · 요약
   * 실패)에만 본문을 쓰고, 모델 입력 상한에서 역산한 길이로 자른다({@link ArchiveTextLimits#MAX_EMBEDDING_INPUT}).
   */
  private static String pickInput(String summary, String bodyText) {
    if (summary != null && !summary.isBlank()) {
      return summary;
    }
    if (bodyText == null || bodyText.isBlank()) {
      return null;
    }
    return ArchiveTextLimits.truncate(bodyText, ArchiveTextLimits.MAX_EMBEDDING_INPUT);
  }
}
