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
import java.util.Optional;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * 🔴 <b>{@code crawl()} 전체를 돈다</b> — 부트스트랩 → GraphQL → 매핑, 그리고 <b>로그인 응답 시 재시도</b>까지.
 *
 * <p><b>왜 필요한가</b>(2026-08-05): 인스타가 다시 깨졌을 때 원인을 못 짚었다. {@code queryPost} 가 {@code
 * .execute().body()} 뿐이라 <b>200 이 아닌 응답도 그대로 JSON 파서에 넘겼고</b>, 사용자에겐 "게시물을 불러올 수 없는 링크예요"만, 로그엔
 * Jackson 예외만 남았다. 상태코드도 본문도 없었다. {@code InstagramUrlCrawlerTest} 는 픽스처를 매핑부에 직접 넣어서 이 경로를 한 번도 안
 * 밟았다 — 유튜브에서 하루를 날린 것과 같은 구조다.
 *
 * <p><b>인터넷을 타지 않는다</b> — 루프백에 JDK 내장 HTTP 서버를 띄우고 {@code modi.archive.instagram.base-url} 을 그쪽으로
 * 돌린다. 그 프로퍼티가 있는 이유가 이것이다.
 */
class InstagramUrlCrawlerResponseTest {

  private static final String SHORTCODE = "DZb-UAhz4Iq";

  /** 부트스트랩이 읽는 것 둘만 담은 페이지 — 실제 페이지의 그 두 조각과 같은 모양이다. */
  private static final String BOOTSTRAP_HTML =
      """
      <html><head><script>
      window.__d("LSD",[],{"token":"AdQCd4WbYxi5oHKQvofPlXtQGvo"});
      var cfg = {"csrf_token":"nb_0uqBX03AqH8WjKII5ZR"};
      </script></head><body></body></html>
      """;

  /** 성공 응답. 매핑부가 실제로 읽는 필드만 남겼다. */
  private static final String GRAPHQL_JSON =
      """
      {"data":{"xdt_api__v1__media__shortcode__web_info":{"items":[{
        "code":"DZb-UAhz4Iq",
        "user":{"username":"workout_plz"},
        "caption":{"text":"오늘의 기록\\n스쿼트 100kg"},
        "carousel_media":null,
        "image_versions2":{"candidates":[
          {"url":"https://scontent.cdninstagram.com/v/big.jpg"}]}
      }]}}}
      """;

  /** 인스타가 차단할 때 주는 것 — <b>200 인데 HTML</b>. 상태코드만 봐서는 못 잡는다. */
  private static final String LOGIN_HTML =
      "<!DOCTYPE html><html><head><title>Login • Instagram</title></head><body></body></html>";

  private HttpServer server;

  private final AtomicInteger bootstrapHits = new AtomicInteger();
  private final AtomicInteger graphqlHits = new AtomicInteger();

  /** GraphQL 이 몇 번째 호출까지 로그인 벽을 줄지. 0 이면 항상 성공. */
  private int loginWallsBeforeSuccess;

  /** 로그인 벽을 줄 때의 상태코드. 200(HTML) 과 403 둘 다 실측된 모양이다. */
  private int loginWallStatus = 200;

  /** 부트스트랩({@code GET /p/{code}/})이 줄 응답. 기본은 정상 페이지다. */
  private int bootstrapStatus = 200;

  private String bootstrapBody = BOOTSTRAP_HTML;

  /**
   * 차단됐을 때 {@code /p/} 가 주는 것 — 게시물 페이지가 아니라 challenge 다(운영 실측 610KB, {@code og:} 태그 0개). 요점은
   * <b>lsd 니들이 없다</b>는 것이다.
   */
  private static final String CHALLENGE_HTML =
      "<!DOCTYPE html><html><head><title>Instagram</title></head>"
          + "<body><div id=\"challenge\">Please wait</div></body></html>";

  @BeforeEach
  void startServer() throws Exception {
    server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);

    server.createContext(
        "/p/",
        exchange -> {
          bootstrapHits.incrementAndGet();
          respond(exchange, bootstrapStatus, bootstrapBody);
        });

    server.createContext(
        "/graphql/query/",
        exchange -> {
          int n = graphqlHits.incrementAndGet();
          if (n <= loginWallsBeforeSuccess) {
            respond(exchange, loginWallStatus, LOGIN_HTML);
          } else {
            respond(exchange, 200, GRAPHQL_JSON);
          }
        });

