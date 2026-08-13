package com.nomara.modi.server.domain.archive.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.archive.exception.CrawlException;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.junit.jupiter.api.Test;

/**
 * 크롤링 결과 파싱만 검증한다. 네트워크를 타지 않도록 {@code JsoupUrlCrawler.toCrawlResult}에 픽스처 HTML을 직접 넘긴다 — SSRF
 * 방어·타임아웃 등 연결 단계는 {@code ArchiveItemServiceTest}가 실제 URL로 덮는다.
 */
class JsoupUrlCrawlerTest {

  private static final String URL = "https://example.com/post/1";

  private final JsoupUrlCrawler crawler = new JsoupUrlCrawler(new UrlSafetyValidator());

  private CrawlResult parse(String html) {
    Document doc = Jsoup.parse(html, URL);
    return crawler.toCrawlResult(doc, URL);
  }

  @Test
  void noiseElementsAreStrippedFromBodyText() {
    // 기존 구현(doc.body().text())은 네비게이션·푸터·스크립트까지 전부 한 줄로 이어붙였다 —
    // 이 잡음이 태깅·요약·추천 세 프롬프트의 입력 토큰을 그대로 부풀린다.
    CrawlResult result =
        parse(
            """
            <html><body>
              <nav>홈 로그인 회원가입</nav>
              <header>사이트 이름</header>
              <script>var tracking = 1;</script>
              <style>.a { color: red; }</style>
              <aside>인기글 목록</aside>
              <p>진짜 본문이다.</p>
              <footer>이용약관 개인정보처리방침</footer>
            </body></html>
            """);

    assertThat(result.bodyText()).contains("진짜 본문이다.");
    assertThat(result.bodyText())
        .doesNotContain("로그인", "사이트 이름", "tracking", "color", "인기글", "이용약관");
  }

  @Test
  void headerInsideTheContentRootIsKept() {
    // <article><header><h1>글 제목</h1></header>은 표준 블로그 템플릿이다. 이걸 지우면 문서에서 정보 밀도가
    // 가장 높은 한 줄(제목·작성일·작성자)이 사라지는데, 태깅 프롬프트에 들어가는 건 bodyText뿐이라
    // AI 입력에서도 통째로 빠진다.
    CrawlResult result =
        parse(
            """
            <html><body>
              <header>사이트 이름 로그인</header>
              <article>
                <header><h1>글 제목이다</h1><p>2026-07-29 작성</p></header>
                <p>%s</p>
                <footer>작성자: 홍길동</footer>
              </article>
              <footer>이용약관</footer>
            </body></html>
            """
                .formatted("본문 문단이다. ".repeat(20)));

    assertThat(result.bodyText()).contains("글 제목이다", "2026-07-29 작성", "작성자: 홍길동");
    assertThat(result.bodyText()).doesNotContain("사이트 이름", "로그인", "이용약관");
  }

  @Test
  void bodyWrappedEntirelyInNoiseFallsBackToTheUncleanedText() {
    // 본문 전체가 <form> 안에 있는 사이트가 있다(고전 ASP.NET WebForms). 노이즈 제거가 본문을 통째로
    // 날리면 정제 전 텍스트로 되돌린다.
    CrawlResult result =
        parse(
            """
            <html><body><form>
              <div><p>폼 안에 있는 본문이다.</p><p>둘째 문단.</p></div>
            </form></body></html>
            """);

    assertThat(result.bodyText()).isEqualTo("폼 안에 있는 본문이다.\n둘째 문단.");
  }

  @Test
  void articleIsPreferredOverSurroundingBody() {
    CrawlResult result =
        parse(
            """
            <html><body>
              <div>관련 글</div>
              <article><p>%s</p></article>
              <div>댓글 12개</div>
            </body></html>
            """
                .formatted("본문 문단이다. ".repeat(20)));

    assertThat(result.bodyText()).startsWith("본문 문단이다.");
    assertThat(result.bodyText()).doesNotContain("관련 글", "댓글");
  }

