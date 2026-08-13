package com.nomara.modi.server.domain.archive.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * 🔴 <b>{@code crawl()} 전체를 돈다</b> — 단축 주소를 펼치고, 업종 경로로 한 홉 넘어가고, 응답에서 {@code CrawlResult} 가 될 때까지의
 * 이음매를 전부 건다.
 *
 * <p><b>왜 이렇게 하는가</b>(2026-08-04 교훈): 유튜브 크롤러는 파싱부에만 픽스처를 넣어 테스트했고, 그래서 {@code crawl()} 이 응답에서 값을
 * 꺼내는 두 줄은 <b>한 번도 실행된 적이 없었다.</b> 그 두 줄이 하루 동안 깨져 있었고 테스트 416개는 초록이었다.
 *
 * <p><b>인터넷을 타지 않는다</b> — 루프백에 JDK 내장 HTTP 서버를 띄우고 {@code short-url-host}·{@code place-url}· {@code
 * allowed-hosts} 를 그쪽으로 돌린다. 그 셋을 프로퍼티로 뺀 이유의 전부가 이것이다.
 *
 * <p><b>단축 호스트는 {@code 127.0.0.1}, 장소 호스트는 {@code localhost} 로 나눠 쓴다</b> — 둘 다 루프백이지만 이름이 달라야 "단축
 * 주소인가"를 호스트로 가르는 실제 분기를 그대로 탈 수 있다.
 */
class NaverUrlCrawlerResponseTest {

  private static final String PLACE_ID = "1810277002";

  /**
   * {@code m.place.naver.com/restaurant/1810277002/home} 의 <b>실제 응답을 줄인 것</b>. 값·이스케이프·엔티티 순서가 원문
   * 그대로다 — 지어낸 픽스처는 실제 페이지에서 헛돈다(유튜브 전례). 자세한 내용은 파일 머리 주석 참고.
   */
  private static String fixture() throws Exception {
    try (var in =
        NaverUrlCrawlerResponseTest.class.getResourceAsStream("/fixtures/naver-place.html")) {
      return new String(in.readAllBytes(), StandardCharsets.UTF_8);
    }
  }

  private HttpServer server;
  private String placeHtml;

  /** 핸들러가 기록한다 — "무엇을 몇 번 불렀나"와 "무슨 UA 로 불렀나"를 단언하기 위해서다. */
  private final AtomicInteger shortHits = new AtomicInteger();

  private final AtomicInteger placeHits = new AtomicInteger();
  private final AtomicInteger typeHits = new AtomicInteger();

  /**
   * <b>모든</b> 요청의 UA 를 모은다.
   *
   * <p>⚠️ 처음에는 마지막 요청의 UA 만 붙들었는데, 그러면 <b>단축 주소 요청의 UA 는 아무도 안 본다</b> — 2026-08-05 변형 테스트에서 그쪽만 PC
   * UA 로 바꿨더니 테스트가 그대로 통과했다. 세 요청이 전부 모바일이어야 한다.
   */
  private final List<String> userAgents = Collections.synchronizedList(new ArrayList<>());

  /** 단축 주소가 펼쳐질 곳. 테스트마다 갈아끼운다. */
  private String shortRedirectsTo;

  /** {@code /place/{id}/home} 이 업종 경로로 넘길지. 실제로 업종에 따라 갈린다. */
  private boolean placeRedirectsToType = true;

  /** 업종 홉의 목적지. 여기도 호스트 검증을 받아야 한다 — 갈아끼워서 확인한다. */
  private String placeRedirectsTo;

  @BeforeEach
  void startServer() throws Exception {
    placeHtml = fixture();
    server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);

    server.createContext(
        "/short",
        exchange -> {
          shortHits.incrementAndGet();
          userAgents.add(exchange.getRequestHeaders().getFirst("User-Agent"));
          exchange.getResponseHeaders().set("Location", shortRedirectsTo);
          exchange.sendResponseHeaders(307, -1);
          exchange.close();
        });

    server.createContext(
        "/place",
        exchange -> {
          placeHits.incrementAndGet();
          userAgents.add(exchange.getRequestHeaders().getFirst("User-Agent"));
          if (placeRedirectsToType) {
            exchange.getResponseHeaders().set("Location", placeRedirectsTo);
            exchange.sendResponseHeaders(302, -1);
            exchange.close();
            return;
          }
          respond(exchange, placeHtml);
        });