    server.start();
  }

  private static void respond(HttpExchange exchange, int status, String body)
      throws java.io.IOException {
    byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
    exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
    exchange.getResponseHeaders().add("Set-Cookie", "csrftoken=nb_0uqBX03AqH8WjKII5ZR; Path=/");
    exchange.sendResponseHeaders(status, bytes.length);
    try (OutputStream out = exchange.getResponseBody()) {
      out.write(bytes);
    }
  }

  @AfterEach
  void stopServer() {
    server.stop(0);
  }

  /** 쿨다운을 메모리로 흉내낸다 — Redis 없이 "막혔다/안 막혔다"만 재현하면 된다. */
  private static final class FakeCooldown implements CrawlBlockCooldown {
    private final java.util.Set<String> blocked = new java.util.HashSet<>();
    private final java.util.List<String> marked = new java.util.ArrayList<>();

    @Override
    public boolean isBlocked(String site) {
      return blocked.contains(site);
    }

    @Override
    public void markBlocked(String site) {
      marked.add(site);
      blocked.add(site);
    }
  }

  private final FakeCooldown cooldown = new FakeCooldown();

  private CrawlResult crawl() {
    String base =
        "http://"
            + InetAddress.getLoopbackAddress().getHostAddress()
            + ":"
            + server.getAddress().getPort();
    InstagramUrlCrawler crawler =
        new InstagramUrlCrawler(
            new ObjectMapper(), Optional.empty(), cooldown, "26713194205046842", base);
    return crawler.crawl("https://www.instagram.com/p/" + SHORTCODE + "/");
  }

  @Test
  void itBootstrapsThenQueriesAndMapsTheCaption() {
    CrawlResult result = crawl();

    assertThat(result.title()).isEqualTo("오늘의 기록");
    assertThat(result.bodyText()).contains("@workout_plz").contains("스쿼트 100kg");
    assertThat(result.source()).isEqualTo("instagram.com");
    assertThat(bootstrapHits.get()).isOne();
    assertThat(graphqlHits.get()).isOne();
  }

  @Test
  void aLoginWallIsRetriedOnceWithFreshTokens() {
    // 참조 문서의 처방: "re-bootstrap on the first execution error/login response".
    // 🔴 **부트스트랩도 다시 해야 한다** — 같은 토큰으로 다시 때리면 같은 답이 온다.
    loginWallsBeforeSuccess = 1;

    assertThat(crawl().title()).isEqualTo("오늘의 기록");
    assertThat(bootstrapHits.get()).isEqualTo(2);
    assertThat(graphqlHits.get()).isEqualTo(2);
  }

  @Test
  void aLoginWallWithA403IsRetriedTheSameWay() {
    // 로그인 벽은 200+HTML 로도, 403 으로도 온다(참조 문서). 둘 다 같은 처방이다.
    loginWallsBeforeSuccess = 1;
    loginWallStatus = 403;

    assertThat(crawl().title()).isEqualTo("오늘의 기록");
    assertThat(graphqlHits.get()).isEqualTo(2);
  }

  @Test
  void itGivesUpAfterOneRetryInsteadOfHammeringInstagram() {
    // 🔴 소프트 블록이면 두 번째도 실패한다. 더 때리면 블록을 키운다 — **정확히 2회**여야 한다.
    loginWallsBeforeSuccess = 99;

    // 문구가 "게시물을 불러올 수 없는 링크예요" 에서 바뀌었다 — 그건 **링크가 잘못됐다**는 뜻으로
    // 읽혀서 사용자가 다시 시도할 이유를 못 찾았다. 실제로는 잠시 막힌 것이고 10~20분이면 풀린다.
    assertThatThrownBy(this::crawl)
        .isInstanceOf(CrawlException.class)
        .hasMessage("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");
    assertThat(graphqlHits.get()).isEqualTo(2);
    assertThat(bootstrapHits.get()).isEqualTo(2);
  }

  @Test
  void givingUpMarksTheCooldownSoTheNextShareDoesNotHammerInstagram() {
    // 🔴 여기가 2026-08-05 에 빠져 있던 것이다. 포기는 했지만 **기억하지 않아서**, 다음 공유가
    // 오면 똑같이 4번 때렸다. 실패 11건이 2~16분 간격으로 뭉쳐 있었고 그 호출이 전부 헛수고였다.
    loginWallsBeforeSuccess = 99;

    assertThatThrownBy(this::crawl).isInstanceOf(CrawlException.class);

    assertThat(cooldown.marked).containsExactly("instagram");
  }

  @Test
  void whileTheCooldownIsOnItDoesNotTouchInstagramAtAll() {
    // 🔴 **호출 0회여야 한다.** 부트스트랩만 해봐도 안 된다 — 차단 상태에서는 그것도 challenge
    // 페이지를 받고(실측: /p/ 페이지가 610KB 챌린지였다), 데이터센터 IP 의 호출이 누적되면
    // 차단이 길어진다. "덜 때린다"가 아니라 "안 때린다"가 이 커밋의 요점이다.
    cooldown.markBlocked("instagram");

    assertThatThrownBy(this::crawl)
        .isInstanceOf(CrawlException.class)
        .hasMessage("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");

    assertThat(bootstrapHits.get()).isZero();
    assertThat(graphqlHits.get()).isZero();
  }

  // ------------------------------------------------ 부트스트랩 단계의 차단(2026-08-06 리뷰 P1)

  @Test
  void aChallengePageOnBootstrapIsRetryableAndMarksTheCooldown() {
    // 🔴 이것이 2026-08-06 리뷰가 잡은 구멍이다. 차단 중에는 /p/ 페이지 자체가 challenge 라
    // lsd 니들이 없는데(운영 실측 610KB), 그 갈래가 **영구 실패**였다 — 사용자에게 곧장
    // "분석 실패"가 뜨고 쿨다운도 안 걸려 다음 공유가 또 때렸다. 로그 문구는 예전부터
    // "차단됐을 수 있다"라고 말하고 있었는데 예외만 그 말과 달랐다.
    bootstrapBody = CHALLENGE_HTML;

    assertThatThrownBy(this::crawl)
        .isInstanceOf(CrawlException.class)
        .hasMessage("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요")
        .matches(e -> ((CrawlException) e).isRetryable(), "다시 해볼 만한 실패여야 한다");

    assertThat(cooldown.marked).containsExactly("instagram");
    // 토큰을 못 땄으면 GraphQL 은 로그인 페이지만 준다 — 때려볼 이유가 없다.
    assertThat(graphqlHits.get()).isZero();
  }

  @Test
  void aRedirectOnBootstrapIsRetryableAndMarksTheCooldown() {
    // 참조 문서(test.md)가 적은 소프트 블록 증상이 정확히 "302/403 to login even with valid
    // tokens" 다. 비공개·삭제 게시물은 여기로 오지 않는다 — 그쪽은 부트스트랩을 통과한 뒤
    // GraphQL 의 빈 items 로 걸러진다(바로 위 두 테스트가 그것을 고정한다).
    bootstrapStatus = 302;

    assertThatThrownBy(this::crawl)
        .isInstanceOf(CrawlException.class)
        .matches(e -> ((CrawlException) e).isRetryable(), "다시 해볼 만한 실패여야 한다");

    assertThat(cooldown.marked).containsExactly("instagram");
    assertThat(graphqlHits.get()).isZero();
  }

  @Test
  void aBlockedBootstrapHitsInstagramOnlyOnce() {
    // 부트스트랩 실패는 로그인 벽과 달리 재시도 루프를 타지 않는다 — 여기서 2번 때리면
    // 차단 중에 호출을 배로 늘려 회복을 늦춘다.
    bootstrapBody = CHALLENGE_HTML;

    assertThatThrownBy(this::crawl).isInstanceOf(CrawlException.class);

    assertThat(bootstrapHits.get()).isEqualTo(1);
  }

  @Test
  void aSuccessfulCrawlNeverMarksTheCooldown() {
    // 성공했는데 쿨다운이 걸리면 멀쩡한 인스타를 10분 동안 안 부른다.
    crawl();

    assertThat(cooldown.marked).isEmpty();
  }

  @Test
  void aPrivateOrDeletedPostDoesNotMarkTheCooldown() {
    // 🔴 비공개·삭제는 **우리가 막힌 게 아니다.** 그걸로 쿨다운을 걸면 남의 글 하나 때문에
    // 방 전체의 인스타 등록이 10분 멈춘다.
    server.removeContext("/graphql/query/");
    server.createContext(
        "/graphql/query/",
        exchange -> {
          graphqlHits.incrementAndGet();
          respond(
              exchange,
              200,
              "{\"data\":{\"xdt_api__v1__media__shortcode__web_info\":{\"items\":[]}}}");
        });

    assertThatThrownBy(this::crawl).isInstanceOf(CrawlException.class);

    assertThat(cooldown.marked).isEmpty();
  }

  @Test
  void aPrivateOrDeletedPostIsNotRetried() {
    // 🔴 빈 items 는 비공개·삭제·doc_id 만료다 — 토큰을 새로 따도 결과가 같다.
    // 이걸 재시도하면 인스타를 두 배로 때리면서 얻는 게 없다.
    server.removeContext("/graphql/query/");
    server.createContext(
        "/graphql/query/",
        exchange -> {
          graphqlHits.incrementAndGet();
          respond(
              exchange,
              200,
              "{\"data\":{\"xdt_api__v1__media__shortcode__web_info\":{\"items\":[]}}}");
        });

    assertThatThrownBy(this::crawl)
        .isInstanceOf(CrawlException.class)
        .hasMessage("공개된 게시물만 등록할 수 있어요");
    assertThat(graphqlHits.get()).isOne();
  }
}
