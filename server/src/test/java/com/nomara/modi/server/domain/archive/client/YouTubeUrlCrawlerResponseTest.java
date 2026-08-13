package com.nomara.modi.server.domain.archive.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import com.sun.net.httpserver.HttpServer;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * 🔴 <b>{@code crawl()} 전체를 돈다</b> — 응답을 받아 {@code CrawlResult} 가 될 때까지의 이음매를 건다.
 *
 * <p><b>이 파일이 존재하는 이유</b>(2026-08-04): {@code YouTubeUrlCrawlerTest} 는 첫 줄에 "네트워크를 타지 않는다 — 파싱부에 직접
 * 넘긴다"라고 적어뒀다. 그래서 <b>{@code crawl()} 이 응답에서 값을 꺼내는 부분은 한 번도 실행된 적이 없었고</b>, 거기 있던 jsoup 이중 읽기 버그가
 * 하루 동안 살아 있었다. 테스트 416개는 그동안 전부 초록이었다. 실측:
 *
 * <pre>
 *   [FAIL 1124ms] youtube.com/watch?v=ZVZjJAor15Y   ValidationException: Object must not be null
 *   [FAIL  705ms] youtube.com/watch?v=zbGF4F-Qg1M   ValidationException: Object must not be null
 *   [FAIL  857ms] youtube.com/watch?v=XUcB-SLDYnA   ← 전날 성공했던 영상
 * </pre>
 *
 * <p><b>교훈은 픽스처가 작아서가 아니라 이음매를 안 건드린 것이었다.</b> 2026-08-05 에 HTML 스크래핑이 Data API 호출로 통째로 바뀌면서 그 버그
 * 자체는 사라졌지만, <b>같은 함정이 그대로 있다</b> — JSON 픽스처를 매핑 함수에 직접 넘기면 "요청을 어떻게 조립하고 응답을 어떻게 꺼내는가"는 여전히 아무도 안
 * 본다. 그래서 이 파일의 모든 테스트는 {@code crawl()} 로 들어간다.
 *
 * <p><b>인터넷을 타지 않는다</b> — 루프백에 JDK 내장 HTTP 서버를 띄우고 {@code modi.archive.youtube.api-url} 자리에 그 주소를
 * 넣는다. 그 프로퍼티가 있는 이유의 절반이 이것이다.
 */
class YouTubeUrlCrawlerResponseTest {

  private static final String VIDEO_URL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ";
  private static final String TEST_QUERY_VALUE = "unit-test-value";

  /**
   * {@code videos.list?part=snippet&id=…} 응답 모양.
   *
   * <p>구조는 Data API v3 문서의 {@code youtube#videoListResponse} 를 따르고, <b>우리가 실제로 읽는 필드가 다 온다는 것은
   * 2026-08-04 에 운영 EC2 에서 직접 호출해 확인했다</b>(제목·채널명·설명 약 2,400자·{@code thumbnails.maxres}·태그 26개). 진짜
   * 응답과 대조하는 것은 로컬 {@code bootRun} 실제 링크 검증이 맡는다 — 픽스처는 회귀를 막는 역할이다.
   *
   * <p>썸네일 5종을 전부 담아 <b>우선순위가 실제로 골라지는지</b> 보게 했고(하나만 있으면 순서를 안 탄다), 설명에는 개행과 따옴표 이스케이프를 넣었다 — 교체 전
   * 코드가 손으로 풀던 것들이라 Jackson 이 제대로 푸는지가 회귀 지점이다.
   */
  private static final String SNIPPET_JSON =
      """
      {
        "kind": "youtube#videoListResponse",
        "etag": "TEST_ETAG",
        "items": [
          {
            "kind": "youtube#video",
            "etag": "TEST_ITEM_ETAG",
            "id": "dQw4w9WgXcQ",
            "snippet": {
              "publishedAt": "2009-10-25T06:57:33Z",
              "channelId": "UCuAXFkgsw1L7xaCfnd5JJOw",
              "title": "Rick Astley - Never Gonna Give You Up (Official Video)",
              "description": "The official video.\\n\\n\\"Never\\" was a global smash.",
              "thumbnails": {
                "default":  {"url": "https://i.ytimg.com/vi/dQw4w9WgXcQ/default.jpg"},
                "medium":   {"url": "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg"},
                "high":     {"url": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"},
                "standard": {"url": "https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg"},
                "maxres":   {"url": "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"}
              },
              "channelTitle": "Rick Astley",
              "tags": ["rick astley", "never gonna give you up"],
              "categoryId": "10",
              "liveBroadcastContent": "none"
            }
          }
        ],
        "pageInfo": {"totalResults": 1, "resultsPerPage": 1}
      }
      """;

