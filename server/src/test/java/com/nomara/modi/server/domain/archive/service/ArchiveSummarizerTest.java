package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.archive.client.AiSummaryClient;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * 요약 실패 폴백과 길이 상한. 두 규칙 모두 <b>코멘트에만 있고 테스트가 0개</b>라는 리뷰 지적을 받아 추가했다 — 스프링·DB·네트워크 없이 검증한다.
 *
 * <p>이 규칙들이 없으면 어떻게 되는지는 {@link ArchiveSummarizer} javadoc 참고. 특히 길이 상한이 새면 비동기 경로에서 항목이 영구 {@code
 * PENDING}으로 남는다.
 */
class ArchiveSummarizerTest {

  private static ArchiveSummarizer with(AiSummaryClient client) {
    return new ArchiveSummarizer(Optional.ofNullable(client));
  }

  @Test
  void returnsNullWhenTheClientBeanIsAbsent() {
    // 게이트웨이 키가 없는 환경(테스트·CI). 요약 없이 등록이 진행돼야 한다.
    assertThat(with(null).summarize("본문")).isNull();
  }

  @Test
  void swallowsClientFailureAndReturnsNull() {
    // 게이트웨이 장애·타임아웃. 등록 자체를 깨뜨리면 안 된다(AI 태깅 실패 폴백과 같은 정책).
    ArchiveSummarizer summarizer =
        with(
            bodyText -> {
              throw new IllegalStateException("gateway down");
            });

    assertThat(summarizer.summarize("본문")).isNull();
  }

  @Test
  void truncatesToTheColumnWidth() {
    // 프롬프트가 300자를 요구하지만 모델이 지킨다는 보장은 없다 — 200자 목표 시절 v2에서 실제로 231자가
    // 나왔다(#15). 목표를 300자로 올린 뒤의 초과 폭은 안 쟀다.
    // summary 는 VARCHAR(500)이고, 넘긴 값이 저장되면 비동기 경로에서 커밋 시점에 INSERT 가 터져
    // 항목이 영구 PENDING 으로 남는다.
    ArchiveSummarizer summarizer = with(bodyText -> "가".repeat(600));

    assertThat(summarizer.summarize("본문")).hasSize(ArchiveTextLimits.MAX_SUMMARY);
  }

  @Test
  void keepsSummariesThatFitAsIs() {
    ArchiveSummarizer summarizer = with(bodyText -> "강릉 카페 세 곳을 방문한다.");

    assertThat(summarizer.summarize("본문")).isEqualTo("강릉 카페 세 곳을 방문한다.");
  }

  @Test
  void passesNullThroughWhenTheModelReturnsNothing() {
    // OpenAiSummaryClient.normalize 가 빈 응답을 null 로 눌러 보낸다.
    assertThat(with(bodyText -> null).summarize("본문")).isNull();
  }
}