  @Test
  void mainWinsOverAnArticleUsedAsACard() {
    // <main>이 있으면 그 안의 카드용 <article>이 아니라 main을 본문으로 본다.
    CrawlResult result =
        parse(
            """
            <html><body>
              <main>
                <article>홍보 카드</article>
                <p>%s</p>
              </main>
            </body></html>
            """
                .formatted("메인 본문이다. ".repeat(20)));

    assertThat(result.bodyText()).contains("메인 본문이다.");
    assertThat(result.bodyText()).contains("홍보 카드"); // main 안에 있으므로 함께 들어온다
  }

  @Test
  void contentRootCoveringOnlyASliceOfThePageFallsBackToBody() {
    // 실측 회귀(EXPERIMENTS #12): <article>을 목록 카드마다 쓰는 사이트에서 첫 카드(92자)가 본문(3,384자)으로
    // 선택돼 본문이 통째로 날아갔다. 후보가 페이지의 절반에 못 미치면 셀렉터가 헛짚은 것으로 보고 body를 쓴다.
    CrawlResult result =
        parse(
            """
            <html><body>
              <article>홍보 카드</article>
              <article>다른 카드</article>
              <div><p>%s</p></div>
            </body></html>
            """
                .formatted("진짜 본문이다. ".repeat(20)));

    assertThat(result.bodyText()).contains("진짜 본문이다.");
    assertThat(result.bodyText()).contains("홍보 카드"); // 폴백이므로 카드도 함께 남는다 — 본문 손실이 없는 쪽을 택한다
  }

  @Test
  void bodyIsUsedWhenNoSemanticContentRootExists() {
    // div 수프로만 된 사이트가 많다 — 이때는 (노이즈를 걷어낸) body 전체를 그대로 쓴다.
    CrawlResult result =
        parse(
            """
            <html><body>
              <nav>메뉴</nav>
              <div><div><p>div 수프 본문이다.</p></div></div>
            </body></html>
            """);

    assertThat(result.bodyText()).isEqualTo("div 수프 본문이다.");
  }

  @Test
  void emptyArticleFallsBackToBody() {
    // <article>이 껍데기뿐이고 실제 본문은 바깥에 있는 사이트가 있다. 정제 결과가 비면 본문을 통째로 잃으므로
    // body로 되돌린다.
    CrawlResult result =
        parse(
            """
            <html><body>
              <article>   </article>
              <div><p>바깥에 있는 본문이다.</p></div>
            </body></html>
            """);

    assertThat(result.bodyText()).contains("바깥에 있는 본문이다.");
  }

  @Test
  void blockBoundariesBecomeNewlinesInsteadOfOneLongLine() {
    // Jsoup의 text()는 문서 전체를 공백 하나로 이어붙여 한 줄로 만든다. LLM이 읽는 입력이므로 문단 경계를 살린다.
    CrawlResult result =
        parse(
            """
            <html><body><article>
              <h1>제목 줄</h1>
              <p>첫째 문단.</p>
              <p>둘째 문단.</p>
              <ul><li>항목 하나</li><li>항목 둘</li></ul>
            </article></body></html>
            """);

    assertThat(result.bodyText())
        .isEqualTo(
            """
            제목 줄
            첫째 문단.
            둘째 문단.
            항목 하나
            항목 둘""");
  }

  @Test
  void consecutiveBlankLinesAreCollapsed() {
    CrawlResult result =
        parse(
            """
            <html><body><article>
              <p>위 문단.</p>
              <div></div><div></div><div></div>
              <p>아래 문단.</p>
            </article></body></html>
            """);

    assertThat(result.bodyText()).isEqualTo("위 문단.\n아래 문단.");
  }

  @Test
  void titlePrefersOpenGraphOverDocumentTitle() {
    CrawlResult result =
        parse(
            """
            <html><head>
              <title>문서 제목</title>
              <meta property="og:title" content="오픈그래프 제목">
            </head><body><p>본문</p></body></html>
            """);

    assertThat(result.title()).isEqualTo("오픈그래프 제목");
  }

  @Test
  void titleFallsBackToDocumentTitleThenUrl() {
    assertThat(
            parse("<html><head><title>문서 제목</title></head><body><p>본문</p></body></html>").title())
        .isEqualTo("문서 제목");
    assertThat(parse("<html><body><p>본문</p></body></html>").title()).isEqualTo(URL);
  }