  /** 위 픽스처의 설명 줄. 통째로 갈아끼우는 테스트가 있어 따로 뺐다. */
  private static final String DESCRIPTION_FIELD =
      "\"description\": \"The official video.\\n\\n\\\"Never\\\" was a global smash.\",";

  private HttpServer server;

  /** 핸들러가 매 요청마다 기록한다 — "몇 번 불렀나"와 "무슨 쿼리로 불렀나"를 단언하기 위해서다. */
  private final AtomicInteger requestCount = new AtomicInteger();

  private final AtomicReference<String> lastQuery = new AtomicReference<>();

  private int responseStatus = 200;
  private String responseBody = SNIPPET_JSON;
  private String responseContentType = "application/json; charset=UTF-8";

  @BeforeEach
  void startServer() throws Exception {
    server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
    server.createContext(
        "/youtube/v3/videos",
        exchange -> {
          requestCount.incrementAndGet();
          lastQuery.set(exchange.getRequestURI().getRawQuery());

          byte[] body = responseBody.getBytes(StandardCharsets.UTF_8);
          exchange.getResponseHeaders().set("Content-Type", responseContentType);
          exchange.sendResponseHeaders(responseStatus, body.length);
          try (OutputStream out = exchange.getResponseBody()) {
            out.write(body);
          }
        });
    server.start();
  }

  @AfterEach
  void stopServer() {
    server.stop(0);
  }

  private String apiUrl() {
    return "http://"
        + InetAddress.getLoopbackAddress().getHostAddress()
        + ":"
        + server.getAddress().getPort()
        + "/youtube/v3/videos";
  }

  /**
   * <b>운영 생성자를 그대로 쓴다</b> — {@code api-url} 자리에 루프백 주소를 넣을 뿐이다.
   *
   * <p>{@code RestClient} 를 받는 테스트 전용 생성자를 두려다 2026-08-05 리뷰에서 접었다. 생성자가 둘이 되면 스프링이 어느 쪽인지 몰라
   * {@code @SpringBootTest} 249개가 통째로 깨지고({@code @Autowired} 로 지목해야 한다), 그 함정을 감수해서 얻는 것이 없었다 —
   * <b>어떤 테스트도 {@code RestClient} 를 mock 하지 않는다.</b> 전부 진짜 루프백 서버를 쓴다.
   */
  private YouTubeUrlCrawler crawlerWithKey(String apiKey) {
    return new YouTubeUrlCrawler(new ObjectMapper(), apiKey, apiUrl(), 5, 10);
  }

  private CrawlResult crawl() {
    return crawlerWithKey(TEST_QUERY_VALUE).crawl(VIDEO_URL);
  }

  // ------------------------------------------------------------------ 정상 경로

  @Test
  void itMapsTitleBodyAndThumbnailFromTheApiResponse() {
    CrawlResult result = crawl();

    assertThat(result.title()).isEqualTo("Rick Astley - Never Gonna Give You Up (Official Video)");
    assertThat(result.thumbnail())
        .isEqualTo("https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg");
    assertThat(result.source()).isEqualTo("youtube.com");

    // 🔴 **정확히 이 세 줄**이어야 한다. contains 로 두면 tags 가 슬쩍 섞여 들어가도 안 잡힌다 —
    // 태그를 AI 입력에 넣는 것은 측정 없이 하지 않기로 한 결정이라 여기서 못 박는다.
    assertThat(result.bodyText())
        .isEqualTo(
            """
            Rick Astley - Never Gonna Give You Up (Official Video)
            Rick Astley
            The official video.

            "Never" was a global smash.""");
  }

  @Test
  void itAsksForTheSnippetOfExactlyThatVideoWithTheKey() {
    crawl();

    // 교체 전에는 `canonicalUrl` 이 이 자리였다 — 사용자 입력이 요청이 되는 지점이라 여전히 봐야 한다.
    assertThat(lastQuery.get())
        .contains("part=snippet")
        .contains("id=dQw4w9WgXcQ")
        .contains("key=" + TEST_QUERY_VALUE);
  }

