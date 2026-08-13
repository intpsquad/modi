package com.nomara.modi.server.domain.archive.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.net.URI;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
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
    Connection.Response response;
    try {
      response =
          Jsoup.connect(postUrl)
              .timeout(TIMEOUT_MILLIS)
              .maxBodySize(MAX_BODY_SIZE)
              .followRedirects(false)
              .userAgent(USER_AGENT)
              .header("Accept-Language", "en-US,en;q=0.9")
              .ignoreContentType(true)
              .execute();
    } catch (Exception e) {
      log.warn("인스타 게시물 페이지를 불러오지 못했다: {}", postUrl, e);
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }
    if (response.statusCode() >= 300) {
      // 🔴 **이것이 소프트 블록의 모양이다**(2026-08-06 리뷰 P1). 참조 문서(test.md)가 적은 차단 증상이
      // 정확히 "302/403 to login even with valid tokens" 이고, 위 주석대로 차단 중에는 /p/ 페이지도
      // challenge 를 준다(실측 610KB). 비공개·삭제 게시물은 여기로 오지 않는다 — 그쪽은 부트스트랩을
      // 통과한 뒤 GraphQL 의 빈 items 로 걸러진다("공개된 게시물만 등록할 수 있어요").
      return blocked("인스타 게시물 페이지가 리다이렉트/오류를 줬다(status={}) — 차단으로 본다", response.statusCode());
    }

    // 원문을 **한 번만** 읽어 로컬에 둔다 — jsoup 응답 본문 재읽기 함정(YouTubeUrlCrawler 참고).
    //
    // 🔴 **`body()` 도 감싼다.** 이건 헤더 뒤 본문 읽기라 소켓이 중간에 끊기면
    // `UncheckedIOException` 이 나는데, 그건 `CrawlException` 이 아니라서 양쪽 호출부가 둘 다
    // 나쁘게 반응한다 — 비동기는 `markCrawlFailed()` 를 못 타 **영구 PENDING**, 동기는
    // **HTTP 500**(`ArchiveCrawlProcessor` 주석이 스스로 경고한 그 사고). 같은 티켓에서 유튜브
    // 쪽은 정확히 이 이유로 감쌌는데 여기만 빠져 있었다(2026-08-04 리뷰 P1-2).
    String html;
    try {
      html = response.body();
    } catch (Exception e) {
      log.warn("인스타 게시물 페이지 본문을 읽지 못했다: {}", postUrl, e);
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }
    String lsd = between(html, LSD_NEEDLE, "\"");
    String csrf = csrfToken(response.cookie("csrftoken"), html);
    if (lsd.isBlank() || csrf.isBlank()) {
      // 둘 중 하나라도 비면 GraphQL 은 로그인 페이지만 돌려준다 — 여기서 끊는 편이 낫다.
      //
      // 🔴 **여기도 차단이다**(2026-08-06 리뷰 P1). 정상 /p/ 페이지에는 lsd 니들이 늘 있고, 없다는 것은
      // 받은 것이 게시물 페이지가 아니라는 뜻이다(challenge HTML). 이 로그가 예전부터 "차단됐을 수
      // 있다"고 말하면서 정작 예외는 영구 실패였다.
      return blocked("인스타 토큰을 못 땄다(lsd={}, csrf={}) — 차단으로 본다", !lsd.isBlank(), !csrf.isBlank());
    }
    return new Bootstrap(lsd, csrf, graphqlCookies(response.cookies(), csrf));
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
    // 🔴 **헤더를 하나씩 순서대로 얹는다 — `Map.of` 를 쓰지 말 것.**
    //
    // 예전엔 `.headers(Map.of(...))` 였다. `Map.of` 가 돌려주는 `ImmutableCollections.MapN` 은
    // **반복 순서가 JVM 기동마다 달라진다**(클래스 로드 시 `System.nanoTime()` 으로 SALT 를 잡는다).
    // jsoup 은 그 맵을 순회하며 헤더를 얹으므로, **이 요청의 헤더 10개 순서가 기동마다 바뀌고 한
    // JVM 안에서는 고정**됐다 — 같은 코드를 4번 돌려 실측했다(2026-08-05).
    //
    // 그게 원인인지는 **아직 모른다**(curl 로는 어떤 순서든 200 JSON 이다). 다만 외부 안티봇
    // 엔드포인트로 나가는 요청이 기동마다 달라지는 것 자체가 결함이고, "재시작하면 되기도 한다"는
    // 오늘의 재현 불가를 그대로 설명한다. 순서는 참조 문서(브라우저 캡처)의 나열 순서를 따른다.
    Connection connection =
        Jsoup.connect(baseUrl + "/graphql/query/")
            .timeout(TIMEOUT_MILLIS)
            .maxBodySize(MAX_BODY_SIZE)
            .followRedirects(false)
            .ignoreContentType(true)
            .ignoreHttpErrors(true)
            .userAgent(USER_AGENT)
            .cookies(bootstrap.cookies())
            .headers(graphqlHeaders(bootstrap, postUrl))
            .data("lsd", bootstrap.lsd())
            .data("doc_id", docId)
            .data("fb_api_req_friendly_name", FRIENDLY_NAME)
            .data("server_timestamps", "true")
            .data("variables", variables)
            // ⚠️ `.post()` 가 아니다 — 그건 Document 를 돌려줘 `.body()` 가 <body> 엘리먼트가 된다.
            // 우리가 필요한 것은 응답 원문(JSON)이다.
            .method(Connection.Method.POST);

    Connection.Response response;
    try {
      response = connection.execute();
    } catch (Exception e) {
      log.warn("인스타 GraphQL 호출 실패: shortcode={}", shortcode, e);
      // ignoreHttpErrors 를 켜 뒀으므로 여기 오는 것은 순수 네트워크 오류다(연결 실패·타임아웃) —
      // 부트스트랩의 같은 실패와 성격이 정확히 같다. 문구가 달라서 분류에서 빠져 있었다(리뷰 P2).
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }
    return readGraphqlBody(
        response, shortcode, bootstrap.cookies().keySet(), connection.request().headers().keySet());
  }

  /**
   * GraphQL 요청 헤더를 <b>순서가 있는 맵</b>으로 만든다.
   *
   * <p>🔴 <b>{@code LinkedHashMap} 이다 — {@code Map.of} 로 되돌리지 말 것.</b> {@code Map.of} 가 돌려주는 {@code
   * ImmutableCollections.MapN} 은 <b>반복 순서가 JVM 기동마다 달라진다</b>(클래스 로드 시 {@code System.nanoTime()} 으로
   * SALT 를 잡는다). jsoup 은 이 맵을 순회하며 헤더를 얹으므로, 예전 코드는 <b>같은 요청을 기동마다 다른 헤더 순서로</b> 보냈다 — 같은 코드를 4번 돌려
   * 실측했다(2026-08-05). 한 JVM 안에서는 고정이라 "재시작하면 되기도 한다"가 됐다.
   *
   * <p>그것이 인스타 실패의 <b>원인인지는 모른다</b> — curl 로는 어떤 순서든 200 JSON 이다. 다만 외부 안티봇 엔드포인트로 나가는 요청이 비결정적인 것
   * 자체가 결함이라 원인과 무관하게 고친다.
   *
   * <p>순서는 참조 문서(`Instagram Public Post Scraping`)의 나열 순서를 따랐다 — 브라우저 캡처에서 나온 것이라 우리가 가진 것 중 가장 근거
   * 있는 순서다. <b>따로 뺀 이유는 테스트가 순서를 못 박기 위해서다.</b>
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
   * <p><b>그래서 헤더 이름과 순서도 함께 남긴다.</b> 우리가 실제로 무엇을 어떤 순서로 보내는지 <b>지금까지 한 번도 확인한 적이 없다.</b> 같은 EC2 에서
   * curl 은 200 JSON 을 받는데 우리만 로그인 HTML 을 받고, IP·쿠키·HTTP 버전·헤더 구성·헤더 순서를 curl 로 전부 배제했다 — 남은 것은
   * <b>우리가 실제로 보내는 것</b> 아니면 <b>Java 클라이언트 지문</b>이다. 싼 쪽을 먼저 본다.
   *
   * <p>⚠️ <b>이 목록이 전부는 아니다.</b> {@code Host}·{@code Content-Length}·{@code Connection} 처럼 {@code
   * HttpURLConnection} 이 직접 붙이는 것은 jsoup 의 맵에 없고, 실제 <b>전송 순서</b>도 JDK 가 다시 정할 수 있다. 여기까지는 "jsoup 이
   * 무엇을 얹었는가"다.
   */
  private String readGraphqlBody(
      Connection.Response response,
      String shortcode,
      Set<String> sentCookieNames,
      Set<String> sentHeaderNames) {
    String body;
    try {
      body = response.body();
    } catch (Exception e) {
      log.warn("인스타 GraphQL 응답 본문을 읽지 못했다: shortcode={}", shortcode, e);
      // 헤더 뒤 본문 읽기 중 소켓이 끊긴 것 — 부트스트랩의 body() 실패와 같다(리뷰 P2).
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }

    int status = response.statusCode();
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
          response.header("Location"),
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
