package com.nomara.modi.server.domain.archive.client;

/**
 * 자료 본문의 AI 요약. 실패 시 호출부가 {@code null}로 폴백한다 — 요약이 없어도 등록은 성공해야 한다({@link AiTaggingClient}와 같은 정책).
 *
 * <p><b>왜 태깅과 별개의 호출인가.</b> 원래 설계는 태깅 호출에 요약을 합치는 것이었다(prompt +47 tok, {@code
 * ai/docs/EXPERIMENTS.md} #8). 2026-07-30에 분리로 바꿨다 — 합치려면 이미 잘 돌고 있는 태깅 프롬프트를 쉼표 구분에서 JSON으로 바꿔야
 * 하고, 그러면 <b>JSON 파싱이 깨질 때 태그까지 함께 날아간다.</b> 분리하면 등록 시 본문을 한 번 더 보내는 비용(자료당 약 5,834 tok)이 들지만 그건
 * 자료당 1회이고, 요약을 쓰는 진짜 이득(추천 프롬프트 45분의 1)은 그대로 남는다. 근거는 {@code ai/docs/DECISIONS.md}.
 */
public interface AiSummaryClient {

  /**
   * 본문을 4~6문장·300자 이내로 요약한다.
   *
   * <p>⚠️ <b>하한은 없다 — 되살리지 말 것.</b> "내용이 충분하면 250자 이상" 같은 하한을 넣으면 원문이 얇은 자료에서 모델이 분량을 채우려고 <b>계정명을
   * 집어넣는다</b>({@code ai/docs/EXPERIMENTS.md} #32 ②, 실측). 짧은 요약이 규칙 위반보다 낫다. 실제 길이 분포는 평균 152.9자 ·
   * 최대 231자다.
   *
   * @return 요약. 모델이 빈 응답을 주면 {@code null}
   */
  String summarize(String bodyText);
}
