package com.nomara.modi.server.domain.archive.entity;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/** 크롤링 완료 반영 규칙. 스프링·DB 없이 도메인 규칙만 본다 — 연관 엔티티는 이 규칙에 관여하지 않으므로 null로 둔다. */
class ArchiveItemTest {

  private static final String URL = "https://m.blog.naver.com/wqf00/224331064053";

  private static ArchiveItem pendingWithTitle(String title) {
    return ArchiveItem.pending(null, null, title, URL, null);
  }

  @Test
  void crawledTitleReplacesThePrefilledUrl() {
    // 공유 다이얼로그(ShareActivity)가 제목칸에 URL을 프리필하므로, 손대지 않고 등록하면 제목이 URL로 남는다.
    ArchiveItem item = pendingWithTitle(URL);

    item.markCrawlDone("오픽 IH 달성 후기", "본문", "m.blog.naver.com", null);

    assertThat(item.getTitle()).isEqualTo("오픽 IH 달성 후기");
    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
  }

  @Test
  void userTypedTitleSurvivesCrawling() {
    // 사용자가 직접 적은 제목을 og:title로 덮어쓰지 않는다.
    ArchiveItem item = pendingWithTitle("주말 모임 후보");

    item.markCrawlDone("오픽 IH 달성 후기", "본문", "m.blog.naver.com", null);

    assertThat(item.getTitle()).isEqualTo("주말 모임 후보");
  }

  @Test
  void truncatedPrefilledUrlIsStillRecognisedAsTheTitleToReplace() {
    // 저장 시 제목은 255자로 잘리는데 url 상한은 2048이다. 완전일치로 판정하면 긴 URL을 공유했을 때
    // 제목이 "중간에서 잘린 URL"로 영영 남는다 — 고치려던 증상보다 나쁘다.
    String longUrl = "https://m.blog.naver.com/wqf00/224331064053?" + "utm_source=x&".repeat(40);
    String truncated = longUrl.substring(0, 255);
    ArchiveItem item = ArchiveItem.pending(null, null, truncated, longUrl, null);

    item.markCrawlDone("오픽 IH 달성 후기", "본문", "m.blog.naver.com", null);

    assertThat(item.getTitle()).isEqualTo("오픽 IH 달성 후기");
  }

  @Test
  void blankCrawledTitleLeavesTheExistingTitleAlone() {
    // 크롤링 제목이 비면 URL이라도 남기는 편이 낫다 — title은 NOT NULL이다.
    ArchiveItem item = pendingWithTitle(URL);

    item.markCrawlDone("   ", "본문", "m.blog.naver.com", null);

    assertThat(item.getTitle()).isEqualTo(URL);
  }

  @Test
  void crawlResultIsStoredRegardlessOfTitleDecision() {
    ArchiveItem item = pendingWithTitle("직접 쓴 제목");

    item.markCrawlDone("무시될 제목", "본문 텍스트", "m.blog.naver.com", "https://img/1.png");

    assertThat(item.getBodyText()).isEqualTo("본문 텍스트");
    assertThat(item.getSource()).isEqualTo("m.blog.naver.com");
    assertThat(item.getThumbnail()).isEqualTo("https://img/1.png");
  }

  /** AI 요약. 요약이 <b>없는 것이 정상</b>인 경우가 여러 개라, 없음을 어떻게 표현하는지가 규칙의 핵심이다. */
  @Nested
  class Summary {

    @Test
    void summaryIsNullUntilItIsApplied() {
      // 크롤링 전에는 요약할 본문 자체가 없다. 마이그레이션 이전에 등록된 자료도 영구히 이 상태다.
      assertThat(pendingWithTitle(URL).getSummary()).isNull();
    }

    @Test
    void applySummaryStoresTheValue() {
      ArchiveItem item = pendingWithTitle(URL);

      item.applySummary("오픽 IH를 달성한 과정과 사용한 교재를 정리한 글이다.");

      assertThat(item.getSummary()).isEqualTo("오픽 IH를 달성한 과정과 사용한 교재를 정리한 글이다.");
    }

    @Test
    void blankSummaryIsStoredAsNull() {
      // 요약 실패 폴백이 빈 문자열을 넘기면 추천 쪽에서 "요약이 있다"고 오판한다 —
      // 없음은 한 가지 방식(null)으로만 표현한다.
      ArchiveItem item = pendingWithTitle(URL);
      item.applySummary("정상 요약");

      item.applySummary("   ");

      assertThat(item.getSummary()).isNull();
    }

    @Test
    void nullSummaryIsAccepted() {
      // 요약 LLM 호출이 실패하면 호출부가 null을 넘긴다(태깅 실패 폴백과 같은 방향).
      ArchiveItem item = pendingWithTitle(URL);

      item.applySummary(null);

      assertThat(item.getSummary()).isNull();
    }

    @Test
    void applySummaryDoesNotTouchCrawlStatusOrBody() {
      // 요약은 크롤링 결과와 독립이다 — 요약이 실패해도 자료는 DONE으로 남아야 한다.
      ArchiveItem item = pendingWithTitle(URL);
      item.markCrawlDone("글 제목", "본문 텍스트", "m.blog.naver.com", null);

      item.applySummary(null);

      assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
      assertThat(item.getBodyText()).isEqualTo("본문 텍스트");
    }
  }

