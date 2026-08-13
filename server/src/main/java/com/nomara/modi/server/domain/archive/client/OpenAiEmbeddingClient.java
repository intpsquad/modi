package com.nomara.modi.server.domain.archive.client;

import org.springframework.ai.embedding.EmbeddingModel;

/** 옛 LLM 게이트웨이(OpenAI 호환) 경유 임베딩 — specs/0001-architecture.md AI 기능 흐름. */
public class OpenAiEmbeddingClient implements AiEmbeddingClient {

  private final EmbeddingModel embeddingModel;

  public OpenAiEmbeddingClient(EmbeddingModel embeddingModel) {
    this.embeddingModel = embeddingModel;
  }

  @Override
  public float[] embed(String text) {
    if (text == null || text.isBlank()) {
      // 임베딩할 것이 없다. 호출하면 400이 돌아올 뿐이므로 크레딧과 왕복을 아낀다
      // (요약이 빈 본문에 대해 null을 돌려주는 것과 같은 이유).
      //
      // ⚠️ 이 분기는 지금 도달하지 않는다 — 유일한 호출자 ArchiveEmbedder.pickInput 이 빈 입력이면
      // 애초에 클라이언트를 부르지 않는다. **일부러 남긴 방어적 중복**이다: 인터페이스가 "입력이 비어
      // 있으면 null"을 계약으로 적어 뒀고, 나중에 다른 호출자(예: 배치)가 생겼을 때 그 계약이
      // 호출자 구현에만 있으면 조용히 400이 난다. 계약은 계약을 선언한 쪽이 지킨다.
      return null;
    }
    return embeddingModel.embed(text);
  }
}
