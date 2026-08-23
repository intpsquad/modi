package com.nomara.modi.server.domain.archive.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpHeaders;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.regex.Pattern;
import org.jsoup.Connection;
import org.jsoup.Jsoup;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * 인스타그램 공개 게시물 전용 크롤러. 캡션을 본문으로, 첫 이미지를 썸네일로 가져온다.
 *
 * <p>일반 크롤러로는 200이 오는데 본문이 JS 껍데기라 {@code "본문을 찾을 수 없는 링크예요"}로 떨어진다. 인증 없이 남은 방법은 <b>2단계
 * 부트스트랩</b>뿐이다(2026-08-03 실측 확인):
 *
 * <pre>
 *   1) GET  /p/{shortcode}/       → lsd 토큰 + csrf 토큰을 **매번 새로** 딴다
 *   2) POST /graphql/query/       → 그 토큰으로 persisted query 를 부른다
 * </pre>
 *
 * <p><b>토큰을 하드코딩하면 안 된다</b> — 굳은 값으로는 403 로그인 페이지가 온다. 세션마다 새로 따야 200이 온다.
 *
 * <p>⚠️ csrf 토큰은 {@code Set-Cookie} <b>와</b> 페이지 본문 두 곳에서 찾는다 — 인스타가 쿠키를 이미 들고 온 요청에는 {@code
 * Set-Cookie} 를 안 주기 때문이다. 이유와 실측은 {@link #csrfToken}.
 *
 * <p>⚠️ <b>참고 문서(InstaFix 계열)의 헤더만으로는 부족했다.</b> 문서대로 {@code X-IG-App-ID}·{@code X-FB-LSD}·{@code
 * X-CSRFToken}만 보내면 JSON 이 아니라 HTML 이 온다. {@code Sec-Fetch-Site/Mode/Dest}·{@code Accept}·{@code
 * X-Requested-With}를 <b>한꺼번에</b> 더하니 200 JSON 이 왔다 — <b>개별 헤더가 각각 필수인지는 확인하지 않았다</b>(하나씩 빼보는 이분 탐색을
 * 안 했다). 처음에 이걸 몰라 {@code doc_id}가 만료된 줄 알았다.
 *
 * <p><b>리다이렉트를 따라가지 않는다.</b> 같은 문서는 "릴스는 {@code /p/} → {@code /reel/} 로 리다이렉트된다"고 적어뒀는데 <b>공개 게시물 한
 * 건을 재봤을 때는</b> 둘 다 200 직행이었다. 덕분에 {@code JsoupUrlCrawler}의 SSRF 방어(추종 금지)를 그대로 지킨다. 이 관측이 틀려도
 * <b>안전 쪽으로 깨진다</b> — 3xx 가 오면 {@code bootstrap} 이 "게시물을 불러올 수 없는 링크예요"로 끝낸다(기능이 안 될 뿐 위험하지 않다).
 *
 * <p>⚠️ <b>이 크롤러는 깨지기 쉽다.</b> {@code doc_id}는 몇 주~몇 달마다 바뀌고, 데이터센터 IP 의 비인증 트래픽은 soft-block 된다. 깨지면
 * {@code CrawlException} → 기존 {@code FAILED} 경로다(2026-08-03 사용자 확정 — 자료·링크는 남고 AI 입력으로만 안 쓰인다). 갱신
 * 절차는 {@code specs/OPEN.md}.
 *
 * <p>🔴 <b>{@code www.instagram.com} 요청 두 개는 {@code java.net.http.HttpClient}(HTTP/2)로 보낸다 — jsoup
 * 이 아니다</b> (2026-08-23, #62). 운영 서버(오라클 데이터센터 IP)에서 같은 헤더·쿠키·본문을 보내도 jsoup 이 쓰는 {@code
 * HttpURLConnection} 은 GraphQL 에서 <b>200 + 로그인 HTML</b> 을 받았고, {@code HttpClient}/HTTP2 는 <b>JSON +
 * items</b> 를 받았다(curl 도 JSON). 즉 인스타는 데이터센터 IP 에서 <b>접속 지문</b>까지 본다. 집 IP 에서는 그 검사가 없어 개발 중엔 재현되지
 * 않았다. 썸네일(CDN)은 jsoup 그대로다 — 그쪽 실패는 "썸네일 없이 등록"으로 삼켜진다({@link #storeThumbnail}).
 */
@Component
public class InstagramUrlCrawler implements SiteUrlCrawler {

  private static final Logger log = LoggerFactory.getLogger(InstagramUrlCrawler.class);

  private static final int TIMEOUT_MILLIS = 5000;

  /** 썸네일은 본론이 아니다 — 캡션보다 짧게 끊는다. 실패하면 썸네일만 포기한다. */
  private static final int THUMBNAIL_TIMEOUT_MILLIS = 3000;

  private static final int MAX_BODY_SIZE = 2_000_000;

  /** 로그에 남길 응답 본문 앞부분의 상한. 로그인 HTML 은 수십 KB 라 그대로 찍으면 로그가 잠긴다. */
  private static final int MAX_LOGGED_BODY = 500;

  private static final int MAX_IMAGE_SIZE = 5_000_000;

  private static final String USER_AGENT =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)"
          + " Chrome/125.0.0.0 Safari/537.36";

  private static final List<String> HOSTS = List.of("instagram.com", "www.instagram.com");
  private static final List<String> POST_PREFIXES = List.of("/p/", "/reel/", "/reels/", "/tv/");

  /** 썸네일을 받아올 수 있는 호스트. 실측 응답은 {@code scontent-*.cdninstagram.com} 을 준다. */
  private static final List<String> CDN_SUFFIXES =
      List.of("cdninstagram.com", "fbcdn.net", "instagram.com");

  /**
   * 게시물 shortcode. base62 + {@code -_} 이고 보통 11자다.
   *
   * <p>⚠️ <b>여기가 이 클래스의 SSRF 방어선이다</b> — 사용자 입력으로 요청 URL 을 조립하므로, 느슨하면 서버가 임의 주소를 부르게 된다.
   */
  private static final Pattern SHORTCODE = Pattern.compile("[A-Za-z0-9_-]{5,32}");

  /** 인스타 웹 클라이언트의 공개 앱 id. 안 바뀐다. */
  private static final String APP_ID = "936619743392459";

  private static final String FRIENDLY_NAME = "PolarisPostRootQuery";
  private static final String ROOT_FIELD = "xdt_api__v1__media__shortcode__web_info";

  /** 페이지 HTML 안의 lsd 토큰 자리. */
  private static final String LSD_NEEDLE = "\"LSD\",[],{\"token\":\"";

  /** 페이지 HTML 안의 csrf 토큰 자리 — {@code Set-Cookie} 가 안 올 때의 폴백({@link #csrfToken}). */
  private static final String CSRF_NEEDLE = "\"csrf_token\":\"";

  /** 쿨다운 키에 쓰는 사이트 이름. */
  private static final String SITE = "instagram";

  private final ObjectMapper objectMapper;
  private final Optional<ObjectStorage> objectStorage;
  private final CrawlBlockCooldown cooldown;
  private final String docId;
  private final String baseUrl;

  /**
   * www 요청 전용. 빈 하나에 하나 — 커넥션을 재사용한다.
   *
   * <p>{@code HTTP_2} 는 운영 서버에서 <b>실측으로 통과한 조합</b>이다(클래스 주석). {@code Redirect.NEVER} 는 지금까지와 같다 —
   * 3xx 는 차단으로 판정한다({@link #bootstrap}). 연결 타임아웃만 여기 두고, <b>총 시간</b>은 {@link #send} 가 잰다.
   */
  private final HttpClient http =
      HttpClient.newBuilder()
          .version(HttpClient.Version.HTTP_2)
          .followRedirects(HttpClient.Redirect.NEVER)
          .connectTimeout(Duration.ofMillis(TIMEOUT_MILLIS))
          .build();

  /**
   * {@link #send} 의 본문 읽기(블로킹, 최대 {@code TIMEOUT_MILLIS})를 돌리는 자리. <b>{@code thenApply} 로 두면 JDK 가
   * {@code ForkJoinPool.commonPool()} 에서 돌린다</b>(리뷰 2026-08-23 P2-1) — 4 OCPU 서버에서 공용 풀 워커는 3개라, 크롤
   * 스레드 4개가 동시에 본문을 읽으면 다른 공용 풀 사용자와 경합한다. 가상 스레드는 블로킹이 싸고 개수 제한이 없다.
   */
  private final ExecutorService bodyReaders = Executors.newVirtualThreadPerTaskExecutor();

  /**
   * {@code base-url} 을 프로퍼티로 뺀 이유는 <b>테스트가 루프백 서버를 가리켜 {@code crawl()} 전체를 돌기 위해서다</b> — 특히 <b>로그인
   * 응답 → 재부트스트랩 재시도</b>는 이음매 없이는 검증할 방법이 없다. {@code YouTubeUrlCrawler.api-url}· {@code
   * NaverUrlCrawler.place-url} 과 같은 패턴이다. 운영에서 바꿀 일이 없다.
   */
  public InstagramUrlCrawler(
      ObjectMapper objectMapper,
      Optional<ObjectStorage> objectStorage,
      CrawlBlockCooldown cooldown,
      @Value("${modi.archive.instagram.doc-id}") String docId,
      @Value("${modi.archive.instagram.base-url:https://www.instagram.com}") String baseUrl) {
    this.objectMapper = objectMapper;
    this.objectStorage = objectStorage;
    this.cooldown = cooldown;
    this.docId = docId;
    this.baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
  }

  @Override
  public boolean supports(URI uri) {
    String host = uri.getHost();
    if (host == null || !HOSTS.contains(host.toLowerCase(Locale.ROOT))) {
      return false;
    }
    String path = uri.getPath() == null ? "" : uri.getPath();
    // 프로필(`/{username}/`)·태그 페이지는 일반 크롤러로 보낸다 — 게시물만 맡는다.
    return POST_PREFIXES.stream().anyMatch(path::startsWith);
  }

  /**
   * 🔴 <b>로그인 응답을 받으면 토큰을 새로 따서 <u>한 번만</u> 다시 시도한다.</b>
   *
   * <p>2026-08-05 실측: 부트스트랩은 통과했는데(lsd·csrf 정상, 경고 없음) GraphQL 만 HTML 을 받아 {@code
   * JsonParseException: Unexpected character ('<')} 로 죽었다. <b>같은 순간 같은 머신에서 curl 로는 200 · 129,627
   * bytes 가 왔다</b> — 쿠키 조합을 둘 다(csrftoken 만 / 부트스트랩 쿠키 전부) 재봤지만 차이가 없었다.
   *
   * <p>참조 문서(`Instagram Public Post Scraping — Working Method`)가 이 증상을 그대로 적어뒀다: <i>"Heavy
   * unauthenticated traffic from one IP eventually gets soft-blocked (302/403 to login <b>even with
   * valid tokens</b>)"</i>, 그리고 처방은 <i>"re-bootstrap on the first execution error/login
   * response"</i> 다.
   *
   * <p>⚠️ <b>재시도는 한 번뿐이다.</b> 소프트 블록이면 두 번째도 실패할 텐데, 거기에 더 때리면 블록을 키운다. 같은 문서가 권하는 캐시·singleflight
   * 는 범위가 커서 {@code specs/OPEN.md} 로 넘겼다.
   *
   * <p>🔴 <b>이 재시도의 근거는 약하다 — 다음 실패 로그를 보고 다시 판단할 것</b>(2026-08-05 리뷰 P2-3). 참조 문서의 저 문장은 <b>부트스트랩
   * 하나를 여러 GraphQL 호출에 재사용할 때</b>의 이야기인데 우리는 크롤링마다 새로 부트스트랩한다 — 즉 여기서는 "그냥 한 번 더 해본다" 이상이 아니고, 대신
   * 소프트 블록 상황에서 <b>인스타 요청이 2배(부트스트랩 2 + GraphQL 2)</b>가 된다. 실제로 2026-08-05 재발 때 <b>이 코드는 발동조차 하지
   * 않았고</b>(서버 재시작으로 복구) 효과를 관측한 적이 없다. 위 {@link #readGraphqlBody} 가 남기는 상태코드·쿠키 이름이 쌓이면 <b>지우는 쪽도
   * 정당한 선택</b>이다.
   */
  @Override
  public CrawlResult crawl(String url) {
    String shortcode = extractShortcode(URI.create(url));
    String postUrl = baseUrl + "/p/" + shortcode + "/";

    // 🔴 **쿨다운 중이면 요청을 하나도 하지 않는다**(2026-08-05). 부트스트랩만 해보는 것도 안 된다 —
    // 차단 상태에서는 `/p/` 페이지도 challenge 를 주고(실측 610KB), 데이터센터 IP 의 호출이 누적되면
    // 차단이 길어진다. 즉 때려보는 것 자체가 회복을 늦춘다.
    if (cooldown.isBlocked(SITE)) {
      log.info("인스타 쿨다운 중이라 호출하지 않는다: shortcode={}", shortcode);
      // notAttempted 다 — 요청을 하나도 안 보냈으므로 재시도 횟수를 태우면 안 된다(리뷰 P2).
      // 차단이 길면 밀려 있던 자료들이 각자 여기로 떨어지는데, 그게 상한을 소진해 버리면
      // 한 번도 진짜로 시도해 보지 못한 채 "분석 실패"가 된다.
      throw CrawlException.notAttempted("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");
    }

    try {
      return toCrawlResult(queryPost(shortcode, postUrl, bootstrap(postUrl)), shortcode);
    } catch (LoginWallException e) {
      log.warn("인스타가 로그인 응답을 줬다 — 토큰을 새로 따서 한 번만 다시 시도한다: shortcode={}", shortcode);
    }
    try {
      return toCrawlResult(queryPost(shortcode, postUrl, bootstrap(postUrl)), shortcode);
    } catch (LoginWallException e) {
      // 두 번째도 로그인 벽이면 토큰 문제가 아니라 IP 평판이다. 여기서 멈추고 **기억한다** —
      // 기억하지 않아서 다음 공유가 똑같이 4번 때렸다(실패 11건이 2~16분 간격으로 뭉쳐 있었다).
      // 자세한 값(상태코드·쿠키 이름·본문)은 바로 위 warn 두 줄에 있다.
      log.error("인스타 재시도도 로그인 응답이다 — IP 소프트 블록일 수 있다: shortcode={} {}", shortcode, e.getMessage());
      cooldown.markBlocked(SITE);
      throw CrawlException.retryable("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요", e);
    }
  }

  /**
   * 차단으로 판정하고 멈춘다 — 로그를 남기고, 쿨다운을 걸고, <b>다시 해볼 만한</b> 실패를 던진다(2026-08-06 리뷰 P1).
   *
   * <p>돌아오는 값은 없다(항상 던진다). 반환 타입이 {@link Bootstrap} 인 것은 호출부가 {@code return blocked(...)} 로 쓸 수 있게
   * 하기 위해서다 — 그 자리에서 흐름이 끝난다는 것이 눈에 보인다.
   *
   * <p><b>왜 한 번의 신호로 쿨다운을 거는가.</b> 로그인 벽 쪽은 두 번 맞아야 걸지만(토큰 문제와 IP 문제를 가르려고) 부트스트랩 단계는 가를 것이 없다 — 정상
   * 페이지면 lsd 니들이 있고 200 이다. 그리고 여기서 안 걸면 밀려 있던 공유들이 각자 한 번씩 더 때려서 <b>차단 회복을 늦춘다</b>(위 {@code
   * crawl()} 주석의 근거와 같다).
   */
  private Bootstrap blocked(String logFormat, Object... logArgs) {
    log.warn(logFormat, logArgs);
    cooldown.markBlocked(SITE);
    throw CrawlException.retryable("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");
  }

  /**
   * "토큰이 신선하면 통과할 수도 있는 실패" 전용 — {@link #crawl} 이 이것만 재시도한다.
   *
   * <p>{@code CrawlException} 과 구분하는 이유: 비공개 게시물이나 잘못된 shortcode 까지 재시도하면 인스타를 두 배로 때리면서 결과는 같다.
   */
  private static final class LoginWallException extends RuntimeException {
    LoginWallException(String message) {
      super(message);
    }
  }

  /**
   * shortcode 를 뽑는다. 쿼리 파라미터가 붙어 와도 된다 — 인스타 앱의 공유 버튼이 {@code ?igsh=...} 를 붙인다.
   *
   * <p><b>안 맞으면 던진다 — 조립할 URL 을 추측하지 않는다.</b>
   */
  String extractShortcode(URI uri) {
    String path = uri.getPath() == null ? "" : uri.getPath();
    String prefix =
        POST_PREFIXES.stream()
            .filter(path::startsWith)
            .findFirst()
            .orElseThrow(() -> new CrawlException("게시물 주소를 알아볼 수 없어요"));

    String candidate = path.substring(prefix.length());
    int slash = candidate.indexOf('/');
    if (slash >= 0) {
      candidate = candidate.substring(0, slash);
    }
    if (!SHORTCODE.matcher(candidate).matches()) {
      throw new CrawlException("게시물 주소를 알아볼 수 없어요");
    }
    return candidate;
  }

  /** 1단계 — 페이지에서 <b>새</b> lsd 토큰과 csrftoken 쿠키를 딴다. 굳은 값으로는 403 로그인 페이지가 온다. */
  private Bootstrap bootstrap(String postUrl) {
    HttpRequest request =
        HttpRequest.newBuilder(URI.create(postUrl))
            .header("User-Agent", USER_AGENT)
            // jsoup 이 기본으로 얹던 값 그대로 — HttpClient 는 Accept 를 알아서 붙이지 않는다.
            .header("Accept", "text/html, application/xhtml+xml, application/xml;q=0.9, */*;q=0.8")
            .header("Accept-Language", "en-US,en;q=0.9")
            .GET()
            .build();
    Fetched response;
    try {
      // 연결 실패·타임아웃·본문 중간 끊김이 전부 여기로 온다 — 예전엔 execute() 와 body() 를 따로 감쌌다.
      response = send(request, MAX_BODY_SIZE);
    } catch (Exception e) {
      log.warn("인스타 게시물 페이지를 불러오지 못했다: {}", postUrl, e);
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }
    if (response.status() >= 300) {
      // 🔴 **이것이 소프트 블록의 모양이다**(2026-08-06 리뷰 P1). 참조 문서(test.md)가 적은 차단 증상이
      // 정확히 "302/403 to login even with valid tokens" 이고, 위 주석대로 차단 중에는 /p/ 페이지도
      // challenge 를 준다(실측 610KB). 비공개·삭제 게시물은 여기로 오지 않는다 — 그쪽은 부트스트랩을
      // 통과한 뒤 GraphQL 의 빈 items 로 걸러진다("공개된 게시물만 등록할 수 있어요").
      return blocked("인스타 게시물 페이지가 리다이렉트/오류를 줬다(status={}) — 차단으로 본다", response.status());
    }

    // 본문은 `send()` 가 이미 다 읽어 String 으로 들고 있다 — 예전 jsoup 의 "본문 재읽기 함정"도,
    // 본문 읽기 중 소켓이 끊겨 `UncheckedIOException` 이 새던 구멍(2026-08-04 리뷰 P1-2)도
    // 위 try 하나가 다 덮는다.
    String html = response.body();
    Map<String, String> cookies = setCookies(response.headers());
    String lsd = between(html, LSD_NEEDLE, "\"");
    String csrf = csrfToken(cookies.get("csrftoken"), html);
    if (lsd.isBlank() || csrf.isBlank()) {
      // 둘 중 하나라도 비면 GraphQL 은 로그인 페이지만 돌려준다 — 여기서 끊는 편이 낫다.
      //
      // 🔴 **여기도 차단이다**(2026-08-06 리뷰 P1). 정상 /p/ 페이지에는 lsd 니들이 늘 있고, 없다는 것은
      // 받은 것이 게시물 페이지가 아니라는 뜻이다(challenge HTML). 이 로그가 예전부터 "차단됐을 수
      // 있다"고 말하면서 정작 예외는 영구 실패였다.
      return blocked("인스타 토큰을 못 땄다(lsd={}, csrf={}) — 차단으로 본다", !lsd.isBlank(), !csrf.isBlank());
    }
    return new Bootstrap(lsd, csrf, graphqlCookies(cookies, csrf));
  }

  /**
   * 응답의 {@code Set-Cookie} 들에서 {@code 이름=값} 만 뗀다(속성 {@code Path}·{@code Secure} 등은 버린다). 순서는 응답 순서,
   * 같은 이름이 두 번 오면 뒤가 이긴다 — jsoup 의 {@code response.cookies()} 와 같은 의미다. <b>빈 값도 그대로 넣는다</b>({@code
   * csrftoken=} 처럼) — {@link #graphqlCookies} 의 {@code put} 논의가 그 경우를 다룬다.
   */
  static Map<String, String> setCookies(HttpHeaders headers) {
    Map<String, String> cookies = new LinkedHashMap<>();
    for (String setCookie : headers.allValues("Set-Cookie")) {
      String pair = setCookie.split(";", 2)[0];
      int eq = pair.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      cookies.put(pair.substring(0, eq).trim(), pair.substring(eq + 1).trim());
    }
    return cookies;
  }

  /**
   * GraphQL 요청에 실을 쿠키. 응답 쿠키를 그대로 가져오되 {@code csrftoken} <b>은 우리가 쓸 값으로 덮는다.</b>
   *
   * <p>🔴 <b>{@code put} 이다 — {@code putIfAbsent} 가 아니다.</b> {@code Set-Cookie: csrftoken=}(빈 값.
   * 서버가 쿠키를 지울 때 보내는 흔한 모양)이 오면 jsoup 은 <b>키를 빈 문자열로 맵에 넣는다.</b> 그러면 {@link #csrfToken} 은 본문 폴백으로
   * 넘어가 페이지 토큰을 쓰는데 {@code putIfAbsent} 는 이미 있는 빈 값을 안 덮어, 쿠키는 {@code csrftoken=} · 헤더 {@code
   * X-CSRFToken} 은 페이지 토큰으로 <b>어긋난 채</b> 나간다 → 인스타가 로그인 HTML 을 준다(2026-08-04 리뷰 P1-1, 루프백 서버로 재현).
   *
   * <p>{@code csrfToken()} 이 이미 <b>쿠키를 우선</b>하므로 정상일 때 {@code put} 은 같은 값 덮어쓰기라 무해하다 — 두 곳의 우선순위를
   * 하나로 맞추는 것이다.
   *
   * <p>따로 뺀 이유는 <b>테스트가 이걸 직접 보게</b> 하려는 것이다({@code bootstrap} 은 네트워크를 탄다).
   */
  static Map<String, String> graphqlCookies(Map<String, String> responseCookies, String csrf) {
    Map<String, String> cookies = new LinkedHashMap<>(responseCookies);
    cookies.put("csrftoken", csrf);
    return cookies;
  }

  /**
   * csrftoken 을 찾는다 — {@code Set-Cookie} 우선, 없으면 <b>페이지 본문</b>. 둘 다 없으면 빈 문자열.
   *
   * <p>🔴 <b>{@code Set-Cookie} 만 보면 크롤러가 "이 JVM 이 인스타와 처음 대화할 때만" 동작한다.</b> 인스타는 쿠키를 이미 들고 온 요청에는
   * 토큰을 <b>다시 주지 않는다</b>(2026-08-04 실측):
   *
   * <pre>
   *   1차 (쿠키 없이 요청)      → Set-Cookie: csrftoken ✅ , Set-Cookie: mid
   *   2차 (그 쿠키를 달고 요청)  → Set-Cookie 없음        ❌
   * </pre>
   *
   * <p>{@code response.cookie(..)} 는 <b>그 응답의 Set-Cookie 만</b> 본다. 그래서 요청에 쿠키가 실려 나가는 순간부터 모든 인스타
   * 크롤링이 "게시물을 불러올 수 없는 링크예요"로 떨어진다. 20시간 떠 있던 개발 서버에서 실제로 그 증상이 났고(인스타 3연속 실패, 재시작하니 복구) <b>쿠키를
   * 붙들고 있던 주체는 아직 못 짚었다</b> — jsoup 자체는 요청 간 쿠키를 나르지 않는다(같은 JVM 12연속 성공). 미결 항목은 {@code
   * specs/OPEN.md}.
   *
   * <p><b>본문 값은 쿠키 값과 같다</b> — 실측으로 두 값이 문자 단위로 일치했다({@code M_OyA-dINujOnx9WtuXoz1}). 그래서 폴백이 성립하고,
   * 원인을 못 짚어도 기능은 쿠키 상태와 무관해진다.
   */
  static String csrfToken(String setCookieValue, String pageHtml) {
    if (setCookieValue != null && !setCookieValue.isBlank()) {
      return setCookieValue;
    }
    return between(pageHtml, CSRF_NEEDLE, "\"");
  }

  /**
   * 2단계 — persisted query. <b>헤더 한 벌이 전부 필요하다</b>(클래스 주석 참고).
   *
   * <p>🔴 <b>상태코드와 응답 모양을 남긴다</b>(2026-08-05). 이 메서드는 원래 {@code .execute().body()} 뿐이라 <b>200 이 아닌
   * 응답도 그대로 JSON 파서에 넘겼다</b> — 인스타가 로그인 HTML 을 주면 사용자에겐 "게시물을 불러올 수 없는 링크예요"만 보이고 <b>로그에는 상태코드도 본문도
   * 없었다.</b> 어제 유튜브에서 EC2 에 SSH 로 들어가 {@code curl} 을 쳐야 했던 것과 같은 사각지대다({@code YouTubeUrlCrawler}).
   * {@code bootstrap()} 은 처음부터 확인하고 있었는데 여기만 빠져 있었다.
   */
  private String queryPost(String shortcode, String postUrl, Bootstrap bootstrap) {
    String variables =
        "{\"shortcode\":\"%s\",\"fetch_tagged_user_count\":null,\"hoisted_comment_id\":null,"
                .formatted(shortcode)
            + "\"hoisted_reply_id\":null,"
            + "\"__relay_internal__pv__PolarisAIGMMediaWebLabelEnabledrelayprovider\":false}";
    // 헤더 순서: `HttpClient` 는 우리가 얹은 순서와 무관하게 **대소문자 무시 알파벳순**으로 보낸다
    // (`HttpRequest.Builder` 가 TreeMap 이다 — 리뷰 2026-08-23 실측). 즉 기동마다 달라지던 jsoup
    // 시절의 결함(2026-08-05, `graphqlHeaders` 주석)은 스택 교체로 사라졌고, 운영 서버는 이 알파벳
    // 순서로 통과했다. `graphqlHeaders` 의 LinkedHashMap 순서는 이제 로그의 이름 목록에만 남는다.
    HttpRequest.Builder builder =
        HttpRequest.newBuilder(URI.create(baseUrl + "/graphql/query/"))
            .header("User-Agent", USER_AGENT)
            .header("Cookie", cookieHeader(bootstrap.cookies()));
    graphqlHeaders(bootstrap, postUrl).forEach(builder::header);
    // `; charset=UTF-8` 꼬리 없음 — 운영 서버에서 실측으로 통과한 모양 그대로다(브라우저도 이렇게 보낸다).
    builder.header("Content-Type", "application/x-www-form-urlencoded");
    String form =
        formEncode(
            List.of(
                Map.entry("lsd", bootstrap.lsd()),
                Map.entry("doc_id", docId),
                Map.entry("fb_api_req_friendly_name", FRIENDLY_NAME),
                Map.entry("server_timestamps", "true"),
                Map.entry("variables", variables)));
    HttpRequest request = builder.POST(HttpRequest.BodyPublishers.ofString(form)).build();

    Fetched response;
    try {
      response = send(request, MAX_BODY_SIZE);
    } catch (Exception e) {
      log.warn("인스타 GraphQL 호출 실패: shortcode={}", shortcode, e);
      // 상태코드는 예외가 아니라 값으로 온다 — 여기 오는 것은 순수 네트워크 오류다(연결 실패·타임아웃·
      // 본문 중간 끊김). 부트스트랩의 같은 실패와 성격이 정확히 같다.
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }
    return readGraphqlBody(
        response, shortcode, bootstrap.cookies().keySet(), request.headers().map().keySet());
  }

  /** {@code k=v; k2=v2} — 브라우저가 보내는 모양. jsoup 의 {@code .cookies(map)} 이 만들던 것과 같다. */
  static String cookieHeader(Map<String, String> cookies) {
    StringBuilder sb = new StringBuilder();
    for (Map.Entry<String, String> e : cookies.entrySet()) {
      if (sb.length() > 0) {
        sb.append("; ");
      }
      sb.append(e.getKey()).append('=').append(e.getValue());
    }
    return sb.toString();
  }

  /**
   * {@code application/x-www-form-urlencoded} 본문. jsoup 의 {@code .data()} 도 같은 {@code URLEncoder} 로
   * 만들었다.
   */
  static String formEncode(List<Map.Entry<String, String>> fields) {
    StringBuilder sb = new StringBuilder();
    for (Map.Entry<String, String> f : fields) {
      if (sb.length() > 0) {
        sb.append('&');
      }
      sb.append(URLEncoder.encode(f.getKey(), StandardCharsets.UTF_8))
          .append('=')
          .append(URLEncoder.encode(f.getValue(), StandardCharsets.UTF_8));
    }
    return sb.toString();
  }

  /** {@link #send} 가 돌려주는 것 — 본문은 이미 다 읽어 String 으로 들고 있다. */
  record Fetched(int status, HttpHeaders headers, String body) {}

  /**
   * 요청 하나를 보내고 본문까지 읽는다. <b>{@code TIMEOUT_MILLIS} 는 연결·헤더·본문을 합친 총 시간이다.</b>
   *
   * <p>jsoup 의 {@code timeout()} 이 총 시간이었으므로 그 성질을 지킨다. {@code HttpRequest.timeout()} 은 <b>헤더가 올
   * 때까지만</b> 재서, 그것만 쓰면 헤더를 주고 본문을 붙잡는 상대에게 무한정 잡힌다({@code specs/OPEN.md} 의 RestTemplate 실측 30초와 같은
   * 함정) — 그래서 비동기로 보내고 본문 읽기까지 이어 붙인 future 하나를 {@code get(timeout)} 으로 기다린다. 시간이 넘으면 future 를 취소해
   * 교환을 끊는다.
   *
   * <p>본문은 {@code maxBytes} 에서 <b>자른다</b> — jsoup {@code maxBodySize} 와 같은 동작이다(예외가 아니다). 인스타 게시물
   * 페이지는 600KB 안팎, challenge 페이지도 610KB 라 2MB 상한 안이다.
   */
  private Fetched send(HttpRequest request, int maxBytes)
      throws IOException, InterruptedException, TimeoutException {
    CompletableFuture<Fetched> future =
        http.sendAsync(request, HttpResponse.BodyHandlers.ofInputStream())
            .thenApplyAsync(
                response -> {
                  try (InputStream in = response.body()) {
                    byte[] bytes = in.readNBytes(maxBytes);
                    return new Fetched(
                        response.statusCode(),
                        response.headers(),
                        new String(bytes, StandardCharsets.UTF_8));
                  } catch (IOException e) {
                    throw new java.io.UncheckedIOException(e);
                  }
                },
                bodyReaders);
    try {
      return future.get(TIMEOUT_MILLIS, TimeUnit.MILLISECONDS);
    } catch (TimeoutException e) {
      future.cancel(true); // 파생 future 의 cancel(true) 가 교환 자체를 끊는다(HttpClient.sendAsync 문서)
      throw e;
    } catch (InterruptedException e) {
      future.cancel(true);
      Thread.currentThread().interrupt(); // get() 이 지운 플래그를 되살린다 — 호출부는 Exception 으로 뭉뚱그린다
      throw e;
    } catch (ExecutionException e) {
      Throwable cause = e.getCause();
      if (cause instanceof java.io.UncheckedIOException unchecked) {
        throw unchecked.getCause();
      }
      if (cause instanceof IOException io) {
        throw io;
      }
      throw new IOException(cause);
    }
  }

  /**
   * GraphQL 요청 헤더를 <b>순서가 있는 맵</b>으로 만든다.
   *
   * <p>{@code LinkedHashMap} 인 것은 <b>역사</b>다: jsoup 시절 {@code Map.of} 를 썼더니 반복 순서가 JVM 기동마다 달라져(클래스
   * 로드 시 {@code System.nanoTime()} SALT) 같은 요청이 기동마다 다른 헤더 순서로 나갔다(2026-08-05 실측). 그게 실패 원인은
   * 아니었다(원인은 접속 지문, 2026-08-23 확정 — 클래스 주석).
   *
   * <p>⚠️ <b>지금은 이 순서가 전선에 나가지 않는다.</b> {@code HttpClient} 는 헤더를 대소문자 무시 알파벳순으로 보낸다(리뷰 2026-08-23
   * 실측: {@code Accept, Accept-Language, Content-Type, Origin, Referer, Sec-Fetch-*, User-Agent,
   * X-CSRFToken, …}). 운영 서버는 그 순서로 통과했다. 이 맵의 순서는 실패 로그의 헤더 이름 목록에만 남는다 — 테스트가 순서를 보는 것은 <b>헤더 집합이
   * 바뀌지 않았는지</b>를 보는 것이다.
   */
  static Map<String, String> graphqlHeaders(Bootstrap bootstrap, String postUrl) {
    Map<String, String> headers = new LinkedHashMap<>();
    headers.put("X-IG-App-ID", APP_ID);
    headers.put("X-FB-LSD", bootstrap.lsd());
    headers.put("X-CSRFToken", bootstrap.csrf());
    headers.put("X-FB-Friendly-Name", FRIENDLY_NAME);
    headers.put("X-Requested-With", "XMLHttpRequest");
    headers.put("Origin", "https://www.instagram.com");
    headers.put("Referer", postUrl);
    headers.put("Sec-Fetch-Site", "same-origin");
    headers.put("Sec-Fetch-Mode", "cors");
    headers.put("Sec-Fetch-Dest", "empty");
    headers.put("Accept", "*/*");
    headers.put("Accept-Language", "en-US,en;q=0.9");
    return headers;
  }

  /**
   * GraphQL 응답을 검사해 원문을 돌려준다. 로그인 벽이면 {@link LoginWallException} 을 던져 {@link #crawl} 이 한 번 재시도하게
   * 한다.
   *
   * <p><b>로그인 벽의 두 얼굴</b>(둘 다 실측): ① 3xx/4xx 로 오거나 ② <b>200 인데 본문이 HTML</b> 이다. ②는 상태코드만 봐서는 못 잡는다
   * — 첫 글자가 {@code <} 인지 봐야 한다.
   *
   * <p>🔴 <b>보낸 쿠키의 <u>이름</u>을 남긴다 — 값은 남기지 않는다.</b> "왜 됐다 안 됐다 하는가"의 유력한 가설이 <b>이 JVM 이 떠 있는 동안
   * 쿠키가 쌓인다</b>는 것인데({@link #csrfToken} 의 미결 항목), 그걸 가르는 관측이 바로 이것이다. 이름만으로는 토큰이 새지 않는다.
   *
   * <p>🔴 <b>2026-08-05 운영 실측에서 그 가설은 기각됐다</b> — {@code cookies=[csrftoken, mid]}, 부트스트랩이 준 것뿐이었다.
   *
   * <p><b>헤더 이름도 함께 남긴다.</b> 같은 서버에서 curl 은 200 JSON 을 받는데 우리만 로그인 HTML 을 받던 문제는 <b>2026-08-23 에 접속
   * 지문으로 확정</b>됐다(클래스 주석 — {@code HttpURLConnection} 만 막히고 {@code HttpClient}/HTTP2 는 통과). 그래도 이
   * 목록은 남긴다: 다음에 또 갈리면 "우리가 무엇을 보냈는가"가 첫 질문이다.
   *
   * <p>⚠️ <b>이 목록이 전부는 아니다.</b> {@code Host}·{@code Content-Length}·{@code Connection}·{@code
   * Upgrade} 처럼 {@code HttpClient} 가 직접 붙이는 것은 {@code request.headers()} 에 없고, 실제 <b>전송 순서</b>도 JDK
   * 가 다시 정할 수 있다. 여기까지는 "우리가 무엇을 얹었는가"다.
   */
  private String readGraphqlBody(
      Fetched response,
      String shortcode,
      Set<String> sentCookieNames,
      Set<String> sentHeaderNames) {
    String body = response.body();

    int status = response.status();
    String head = body == null ? "" : body.stripLeading();
    boolean html = head.startsWith("<");

    if (status != 200 || html) {
      // 🔴 상태코드·리다이렉트 대상·본문 앞부분·보낸 쿠키 이름을 남긴다. 쿠키 값과 토큰은 찍지 않는다.
      //
      // ⚠️ **warn 이다 — error 가 아니다.** 1차 실패는 재시도가 구제할 수 있고, 그때 error 를 찍으면
      // 최종 결과가 정상인데 알림만 울린다. 두 번째까지 실패하면 {@link #crawl} 이 error 로 올린다.
      log.warn(
          "인스타 GraphQL 이 로그인/오류 응답을 줬다: shortcode={} status={} html={} location={} cookies={}"
              + " headers={} body={}",
          shortcode,
          status,
          html,
          response.headers().firstValue("Location").orElse(null),
          sentCookieNames,
          sentHeaderNames,
          snippet(body));
      throw new LoginWallException("status=" + status + " html=" + html);
    }
    return body;
  }

  /**
   * 응답 본문에서 값이 새면 안 되는 키들. 이 클래스 자신이 <b>인스타 HTML 안에 토큰이 들어 있다는 사실에 의존한다</b>({@link #CSRF_NEEDLE} —
   * {@code csrfToken()} 의 폴백이 바로 그것을 읽는다). 앞 500자에 그게 올 확률은 낮지만 <b>그건 추측이고</b>, 지금 "값은 안 찍는다"를 지키는
   * 근거가 사람의 주의력뿐이었다(2026-08-05 리뷰 P2-1). 한 줄로 코드가 지키게 한다.
   */
  private static final Pattern SECRETISH =
      Pattern.compile("(\"(?:csrf_token|token|lsd|sessionid|ds_user_id)\"\\s*:\\s*)\"[^\"]*\"");

  /**
   * 로그에 남길 응답 본문 앞부분. 길면 자른다 — spring 컨테이너는 로그 로테이션에서 제외돼 있다.
   *
   * <p>🔴 <b>자르기가 정규식보다 <u>먼저</u>다.</b> 예전엔 최대 2MB 본문 <b>전체</b>에 {@code replaceAll("\\s+", " ")} 를
   * 돌린 뒤 500자를 떼어냈다 — 실패 1건마다 2MB 스캔이다(리뷰 P2-1).
   *
   * <p>⚠️ 창(4배) 밖으로 넘어가는 <b>아주 긴 토큰 값</b>은 마스킹이 못 잡을 수 있지만, 그건 어차피 최종 500자 밖이라 로그에 안 남는다.
   */
  private static String snippet(String body) {
    if (body == null) {
      return "(없음)";
    }
    // 공백을 접으면 길이가 줄어드니 여유 있게 4배를 떠서 자른다.
    int window = Math.min(body.length(), MAX_LOGGED_BODY * 4);
    String oneLine = body.substring(0, window).replaceAll("\\s+", " ").strip();
    String masked = SECRETISH.matcher(oneLine).replaceAll("$1\"***\"");
    return masked.length() <= MAX_LOGGED_BODY
        ? masked
        : masked.substring(0, MAX_LOGGED_BODY) + "…(잘림)";
  }

  /**
   * 네트워크를 타지 않는 파싱부 — 픽스처 JSON 으로 단위 테스트한다({@code InstagramUrlCrawlerTest}).
   *
   * <p>썸네일 다운로드·저장만 예외적으로 네트워크를 타는데, <b>실패해도 크롤링을 죽이지 않는다</b> — 캡션이 본론이다.
   */
  CrawlResult toCrawlResult(String json, String shortcode) {
    JsonNode item;
    try {
      JsonNode items = objectMapper.readTree(json).path("data").path(ROOT_FIELD).path("items");
      item = items.isArray() && !items.isEmpty() ? items.get(0) : null;
    } catch (Exception e) {
      log.warn("인스타 응답을 파싱하지 못했다: shortcode={}", shortcode, e);
      throw new CrawlException("게시물을 불러올 수 없는 링크예요", e);
    }
    if (item == null) {
      // 비공개·삭제·연령제한이거나 doc_id 가 만료됐다. 어느 쪽이든 사용자에게는 같은 결과다.
      log.warn("인스타 응답에 게시물이 없다(비공개·삭제이거나 doc_id 만료): shortcode={}", shortcode);
      throw new CrawlException("공개된 게시물만 등록할 수 있어요");
    }

    String username = item.path("user").path("username").asText("");
    String caption = item.path("caption").path("text").asText("");

    String cdnUrl = firstImageUrl(item);
    String thumbnail = storeThumbnail(cdnUrl, shortcode);

    return new CrawlResult(
        title(caption, username), body(caption, username), thumbnail, "instagram.com");
  }

  /**
   * 표시할 이미지 하나를 고른다.
   *
   * <p>⚠️ <b>{@code carousel_media} 는 앨범이 아니어도 키가 있고 값이 {@code null} 이다.</b> "키가 있나"로 분기하면 앨범 가지로
   * 잘못 빠져 미디어가 0개가 된다 — <b>"비지 않은 배열인가"로 분기한다.</b>
   *
   * <p>영상이면 {@code image_versions2} 가 곧 커버 이미지다 — 따로 가를 필요가 없다.
   */
  private String firstImageUrl(JsonNode item) {
    JsonNode carousel = item.path("carousel_media");
    JsonNode source = carousel.isArray() && !carousel.isEmpty() ? carousel.get(0) : item;

    JsonNode candidates = source.path("image_versions2").path("candidates");
    // candidates[0] 이 가장 크다(실측: 640x1136 → 480x852 → … 내림차순).
    return candidates.isArray() && !candidates.isEmpty()
        ? candidates.get(0).path("url").asText("")
        : "";
  }

  /**
   * CDN 이미지를 받아 MinIO 에 넣고 <b>우리 URL</b>을 돌려준다(2026-08-03 사용자 확정).
   *
   * <p><b>왜 CDN URL 을 그대로 안 쓰는가</b>: {@code oh=}/{@code oe=} 서명이 붙어 몇 시간이면 만료된다. 그대로 저장하면 하루 뒤 깨진
   * 이미지가 된다 — 블로그 {@code og:image} 와 성질이 다르다.
   *
   * <p><b>실패는 전부 삼킨다.</b> 썸네일이 없는 것과 등록이 안 되는 것 중에는 전자가 낫다. MinIO 가 없는 환경 ({@code minio.endpoint}
   * 미설정)에서도 <b>만료되는 URL 을 저장하지 않고</b> {@code null} 로 둔다.
   */
  private String storeThumbnail(String cdnUrl, String shortcode) {
    if (cdnUrl.isBlank()) {
      return null;
    }
    if (objectStorage.isEmpty()) {
      log.debug("MinIO 가 없어 인스타 썸네일을 보관하지 않는다 — 만료되는 CDN URL 은 저장하지 않는다");
      return null;
    }
    try {
      Downloaded image = download(cdnUrl);
      String objectKey =
          "archive/instagram/"
              + shortcode
              + "-"
              + UUID.randomUUID()
              + extension(image.contentType());
      // 저장하는 content-type 은 **우리가 판정한 확장자**를 따른다 — 원격 값을 그대로 넣으면
      // 공개 버킷의 오브젝트 메타데이터를 외부가 정하게 된다(리뷰 M1).
      objectStorage.get().put(objectKey, image.bytes(), contentTypeOf(objectKey));
      return objectStorage.get().publicUrl(objectKey);
    } catch (Exception e) {
      log.warn("인스타 썸네일 보관 실패 — 썸네일 없이 등록한다: shortcode={}", shortcode, e);
      return null;
    }
  }

  /**
   * 이미지 한 장을 받아온다. <b>테스트가 갈아끼우는 이음매다</b> — 이걸 인라인으로 두면 다운로드 실패 경로를 네트워크 없이 잴 수 없다.
   *
   * <p>⚠️ <b>초안은 여기서 리다이렉트를 따라갔고 호스트도 안 봤다</b>(2026-08-03 리뷰 M1). "대상이 사용자 입력이 아니라 인스타 응답이라 괜찮다"고
   * 적었는데, 그건 {@code JsoupUrlCrawler} 가 코드로 지키는 불변식을 <b>말로</b> 면제한 것이다. 게다가 이 티켓이 방금 {@code
   * archive/} 를 <b>공개 읽기</b>로 열었으므로, 받아온 것이 무엇이든 우리 도메인에서 공개 제공된다. 셋을 막는다.
   *
   * <ol>
   *   <li>호스트가 인스타 CDN 인지 — 응답이 조작돼도 임의 주소로 못 나간다
   *   <li>리다이렉트 미추종 — 검사한 호스트에서 다른 곳으로 새지 않는다
   *   <li>{@code image/*} 만 — HTML·JSON 을 이미지인 척 보관하지 않는다
   * </ol>
   */
  Downloaded download(String imageUrl) throws Exception {
    requireInstagramCdn(imageUrl);
    Connection.Response response =
        Jsoup.connect(imageUrl)
            .timeout(THUMBNAIL_TIMEOUT_MILLIS)
            .maxBodySize(MAX_IMAGE_SIZE)
            .followRedirects(false)
            .userAgent(USER_AGENT)
            .ignoreContentType(true)
            .execute();
    if (response.statusCode() >= 300) {
      throw new CrawlException("썸네일을 받지 못했다: HTTP " + response.statusCode());
    }
    String contentType = response.contentType() == null ? "" : response.contentType();
    if (!contentType.toLowerCase(Locale.ROOT).startsWith("image/")) {
      throw new CrawlException("이미지가 아닌 응답이라 보관하지 않는다: " + contentType);
    }
    return new Downloaded(response.bodyAsBytes(), contentType);
  }

  /**
   * 인스타 CDN 호스트만 허용한다. 접미사 매칭이라 {@code cdninstagram.com.evil.test} 는 안 걸린다 — {@code .} 을 붙여 비교하는
   * 이유다.
   */
  static void requireInstagramCdn(String imageUrl) {
    URI uri = URI.create(imageUrl);
    String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
    String host = uri.getHost() == null ? "" : uri.getHost().toLowerCase(Locale.ROOT);
    boolean allowed =
        ("https".equals(scheme) || "http".equals(scheme))
            && CDN_SUFFIXES.stream().anyMatch(s -> host.equals(s) || host.endsWith("." + s));
    if (!allowed) {
      throw new CrawlException("인스타 CDN 이 아닌 주소라 받지 않는다: " + host);
    }
  }

  record Downloaded(byte[] bytes, String contentType) {}

  private static String extension(String contentType) {
    String lower = contentType.toLowerCase(Locale.ROOT);
    if (lower.contains("png")) {
      return ".png";
    }
    if (lower.contains("webp")) {
      return ".webp";
    }
    if (lower.contains("heic")) {
      return ".heic";
    }
    return ".jpg";
  }

  /** 확장자 → content-type. 원격이 준 값을 그대로 저장하지 않으려고 한 번 되짚는다(리뷰 M1). */
  static String contentTypeOf(String objectKey) {
    if (objectKey.endsWith(".png")) {
      return "image/png";
    }
    if (objectKey.endsWith(".webp")) {
      return "image/webp";
    }
    if (objectKey.endsWith(".heic")) {
      return "image/heic";
    }
    return "image/jpeg";
  }

  /** 인스타 게시물에는 제목이 없다 — 캡션 첫 줄을 쓰고, 캡션이 없으면 계정명으로 대신한다. */
  private static String title(String caption, String username) {
    String firstLine =
        caption.lines().map(String::trim).filter(s -> !s.isEmpty()).findFirst().orElse("");
    if (!firstLine.isBlank()) {
      return firstLine;
    }
    return username.isBlank() ? "인스타그램 게시물" : "@" + username;
  }

  /**
   * 캡션이 본문이다. 계정명을 한 줄 얹는다 — 캡션만으로는 출처를 알 수 없고, 태깅·추천에 쓸모가 있다.
   *
   * <p>캡션이 비어도 <b>빈 본문으로 실패시키지 않는다</b>(사진만 올린 게시물이 흔하다). 계정명이 남는다.
   */
  private static String body(String caption, String username) {
    String handle = username.isBlank() ? "" : "@" + username;
    return String.join("\n", List.of(handle, caption).stream().filter(s -> !s.isBlank()).toList())
        .trim();
  }

  private static String between(String text, String needle, String terminator) {
    int start = text.indexOf(needle);
    if (start < 0) {
      return "";
    }
    int from = start + needle.length();
    int end = text.indexOf(terminator, from);
    return end < 0 ? "" : text.substring(from, end);
  }

  /** {@code private} 가 아닌 이유: {@link #graphqlHeaders} 의 순서를 테스트가 직접 확인한다. */
  record Bootstrap(String lsd, String csrf, Map<String, String> cookies) {}
}