  @Test
  void thumbnailIsNullWhenOpenGraphImageIsAbsent() {
    assertThat(parse("<html><body><p>본문</p></body></html>").thumbnail()).isNull();
    assertThat(
            parse(
                    """
                    <html><head><meta property="og:image" content="https://example.com/a.png">
                    </head><body><p>본문</p></body></html>
                    """)
                .thumbnail())
        .isEqualTo("https://example.com/a.png");
  }

  @Test
  void sourceIsTheHost() {
    assertThat(parse("<html><body><p>본문</p></body></html>").source()).isEqualTo("example.com");
  }

  @Test
  void redirectStatusCodesAreRejected() {
    // 2026-07-29 실측(specs/OPEN.md): 리다이렉트 미추종 상태에서 Jsoup은 3xx를 에러로 안 봐서 예외 없이 넘어온다 —
    // 방치하면 빈/스텁 본문이 조용히 DONE으로 저장된다. 네트워크 없이 상태코드 경계만 검증한다.
    assertThatThrownBy(() -> crawler.rejectRedirectStatus(300)).isInstanceOf(CrawlException.class);
    assertThatThrownBy(() -> crawler.rejectRedirectStatus(301)).isInstanceOf(CrawlException.class);
    assertThatThrownBy(() -> crawler.rejectRedirectStatus(308)).isInstanceOf(CrawlException.class);
    assertThatThrownBy(() -> crawler.rejectRedirectStatus(399)).isInstanceOf(CrawlException.class);
  }

  @Test
  void nonRedirectStatusCodesArePassedThrough() {
    crawler.rejectRedirectStatus(200);
    crawler.rejectRedirectStatus(299);
    crawler.rejectRedirectStatus(400);
  }

  @Test
  void deadLinksAreNotRetried() {
    // 🔴 없는 글을 20분 간격으로 세 번 더 긁으면, 사용자는 한 시간 동안 "분석 중"을 보다가
    // 결국 "분석 실패"를 본다(2026-08-06 리뷰 P3). 다시 걸어도 같은 답이 온다.
    assertThat(JsoupUrlCrawler.isWorthRetrying(404)).isFalse();
    assertThat(JsoupUrlCrawler.isWorthRetrying(410)).isFalse();
    assertThat(JsoupUrlCrawler.isWorthRetrying(401)).isFalse();
    assertThat(JsoupUrlCrawler.isWorthRetrying(403)).isFalse();
    assertThat(JsoupUrlCrawler.isWorthRetrying(400)).isFalse();
  }

  @Test
  void overloadAndServerErrorsAreRetried() {
    // 반대편 말뚝 — 이쪽까지 영구 실패로 만들면 잠깐 흔들린 사이트가 그대로 실패로 굳는다.
    assertThat(JsoupUrlCrawler.isWorthRetrying(408)).isTrue(); // 요청 타임아웃
    assertThat(JsoupUrlCrawler.isWorthRetrying(429)).isTrue(); // 과호출 제한
    assertThat(JsoupUrlCrawler.isWorthRetrying(500)).isTrue();
    assertThat(JsoupUrlCrawler.isWorthRetrying(502)).isTrue();
    assertThat(JsoupUrlCrawler.isWorthRetrying(503)).isTrue();
  }

  @Test
  void iframeOnlyPageWithNoRealBodyTextFailsInsteadOfSavingEmptyBody() {
    // 2026-07-29 실측(specs/OPEN.md): 네이버 블로그 PC 주소가 이런 모양이다 — 실제 본문은 다른 iframe 주소에 있고
    // 이 페이지 자체엔 텍스트가 없다. 사이트별 iframe 추종은 하지 않기로 확정했으므로(2026-07-30) 조용히
    // 빈 본문으로 DONE 저장하지 않고 크롤링 실패로 처리한다.
    CrawlException ex =
        catchThrowableOfType(
            () ->
                parse(
                    """
                    <html><body>
                      <iframe src="https://example.com/PostView.naver?blogId=x&logNo=1"></iframe>
                    </body></html>
                    """),
            CrawlException.class);

    assertThat(ex).isNotNull();
  }
}