  @Test
  void aVideoWithoutMaxresFallsBackToTheNextBestThumbnail() {
    // ⚠️ 원본이 720p 미만인 옛날 영상에는 maxres 가 아예 없다(실측). 폴백이 없으면 그런 영상만
    // **썸네일이 조용히 사라진다** — 등록은 성공해서 로그에 흔적이 없다.
    responseBody =
        SNIPPET_JSON.replace(
            "\"maxres\":   {\"url\": \"https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg\"}",
            "\"unused\": {}");

    assertThat(crawl().thumbnail()).isEqualTo("https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg");
  }

  @Test
  void koreanSurvivesEvenWhenTheResponseDeclaresTheWrongCharset() {
    // 실사용 자료는 대부분 한글이라 인코딩이 깨지면 제목·요약·태그가 전부 오염된다.
    //
    // 🔴 **선언된 charset 이 틀린 경우**를 고른 이유가 있다. 우리는 응답을 바이트로 읽어 Jackson 이
    // JSON 규격대로 인코딩을 스스로 판별하게 두므로 **헤더가 틀려도 안 흔들린다.** 반대로 헤더를
    // 믿는 구현(`retrieve().body(String.class)` 등)으로 되돌아가면 여기가 바로 빨개진다 —
    // 그게 이 조건을 고른 이유다.
    //
    // ⚠️ charset 을 **안 붙인** `application/json` 으로는 구분이 안 된다. 그 경우엔
    // StringHttpMessageConverter 도 UTF-8 로 특별 취급해서(6.2.8 `getContentTypeCharset`)
    // 두 구현이 같은 결과를 낸다 — 2026-08-05 변형 테스트로 확인했고, 그래서 조건을 바꿨다.
    responseContentType = "application/json; charset=ISO-8859-1";
    responseBody =
        SNIPPET_JSON
            .replace("Rick Astley - Never Gonna Give You Up (Official Video)", "백종원의 요리비책")
            .replace("\"channelTitle\": \"Rick Astley\"", "\"channelTitle\": \"백종원\"");

    CrawlResult result = crawl();

    assertThat(result.title()).isEqualTo("백종원의 요리비책");
    assertThat(result.bodyText()).contains("백종원");
  }

  @Test
  void aVideoWithNoThumbnailAtAllStillRegisters() {
    // 썸네일이 하나도 없으면 null 이고 **등록은 성공해야 한다**. 여기서 던지면 썸네일이 없다는
    // 이유로 자료 자체가 안 들어간다 — "썸네일만 조용히 사라진다"보다 나쁘다.
    responseBody =
        """
        {"items": [{"snippet": {
          "title": "Rick Astley - Never Gonna Give You Up (Official Video)",
          "channelTitle": "Rick Astley",
          "description": "The official video.",
          "thumbnails": {}
        }}]}
        """;

    CrawlResult result = crawl();

    assertThat(result.thumbnail()).isNull();
    assertThat(result.title()).isEqualTo("Rick Astley - Never Gonna Give You Up (Official Video)");
  }

  @Test
  void aVideoWithoutADescriptionStillHasABody() {
    // 설명 없는 영상은 드물지 않다. bodyText 를 설명만으로 만들면 그런 영상이 빈 본문으로 실패한다 —
    // 제목·채널명을 함께 넣는 이유가 이것이고, 그 이유를 여기서 지킨다.
    responseBody = SNIPPET_JSON.replace(DESCRIPTION_FIELD, "\"description\": \"\",");

    assertThat(crawl().bodyText())
        .isEqualTo("Rick Astley - Never Gonna Give You Up (Official Video)\nRick Astley");
  }

  @Test
  void aBlankFieldInTheMiddleDoesNotLeaveAnEmptyLine() {
    // ⚠️ 위 테스트만으로는 빈 값 필터가 **검증되지 않는다** — 맨 뒤의 빈 값은 어차피 trim() 이
    // 먹어서 필터가 있든 없든 결과가 같다(2026-08-05 변형 테스트로 확인). 가운데가 비어야 갈린다.
    // 빈 줄이 끼면 그대로 AI 요약·임베딩 입력이 된다.
    responseBody =
        SNIPPET_JSON.replace("\"channelTitle\": \"Rick Astley\",", "\"channelTitle\": \"\",");

    assertThat(crawl().bodyText())
        .isEqualTo(
            """
            Rick Astley - Never Gonna Give You Up (Official Video)
            The official video.

            "Never" was a global smash.""");
  }

