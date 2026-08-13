package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.archive.client.AiEmbeddingClient;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * 임베딩 실패 폴백과 <b>무엇을 임베딩하는가</b>. 스프링·DB·네트워크 없이 검증한다.
 *
 * <p>입력 선택 규칙("요약 우선, 없으면 본문")은 코멘트로만 두면 나중에 {@code pickContent}("짧은 쪽")와 같은 것으로 오해되어 조용히 통일될 수 있다
 * — 여기서 못 박는다.
 */
class ArchiveEmbedderTest {

  private static final float[] VECTOR = {0.1f, 0.2f, 0.3f};

  /** 어떤 텍스트로 호출됐는지 기록하는 스텁. "무엇을 임베딩하는가"가 이 티켓의 설계 결정이라 입력 자체를 검사한다. */
  private static final class RecordingClient implements AiEmbeddingClient {
    private final List<String> calls = new ArrayList<>();

    @Override
    public float[] embed(String text) {
      calls.add(text);
      return VECTOR;
    }
  }

  private static ArchiveEmbedder with(AiEmbeddingClient client) {
    return new ArchiveEmbedder(Optional.ofNullable(client));
  }

  @Test
  void returnsNullWhenTheClientBeanIsAbsent() {
    // 게이트웨이 키가 없는 환경(테스트·CI). 임베딩 없이 등록이 진행돼야 한다.
    assertThat(with(null).embed("요약", "본문")).isNull();
  }

  @Test
  void swallowsClientFailureAndReturnsNull() {
    // 게이트웨이 장애·타임아웃. 등록 자체를 깨뜨리면 안 된다(태깅·요약 폴백과 같은 정책).
    ArchiveEmbedder embedder =
        with(
            text -> {
              throw new IllegalStateException("gateway down");
            });

    assertThat(embedder.embed("요약", "본문")).isNull();
  }

  @Test
  void prefersTheSummaryOverTheBody() {
    // pickContent("짧은 쪽")와 다른 규칙이다 — 질의가 짧은 방 목표라서, 긴 본문을 통째로 임베딩하면
    // 벡터가 평균화되어 무엇과도 어중간하게 닮는다. 요약이 본문보다 길어도 요약을 쓴다.
    RecordingClient client = new RecordingClient();

    with(client).embed("가".repeat(300), "짧은 본문");

    assertThat(client.calls).containsExactly("가".repeat(300));
  }

  @Test
  void fallsBackToTheBodyWhenThereIsNoSummary() {
    // V5 이전 등록분 · 요약 LLM 실패 — 요약이 없는 것은 문서화된 정상 상태다.
    RecordingClient client = new RecordingClient();

    with(client).embed(null, "본문 텍스트");

    assertThat(client.calls).containsExactly("본문 텍스트");
  }

  @Test
  void blankSummaryIsTreatedAsNoSummary() {
    RecordingClient client = new RecordingClient();

    with(client).embed("   ", "본문 텍스트");

    assertThat(client.calls).containsExactly("본문 텍스트");
  }

  @Test
  void truncatesTheBodyToTheModelInputLimit() {
    // 넘기면 400이 돌아와 임베딩이 통째로 null 이 된다 — 잘라서라도 벡터를 남기는 편이 낫다.
    // 상한값의 근거(실측 tok/char)는 ArchiveTextLimits.MAX_EMBEDDING_INPUT javadoc.
    RecordingClient client = new RecordingClient();

    with(client).embed(null, "가".repeat(ArchiveTextLimits.MAX_BODY_TEXT));

    assertThat(client.calls).hasSize(1);
    assertThat(client.calls.get(0)).hasSize(ArchiveTextLimits.MAX_EMBEDDING_INPUT);
  }

  @Test
  void doesNotCallTheClientWhenThereIsNothingToEmbed() {
    // 크롤링 전(PENDING)이라 요약도 본문도 없다. 부르면 400 이 올 뿐이라 크레딧과 왕복을 아낀다.
    RecordingClient client = new RecordingClient();

    assertThat(with(client).embed(null, null)).isNull();
    assertThat(with(client).embed("  ", "   ")).isNull();
    assertThat(client.calls).isEmpty();
  }

  @Test
  void returnsTheVectorOnSuccess() {
    assertThat(with(new RecordingClient()).embed("요약", null)).containsExactly(VECTOR);
  }
}
