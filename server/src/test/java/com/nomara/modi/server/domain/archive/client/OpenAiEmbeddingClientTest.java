package com.nomara.modi.server.domain.archive.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.Test;
import org.springframework.ai.embedding.EmbeddingModel;

/**
 * {@link AiEmbeddingClient} 계약("입력이 비어 있으면 호출하지 않고 {@code null}")을 이 클래스가 지키는지 본다.
 *
 * <p>지금은 유일한 호출자({@code ArchiveEmbedder})가 먼저 걸러 주므로 이 분기가 도달하지 않지만, 계약은 계약을 선언한 쪽이 지켜야 한다 — 나중에 다른
 * 호출자가 생겼을 때 조용히 400이 나지 않게 여기서 못 박는다.
 */
class OpenAiEmbeddingClientTest {

  private static final float[] VECTOR = {0.1f, 0.2f};

  private final EmbeddingModel embeddingModel = mock(EmbeddingModel.class);
  private final OpenAiEmbeddingClient client = new OpenAiEmbeddingClient(embeddingModel);

  @Test
  void delegatesToTheModel() {
    when(embeddingModel.embed("강릉 여행 코스")).thenReturn(VECTOR);

    assertThat(client.embed("강릉 여행 코스")).containsExactly(VECTOR);
  }

  @Test
  void doesNotCallTheModelForEmptyInput() {
    assertThat(client.embed(null)).isNull();
    assertThat(client.embed("")).isNull();
    assertThat(client.embed("   ")).isNull();

    verify(embeddingModel, never()).embed(anyString());
  }
}
