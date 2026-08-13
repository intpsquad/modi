package com.nomara.modi.server.domain.archive.client;

/**
 * 자료 텍스트의 임베딩. 실패 시 호출부가 {@code null}로 폴백한다 — 임베딩이 없어도 등록은 성공해야 한다({@link AiSummaryClient}·{@link
 * AiTaggingClient}와 같은 정책).
 *
 * <p><b>이 벡터를 쓰는 쪽은 아직 없다.</b> 추천 자료 선별(RAG 2단계)이 읽을 예정이고, 그때 방 목표 문장과의 코사인 유사도로 자료 K개를 고른다. 지금 만들어
 * 두는 이유는 추천을 누를 때마다 아카이브 전체를 다시 임베딩할 수 없기 때문이다(자료당 약 1.4초 실측 — 백필 12건 평균, EXPERIMENTS #19).
 *
 * <p><b>태깅·요약과 달리 프롬프트가 없다.</b> 임베딩 API는 지시를 받지 않고 텍스트를 벡터로 바꾸기만 한다 — 그래서 프롬프트 인젝션 방어도 필요 없다(모델이
 * 본문의 지시문을 따를 여지 자체가 없다).
 */
public interface AiEmbeddingClient {

  /**
   * 텍스트를 벡터로 바꾼다.
   *
   * @param text 임베딩할 텍스트. 길이 상한은 호출부가 적용한다({@code ArchiveTextLimits.MAX_EMBEDDING_INPUT})
   * @return 임베딩 벡터. 입력이 비어 있으면 {@code null}
   */
  float[] embed(String text);
}