    server.createContext(
        "/restaurant",
        exchange -> {
          typeHits.incrementAndGet();
          userAgents.add(exchange.getRequestHeaders().getFirst("User-Agent"));
          respond(exchange, placeHtml);
        });

    server.start();
    shortRedirectsTo = loopback("localhost", "/place") + "/" + PLACE_ID + "/home";
    placeRedirectsTo = loopback("localhost", "/restaurant");
  }

  private static void respond(HttpExchange exchange, String body) throws java.io.IOException {
    byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
    exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
    exchange.sendResponseHeaders(200, bytes.length);
    try (OutputStream out = exchange.getResponseBody()) {
      out.write(bytes);
    }
  }

  @AfterEach
  void stopServer() {
    server.stop(0);
  }

  private String loopback(String host, String path) {
    return "http://" + host + ":" + server.getAddress().getPort() + path;
  }

  private NaverUrlCrawler crawler(JsoupUrlCrawler fallback) {
    return new NaverUrlCrawler(
        new ObjectMapper(),
        fallback,
        "127.0.0.1",
        loopback("localhost", "/place"),
        "localhost,127.0.0.1");
  }

  private CrawlResult crawlShortLink() {
    return crawler(new JsoupUrlCrawler(new UrlSafetyValidator()))
        .crawl(loopback("127.0.0.1", "/short"));
  }

  // ------------------------------------------------------------------ 정상 경로

  @Test
  void itFollowsTheShortLinkThroughTheTypeRedirectAndMapsThePlace() {
    CrawlResult result = crawlShortLink();

    assertThat(result.title()).isEqualTo("몽탄");
    assertThat(result.source()).isEqualTo("naver.com");
    assertThat(result.thumbnail()).startsWith("https://search.pstatic.net/common/");

    // 🔴 **정확히 이 다섯 줄**이어야 한다. contains 로 두면 메뉴가 슬쩍 섞여도 안 잡힌다.
    assertThat(result.bodyText())
        .isEqualTo(
            """
            몽탄
            육류,고기요리
            서울 용산구 백범로99길 50
            한 번 먹으면 잊을 수 없는 맛
            단체 이용 가능, 무선 인터넷, 유아의자""");

    // 세 단계를 전부 거쳤다.
    assertThat(shortHits.get()).isOne();
    assertThat(placeHits.get()).isOne();
    assertThat(typeHits.get()).isOne();
  }

  @Test
  void aPlaceThatServesDirectlyNeedsNoTypeHop() {
    // 실측: 업종에 따라 /place/{id}/home 이 바로 200 을 준다(`남도낚시`). 그때도 같은 결과여야 한다.
    placeRedirectsToType = false;

    assertThat(crawlShortLink().title()).isEqualTo("몽탄");
    assertThat(typeHits.get()).isZero();
  }

  @Test
  void everyRequestCarriesAMobileUserAgent() {
    // 🔴 PC UA·UA 없음은 첫 요청부터 429 다(실측 2026-08-05). 이게 회귀하면 네이버만 조용히 전멸한다.
    crawlShortLink();

    assertThat(userAgents).hasSize(3).allSatisfy(ua -> assertThat(ua).contains("iPhone"));
  }

  @Test
  void theMenuNextToTheAnchorIsNotMistakenForThePlace() {
    // 픽스처에는 앵커 **앞**에 `"name":"삼각지 주차장"`(Parking), **뒤**에 `"name":"우대갈비 280g"`(Menu)이
    // 실제 페이지 순서 그대로 들어 있다. 앵커로 객체를 자르지 않으면 둘 중 하나를 집는다.
    CrawlResult result = crawlShortLink();

    assertThat(result.title()).isEqualTo("몽탄");
    assertThat(result.bodyText()).doesNotContain("우대갈비").doesNotContain("삼각지 주차장");
    assertThat(result.bodyText()).doesNotContain("주차장");
  }

  // ------------------------------------------------------------------ 실패·폴백 경로

  @Test
  void aPlaceThatDoesNotExistIsAFailure() {
    // 🔴 없는 장소도 **200** 이다(실측 340KB). 상태코드로 구분할 수 없어 제목 유무로 판정한다.
    placeHtml = "<html><head></head><body><div id=\"app\"></div></body></html>";

    assertThatThrownBy(this::crawlShortLink)
        .isInstanceOf(CrawlException.class)
        .hasMessage("장소를 불러올 수 없는 링크예요");
  }

  @Test
  void aShortLinkPointingOffNaverIsRefusedWithoutFetchingIt() {
    // 🔴 이 크롤러가 일반 크롤러의 "리다이렉트 미추종"을 우회하는 통로가 되면 안 된다.
    shortRedirectsTo = "http://evil.test/whatever";

    assertThatThrownBy(this::crawlShortLink)
        .isInstanceOf(CrawlException.class)
        .hasMessage("장소를 불러올 수 없는 링크예요");
    assertThat(placeHits.get()).isZero();
    assertThat(typeHits.get()).isZero();
  }

  @Test
  void theTypeRedirectIsHostCheckedToo() {
    // 🔴 두 번째 홉도 같은 방어선을 받아야 한다. 2026-08-05 리뷰가 이 줄의 검증을 빼는 변형으로
    // **테스트 159개가 전부 통과하는 것**을 보였다 — 그때 이 테스트가 없었다.
    placeRedirectsTo = "http://evil.test/restaurant/1/home";

    assertThatThrownBy(this::crawlShortLink)
        .isInstanceOf(CrawlException.class)
        .hasMessage("장소를 불러올 수 없는 링크예요");
    assertThat(typeHits.get()).isZero();
  }

  @Test
  void aShortLinkThatIsNotAPlaceGoesToTheGeneralCrawler() {
    // 사용자 확정(2026-08-05): 장소가 아닌 naver.me 는 펼쳐서 일반 크롤러에 넘긴다.
    // 그쪽 validateUrl 이 스킴·사설IP 를 다시 검증하므로 여기서 중복 검증하지 않는다.
    //
    // 🔴 **실제 블로그 주소 모양(두 조각 + 숫자)을 써야 한다.** 처음엔 `/blog/somebody/223`(세 조각)을
    // 썼는데, 그러면 `segments.get(1)="somebody"` 라 숫자 검증에서 우연히 걸러져 **호스트 검사가
    // 없어도 통과한다**. 2026-08-05 리뷰가 이 헛돎을 잡았다.
    // 호스트도 장소 호스트(localhost)가 아닌 곳(127.0.0.1)이어야 실제 상황과 같다.
    shortRedirectsTo = loopback("127.0.0.1", "/naver_diary/223456789012");
    RecordingJsoupUrlCrawler recording = new RecordingJsoupUrlCrawler();

    CrawlResult result = crawler(recording).crawl(loopback("127.0.0.1", "/short"));

    assertThat(recording.lastUrl).isEqualTo(shortRedirectsTo);
    assertThat(result.title()).isEqualTo("일반 크롤러가 처리했다");
    assertThat(placeHits.get()).isZero();
  }

  @Test
  void aTruncatedPageStillRegistersWithTheOgTitle() {
    // 페이지가 크기 상한에 잘리면 앵커 객체가 안 닫힌다. 그때 본문은 얇아지지만 **등록은 성공해야 한다** —
    // 조용히 실패하는 대신 제목만이라도 남긴다(구조 변경 시의 degrade 경로와 같다).
    placeHtml = placeHtml.substring(0, placeHtml.indexOf("\"roadAddress\""));

    CrawlResult result = crawlShortLink();

    assertThat(result.title()).isEqualTo("몽탄");
    assertThat(result.bodyText()).isEqualTo("몽탄");
  }

  /** {@code JsoupUrlCrawler} 는 루프백 주소를 SSRF 로 막으므로, 위임 여부만 기록해 확인한다. */
  private static final class RecordingJsoupUrlCrawler extends JsoupUrlCrawler {
    private String lastUrl;

    RecordingJsoupUrlCrawler() {
      super(new UrlSafetyValidator());
    }

    @Override
    public CrawlResult crawl(String url) {
      lastUrl = url;
      return new CrawlResult("일반 크롤러가 처리했다", "본문", null, "naver.com");
    }
  }
}