  /** 임베딩. 요약과 같은 "없음은 null 하나로만" 규칙을 따르되, 빈 값의 모양이 빈 배열이다. */
  @Nested
  class Embedding {

    @Test
    void embeddingIsNullUntilItIsApplied() {
      assertThat(pendingWithTitle(URL).getEmbedding()).isNull();
    }

    @Test
    void applyEmbeddingStoresTheVector() {
      ArchiveItem item = pendingWithTitle(URL);

      item.applyEmbedding(new float[] {0.1f, -0.2f, 0.3f});

      assertThat(item.getEmbedding()).containsExactly(0.1f, -0.2f, 0.3f);
    }

    @Test
    void emptyVectorIsStoredAsNull() {
      // 길이 0짜리 배열이 남으면 읽는 쪽이 "벡터가 있다"고 보고 0으로 나누게 된다.
      ArchiveItem item = pendingWithTitle(URL);
      item.applyEmbedding(new float[] {0.1f});

      item.applyEmbedding(new float[] {});

      assertThat(item.getEmbedding()).isNull();
    }

    @Test
    void nullVectorIsAccepted() {
      // 임베딩 호출이 실패하면 호출부가 null을 넘긴다(요약·태깅 실패 폴백과 같은 방향).
      ArchiveItem item = pendingWithTitle(URL);

      item.applyEmbedding(null);

      assertThat(item.getEmbedding()).isNull();
    }

    @Test
    void applyEmbeddingDoesNotTouchCrawlStatusBodyOrSummary() {
      ArchiveItem item = pendingWithTitle(URL);
      item.markCrawlDone("글 제목", "본문 텍스트", "m.blog.naver.com", null);
      item.applySummary("요약");

      item.applyEmbedding(null);

      assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
      assertThat(item.getBodyText()).isEqualTo("본문 텍스트");
      assertThat(item.getSummary()).isEqualTo("요약");
    }
  }

  /** 사용자 메모(2026-08-06 도입). AI 요약과 같은 "없음은 null 하나로만" 정규화 규칙을 따른다. */
  @Nested
  class Memo {

    @Test
    void memoIsNullUntilItIsApplied() {
      assertThat(pendingWithTitle(URL).getMemo()).isNull();
    }

    @Test
    void editMemoStoresTheValue() {
      ArchiveItem item = pendingWithTitle(URL);

      item.editMemo("다음에 다시 읽어볼 것");

      assertThat(item.getMemo()).isEqualTo("다음에 다시 읽어볼 것");
    }

    @Test
    void blankMemoIsStoredAsNull() {
      ArchiveItem item = pendingWithTitle(URL);
      item.editMemo("메모");

      item.editMemo("   ");

      assertThat(item.getMemo()).isNull();
    }

    @Test
    void nullMemoIsAccepted() {
      ArchiveItem item = pendingWithTitle(URL);
      item.editMemo("메모");

      item.editMemo(null);

      assertThat(item.getMemo()).isNull();
    }
  }

  /** 링크 편집(2026-08-06 도입) — 새 URL로 재분석해야 하므로 옛 크롤링 결과를 지우고 PENDING으로 되돌린다. */
  @Nested
  class EditUrl {

    @Test
    void editUrlResetsCrawledDataAndPending() {
      ArchiveItem item = pendingWithTitle(URL);
      item.markCrawlDone("글 제목", "본문 텍스트", "m.blog.naver.com", "https://img/1.png");
      item.applySummary("요약");
      item.applyEmbedding(new float[] {0.1f});
      item.scheduleCrawlRetry(java.time.Instant.now());

      String newUrl = "https://example.com/new";
      item.editUrl(newUrl, newUrl);

      assertThat(item.getUrl()).isEqualTo(newUrl);
      assertThat(item.getTitle()).isEqualTo(newUrl);
      assertThat(item.getBodyText()).isNull();
      assertThat(item.getSource()).isNull();
      assertThat(item.getThumbnail()).isNull();
      assertThat(item.getSummary()).isNull();
      assertThat(item.getEmbedding()).isNull();
      assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.PENDING);
      assertThat(item.getCrawlRetries()).isZero();
      assertThat(item.getNextCrawlAt()).isNull();
    }

    @Test
    void editUrlPlaceholderTitleIsReplacedByNextCrawl() {
      // editUrl이 제목을 새 URL로 프리필해야 markCrawlDone의 titleIsStillThePrefilledUrl 판정을 타고
      // 재크롤링 결과로 교체된다 — 등록 때와 같은 규칙.
      ArchiveItem item = pendingWithTitle(URL);
      item.markCrawlDone("옛 제목", "옛 본문", "old.com", null);
      String newUrl = "https://example.com/new";

      item.editUrl(newUrl, newUrl);
      item.markCrawlDone("새 제목", "새 본문", "example.com", null);

      assertThat(item.getTitle()).isEqualTo("새 제목");
    }
  }
}