  @Test
  void anAbsurdlyLargeBodyIsCutOffInsteadOfBuffered() {
    // 교체 전 이 클래스에는 MAX_BODY_SIZE 가 있었고 형제 크롤러 셋은 지금도 쓴다. retrieve() 로 받으면
    // 무제한 버퍼링이라(실측: 64MB 를 296ms 만에 메모리로) 상한이 사라졌던 것을 리뷰가 잡았다.
    responseBody = "{\"items\":[{\"snippet\":{\"title\":\"" + "가".repeat(1_100_000) + "\"}}]}";

    assertThatThrownBy(this::crawl)
        .isInstanceOf(CrawlException.class)
        .hasMessage("영상을 불러올 수 없는 링크예요");
  }

  @Test
  void aBrokenContentTypeHeaderIsSimplyIgnored() {
    // 🔴 이건 실패 테스트가 아니라 **성공 테스트**다. retrieve() 시절에는 본문을 변환하기 전에
    // Content-Type 을 파싱해서, 깨진 헤더면 InvalidMediaTypeException(IllegalArgumentException
    // 계열)이 CrawlException 바깥으로 샜다 — 2026-08-05 리뷰가 재현했다. exchange() 는 헤더를
    // 아예 안 보므로 이제 **깨진 헤더로도 등록이 성공한다**. 예외를 안 던지는 것이 개선이다.
    responseContentType = "///bogus";

    assertThat(crawl().title()).isEqualTo("Rick Astley - Never Gonna Give You Up (Official Video)");
  }

  // ------------------------------------------------------------------ 실패 경로

  @Test
  void anEmptyItemsArrayIsAFailureNotAnEmptyResult() {
    // 200 인데 items 가 비는 경우 = 비공개·삭제·지역 차단. 인스타의 doc_id 만료와 같은 모양이다.
    responseBody = "{\"kind\": \"youtube#videoListResponse\", \"items\": [], \"pageInfo\": {}}";

    assertThatThrownBy(this::crawl)
        .isInstanceOf(CrawlException.class)
        .hasMessage("영상을 불러올 수 없는 링크예요");
  }

  @Test
  void aQuotaOrKeyRestrictionFailureBecomesACrawlException() {
    // 🔴 CrawlException 이 아니면 동기 등록은 HTTP 500, 비동기는 영구 PENDING 이 된다
    // (CompositeUrlCrawler 주석). 쿼터가 소진되는 날 그 차이가 그대로 사용자에게 간다.
    responseStatus = 403;
    responseBody =
        """
        {"error": {"code": 403, "message": "The request cannot be completed because you have\
         exceeded your quota.", "errors": [{"reason": "quotaExceeded"}]}}
        """;

    assertThatThrownBy(this::crawl)
        .isInstanceOf(CrawlException.class)
        .hasMessage("영상을 불러올 수 없는 링크예요");
  }

  @Test
  void aBodyThatIsNotJsonDoesNotEscapeAsSomethingElse() {
    // 구글이 프록시 오류 페이지(HTML)를 줄 수도 있다. 그때 JsonParseException 이 그대로 새어나가면
    // 위 403 과 같은 이유로 500 이 된다.
    responseBody = "<html><body>Service Unavailable</body></html>";

    assertThatThrownBy(this::crawl).isInstanceOf(CrawlException.class);
  }

  @Test
  void withoutAnApiKeyItFailsWithoutCallingTheApiAtAll() {
    // 키가 없으면 나갈 필요가 없는 요청이다. 그리고 supports() 는 계속 true 라야 한다 —
    // false 로 떨어뜨리면 일반 크롤러가 "본문을 찾을 수 없는 링크예요"라는 엉뚱한 문구를 낸다.
    YouTubeUrlCrawler crawler = crawlerWithKey("");

    assertThat(crawler.supports(java.net.URI.create(VIDEO_URL))).isTrue();
    assertThatThrownBy(() -> crawler.crawl(VIDEO_URL))
        .isInstanceOf(CrawlException.class)
        .hasMessage("영상을 불러올 수 없는 링크예요");
    assertThat(requestCount.get()).isZero();
  }
}
