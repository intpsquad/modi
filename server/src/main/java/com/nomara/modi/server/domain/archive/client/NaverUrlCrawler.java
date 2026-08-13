package com.nomara.modi.server.domain.archive.client;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import java.net.URI;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.jsoup.Connection;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * 네이버 단축 주소(<b>{@code naver.me}</b>)와 장소 페이지 전용 크롤러(2026-08-05).
 *
 * <p><b>왜 필요한가.</b> 네이버 지도 앱에서 가게를 공유하면 {@code https://naver.me/FoEJcO1X} 가 온다. 이게 3xx 라 {@code
 * JsoupUrlCrawler} 의 SSRF 방어(리다이렉트 미추종)에 걸려 <b>"리다이렉트되는 링크는 등록할 수 없어요"로 거절</b>됐다. 그 방어 자체는 옳다 — 임의
 * 외부 URL 을 상대하는 자리라 추종을 켜면 스킴·사설IP 재검증 없이 아무 호스트로 넘어간다. {@code youtu.be} 도 같은 이유로 막혀 있었고 전용 크롤러로
 * 풀었다.
 *
 * <p><b>실측 경로</b>(2026-08-05, {@code naver.me/FoEJcO1X} = 몽탄):
 *
 * <pre>
 *   naver.me/FoEJcO1X
 *     → 307  map.naver.com/p/entry/place/1810277002?lng=…&amp;lat=…
 *            (200 이지만 2,353 bytes JS 껍데기 — og:title 이 없다. <b>id 만 뽑고 버린다</b>)
 *     → m.place.naver.com/place/{id}/home
 *            업종에 따라 바로 200 이거나 302 로 /restaurant/{id}/home 등으로 한 번 넘긴다.
 *            <b>업종을 몰라도 되는 이유가 이것이다</b> — /place/ 하나가 진입점이다.
 * </pre>
 *
 * <p>🔴 <b>모바일 UA 가 필수다.</b> PC UA 와 UA 없음은 <b>첫 요청부터 {@code 429}</b> 를 받는다(실측). 볼륨이 아니라 UA 판별이다.
 *
 * <p>🔴 <b>없는 장소도 200 이다</b>(340KB, {@code og:title} 없음). 상태코드로 구분할 수 없어 <b>제목 유무로 판정</b>한다 — 인스타의
 * "200 인데 {@code items} 가 빈 배열"과 같은 함정이다.
 *
 * <p><b>공식 API 는 없다.</b> 네이버 검색 API(지역)는 키워드 검색만 되고 place id·좌표로 조회가 안 된다 — 이름을 알아야 부를 수 있는데 그 이름을
 * 얻으려는 것이라 순환이다. 그래서 유튜브처럼 API 로 갈아탈 수 없고 <b>인스타와 같은 등급으로 깨지기 쉽다</b>({@code specs/OPEN.md}).
 *
 * <p>⚠️ <b>2026-08-05 기준 운영 EC2 는 안 막혔다</b> — 데이터센터 IP 로도 200 · 609,637 bytes · 0.417s 로 로컬과 바이트까지
 * 같았다. 유튜브가 CAPTCHA 에 막힌 것과 다른 점이라 배포 전에 확인해 뒀다. <b>다만 이건 스냅샷 한 번이다</b> — 유튜브도 정확히 이 문장이 참이던 상태에서
 * 뒤집혔다({@code YouTubeUrlCrawler}). 네이버만 실패하기 시작하면 여기부터 다시 재라.
 */
@Component
public class NaverUrlCrawler implements SiteUrlCrawler {

  private static final Logger log = LoggerFactory.getLogger(NaverUrlCrawler.class);

  private static final int TIMEOUT_MILLIS = 5000;
  private static final int MAX_BODY_SIZE = 2_000_000;

  /** 🔴 이 UA 를 바꾸지 말 것 — PC UA 는 {@code 429} 다(실측 2026-08-05). */
  private static final String MOBILE_USER_AGENT =
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
          + " (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";

  /**
   * 장소 주소로 인정하는 호스트들 — <b>전부 2026-08-05 에 실제로 확인했다</b>({@code map.naver.com} 302, 나머지 200). 여기 있는
   * 것은 <b>id 를 뽑는 대상</b>일 뿐이고, 실제 요청은 언제나 {@code place-url} 로 나간다.
   *
   * <p>⚠️ {@code place.naver.com} 은 <b>넣었다가 뺐다</b> — 그럴듯해 보였지만 연결 자체가 안 된다(실측 {@code http=000}).
   * 추측으로 호스트를 늘리지 말 것.
   *
   * <p>🔴 <b>이 목록이 "장소 주소인가"의 유일한 판정 기준이다.</b> 없으면 {@code blog.naver.com/{id}/{글번호}} 처럼 <b>두 조각짜리
   * 네이버 주소가 전부 장소로 오인된다</b> — 2026-08-05 리뷰가 재현했다(`223456789012` 를 place id 로 뽑았다). 그러면 블로그 단축 링크가
   * 일반 크롤러로 안 넘어갈 뿐 아니라, 글번호가 실재하는 place id 와 겹치면 <b>엉뚱한 가게 이름·주소·썸네일이 저장되고 AI 태깅까지 그 내용으로 돈다.</b>
   */
  private static final List<String> DEFAULT_PLACE_HOSTS =
      List.of("map.naver.com", "m.place.naver.com", "pcmap.place.naver.com");

  /**
   * place id 는 숫자다. ⚠️ <b>여기가 이 클래스의 SSRF 방어선이다</b> — 사용자 입력으로 요청 URL 을 조립하므로 느슨하면 서버가 임의 주소를
   * 부른다(유튜브의 11자 id 와 같은 역할).
   */
  private static final Pattern PLACE_ID = Pattern.compile("[0-9]{1,20}");

  /** {@code og:title} 이 {@code "몽탄 : 네이버"} 로 온다. */
  private static final String OG_TITLE_SUFFIX = " : 네이버";

  private final ObjectMapper objectMapper;
  private final JsoupUrlCrawler fallback;
  private final String shortUrlHost;
  private final String placeUrl;
  private final List<String> allowedHosts;
  private final List<String> placeHosts;

  /**
   * {@code short-url-host}·{@code place-url}·{@code allowed-hosts} 를 프로퍼티로 뺀 이유는 <b>테스트가 루프백 서버를
   * 가리켜 {@code crawl()} 전체를 돌기 위해서다</b>(2026-08-04 교훈: 파싱부만 테스트하면 이음매는 아무도 안 본다).
   *
   * <p>🔴 <b>{@code allowed-hosts} 는 보안 경계다.</b> 단축 주소가 어디로든 보낼 수 있으므로 목적지 호스트를 여기서 잠근다. 운영에서
   * {@code naver.com,naver.me} 밖으로 넓히지 말 것.
   */
  public NaverUrlCrawler(
      ObjectMapper objectMapper,
      JsoupUrlCrawler fallback,
      @Value("${modi.archive.naver.short-url-host:naver.me}") String shortUrlHost,
      @Value("${modi.archive.naver.place-url:https://m.place.naver.com/place}") String placeUrl,
      @Value("${modi.archive.naver.allowed-hosts:naver.com,naver.me}") String allowedHosts) {
    this.objectMapper = objectMapper;
    this.fallback = fallback;
    this.shortUrlHost = shortUrlHost.trim().toLowerCase(Locale.ROOT);
    this.placeUrl = placeUrl.trim();
    // 🔴 빈 항목을 걸러낸다. `a,,b` 나 ` ` 가 빈 문자열 항목을 만들면 host 가 null 인 URI 가 통과해
    // **오타 하나로 방어선이 무력화된다**(2026-08-05 리뷰). 다 비면 기동을 멈추는 편이 안전하다.
    this.allowedHosts =
        Arrays.stream(allowedHosts.split(","))
            .map(h -> h.trim().toLowerCase(Locale.ROOT))
            .filter(h -> !h.isEmpty())
            .toList();
    if (this.allowedHosts.isEmpty()) {
      throw new IllegalStateException(
          "modi.archive.naver.allowed-hosts 가 비어 있다 — 단축 주소 목적지 검증이 불가능하다");
    }
    // 설정된 place-url 의 호스트도 장소 호스트로 친다. 운영에서는 m.place.naver.com 이라 기본 목록과
    // 겹치고, 테스트는 이 한 줄 덕에 루프백을 장소 호스트로 쓸 수 있다(별도 프로퍼티가 필요 없다).
    this.placeHosts =
        Stream.concat(DEFAULT_PLACE_HOSTS.stream(), Stream.of(host(URI.create(this.placeUrl))))
            .filter(h -> !h.isEmpty())
            .distinct()
            .toList();
  }

  /**
   * <b>{@code naver.me} 는 목적지를 모른 채 맡는다.</b> 무엇으로 펼쳐지는지는 요청해봐야 알고, 이 판정은 네트워크를 타면 안 된다({@link
   * SiteUrlCrawler} 계약). 장소가 아니면 {@code crawl()} 이 일반 크롤러로 넘긴다.
   */
  @Override
  public boolean supports(URI uri) {
    String host = host(uri);
    if (host.isEmpty()) {
      return false;
    }
    // 장소 id 를 못 뽑는 네이버 지도 주소(검색 결과·길찾기)와 블로그·뉴스는 맡지 않는다 —
    // 일반 크롤러에 기회를 준다. 호스트 판정은 findPlaceId 안에 있다.
    return host.equals(shortUrlHost) || !findPlaceId(uri).isEmpty();
  }

  @Override
  public CrawlResult crawl(String url) {
    String resolved = host(URI.create(url)).equals(shortUrlHost) ? resolveShortUrl(url) : url;

    String placeId = findPlaceId(URI.create(resolved));
    if (placeId.isEmpty()) {
      // 장소가 아닌 네이버 링크(블로그·뉴스·카페…)다. 일반 크롤러에 넘긴다 —
      // 그쪽 validateUrl 이 스킴·사설IP 를 **다시 검증**하므로 여기서 검증을 중복하지 않는다.
      log.debug("네이버 단축 주소가 장소가 아니다 — 일반 크롤러로 넘긴다: {}", resolved);
      return fallback.crawl(resolved);
    }
    return crawlPlace(placeId);
  }

  // ------------------------------------------------------------------ 단축 주소 해석

  /**
   * 단축 주소를 <b>한 홉만</b> 펼친다. 추종을 켜지 않는 이유는 클래스 주석 참고.
   *
   * <p>🔴 <b>목적지 호스트 검증이 이 메서드의 존재 이유다.</b> 단축 주소는 발급자가 어디로든 보낼 수 있어, 검증이 없으면 이 크롤러가 일반 크롤러의 추종 금지를
   * 우회하는 통로가 된다.
   */
  private String resolveShortUrl(String url) {
    Connection.Response response;
    try {
      response =
          Jsoup.connect(url)
              .timeout(TIMEOUT_MILLIS)
              .maxBodySize(MAX_BODY_SIZE)
              .followRedirects(false)
              .userAgent(MOBILE_USER_AGENT)
              .ignoreContentType(true)
              .execute();
    } catch (Exception e) {
      log.warn("네이버 단축 주소를 펼치지 못했다: {}", url, e);
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }

    int status = response.statusCode();
    if (status < 300 || status >= 400) {
      log.warn("네이버 단축 주소가 리다이렉트가 아니다(status={}): {}", status, url);
      throw new CrawlException("장소를 불러올 수 없는 링크예요");
    }

    String location = response.header("Location");
    if (location == null || location.isBlank()) {
      log.warn("네이버 단축 주소에 Location 이 없다(status={}): {}", status, url);
      throw new CrawlException("장소를 불러올 수 없는 링크예요");
    }
    return requireAllowedHost(location);
  }

  /**
   * 허용 호스트가 아니면 <b>요청하지 않고</b> 끊는다. 통과하면 그 주소를 그대로 돌려준다.
   *
   * <p>⚠️ <b>상대 경로 {@code Location} 은 거절된다</b>(호스트가 없으니 허용 목록에 못 걸린다). RFC 7231 은 상대 경로를 허용하고 네이버는
   * 2026-08-05 실측에서 절대 URL 을 줬지만, 그게 바뀌면 <b>여기서 조용히 전멸한다</b>. 그때는 기준 URL 로 resolve 하는 한 줄을 넣되
   * <b>resolve 결과를 다시 이 검사에 태워야</b> 한다.
   */
  private String requireAllowedHost(String location) {
    URI dest;
    try {
      dest = URI.create(location);
    } catch (IllegalArgumentException e) {
      log.warn("네이버 리다이렉트의 Location 을 해석하지 못했다: {}", location);
      throw new CrawlException("장소를 불러올 수 없는 링크예요", e);
    }

    String scheme = dest.getScheme() == null ? "" : dest.getScheme().toLowerCase(Locale.ROOT);
    String host = host(dest);
    boolean allowed = allowedHosts.stream().anyMatch(a -> host.equals(a) || host.endsWith("." + a));
    if (!scheme.equals("https") && !scheme.equals("http")) {
      log.error("네이버 단축 주소가 http(s) 가 아닌 곳으로 보낸다(scheme={})", scheme);
      throw new CrawlException("장소를 불러올 수 없는 링크예요");
    }
    if (!allowed) {
      log.error("네이버 단축 주소가 허용되지 않은 호스트로 보낸다(host={})", host);
      throw new CrawlException("장소를 불러올 수 없는 링크예요");
    }
    return location;
  }

  // ------------------------------------------------------------------ 장소 id

  /**
   * 주소에서 place id 를 뽑는다. 못 뽑으면 <b>빈 문자열</b>이다 — 여기서 던지지 않는 이유는 {@link #supports} 가 이 결과로 판정하고,
   * {@code crawl()} 은 일반 크롤러로 넘겨야 하기 때문이다.
   *
   * <pre>
   *   map.naver.com/p/entry/place/{id}   → "place" 다음 조각
   *   map.naver.com/?…&amp;pinId={id}&amp;…    → 쿼리의 pinId   ← 지도 **앱** 공유 버튼
   *   m.place.naver.com/{업종}/{id}/home → 두 번째 조각
   *   place.naver.com/{업종}/{id}/…      → 두 번째 조각
   * </pre>
   *
   * <p>🔴 <b>지도 앱과 웹이 서로 다른 모양을 준다</b>(2026-08-05 실측, 사용자 신고로 발견). 웹 장소 페이지의 공유는 경로형 ({@code
   * /p/entry/place/1810277002})인데, <b>지도 앱</b>의 공유 버튼은 <b>경로에 장소가 없는</b> 좌표 URL 을 준다:
   *
   * <pre>
   *   map.naver.com/?lat=37.5032828&amp;title=돼지통%20역삼2호점&amp;pinId=1340737588&amp;pinType=site&amp;…
   * </pre>
   *
   * 경로만 보던 초안은 여기서 장소를 못 알아보고 일반 크롤러로 넘겼는데, 그 주소가 또 3xx 라 <b>"리다이렉트되는 링크는 등록할 수 없어요"로 죽었다</b>(실측
   * `itemId=64`). {@code pinId} 는 place id 와 <b>같은 값</b>이다 —
   * `m.place.naver.com/place/1340737588/home` 이 302 로 `/restaurant/1340737588/home` 을 주고 거기
   * `PlaceDetailBase:1340737588` 이 있는 것을 확인했다.
   *
   * <p>⚠️ <b>쿼리의 {@code title} 은 쓰지 않는다.</b> 거기에도 가게명이 있지만(`title=돼지통%20역삼2호점`) 그것만 믿으면 주소·업종·한줄평이
   * 없는 얇은 항목이 된다. place id 로 페이지를 받는 편이 낫고, 그게 웹 공유와 같은 경로다.
   */
  String findPlaceId(URI uri) {
    // 🔴 호스트 검사가 **먼저**다. 이게 없으면 blog.naver.com/{id}/{글번호} 처럼 두 조각짜리 네이버
    // 주소가 전부 장소로 오인된다(DEFAULT_PLACE_HOSTS 주석 참고).
    if (!placeHosts.contains(host(uri))) {
      return "";
    }
    String path = uri.getPath() == null ? "" : uri.getPath();
    List<String> segments = new ArrayList<>();
    for (String s : path.split("/")) {
      if (!s.isBlank()) {
        segments.add(s);
      }
    }

    String candidate = "";
    if ("map.naver.com".equals(host(uri))) {
      int at = segments.indexOf("place");
      candidate = at >= 0 && at + 1 < segments.size() ? segments.get(at + 1) : pinId(uri);
    } else if (segments.size() >= 2) {
      candidate = segments.get(1);
    }
    return PLACE_ID.matcher(candidate).matches() ? candidate : "";
  }

  /**
   * 쿼리에서 {@code pinId} 값을 뽑는다. 없으면 빈 문자열.
   *
   * <p>🔴 <b>{@code getRawQuery()} 다 — {@code getQuery()} 가 아니다.</b> 후자는 퍼센트 디코딩을 <b>먼저</b> 하므로
   * {@code title} 안의 {@code %26} 이 진짜 {@code &} 가 되어 <b>칸이 어긋난다</b>: {@code
   * ?title=a%26pinId=999&pinId=123} 이 {@code pinId=999} 를 먼저 내놓는다. SSRF 는 아니지만(숫자 id 로 우리 {@code
   * place-url} 에만 나간다) <b>엉뚱한 가게가 저장된다.</b> 원문으로 쪼개면 그 경로가 없다 — {@code pinId} 는 숫자라 디코딩할 것도 없고, 어차피
   * {@link #PLACE_ID} 로 다시 거른다.
   */
  private static String pinId(URI uri) {
    String query = uri.getRawQuery();
    if (query == null) {
      return "";
    }
    for (String pair : query.split("&")) {
      if (pair.startsWith("pinId=")) {
        return pair.substring("pinId=".length());
      }
    }
    return "";
  }

  // ------------------------------------------------------------------ 장소 페이지

  private CrawlResult crawlPlace(String placeId) {
    String url = placeUrl + "/" + placeId + "/home";
    Connection.Response response = fetch(url, placeId);

    // 업종별 경로로 한 홉 넘길 수 있다(/place/{id} → /restaurant/{id}). 추종을 켜지 않고 직접 한 번만 따라간다.
    int status = response.statusCode();
    if (status >= 300 && status < 400) {
      String location = response.header("Location");
      if (location == null || location.isBlank()) {
        log.warn("네이버 장소 페이지가 Location 없는 {} 를 줬다(placeId={})", status, placeId);
        throw new CrawlException("장소를 불러올 수 없는 링크예요");
      }
      response = fetch(requireAllowedHost(location), placeId);
      status = response.statusCode();
    }

    if (status != 200) {
      // 🔴 429 면 UA 판별에 걸린 것이다. 로그가 없으면 이걸 알아내려고 EC2 에 들어가야 한다.
      log.error("네이버 장소 페이지가 {} 를 줬다(placeId={}) — 429 면 UA 차단이다", status, placeId);
      throw new CrawlException("장소를 불러올 수 없는 링크예요");
    }

    String rawHtml;
    try {
      // 🔴 원문을 **먼저** 읽는다. jsoup 응답 본문은 한 번만 읽히고, parse() 가 스트림을 소비하면
      // body() 가 터진다(2026-08-03 유튜브에서 하루 동안 이걸로 전멸했다).
      rawHtml = response.body();
    } catch (Exception e) {
      log.warn("네이버 장소 페이지 본문을 읽지 못했다(placeId={})", placeId, e);
      throw new CrawlException("장소를 불러올 수 없는 링크예요", e);
    }
    return toCrawlResult(rawHtml, placeId);
  }

  private Connection.Response fetch(String url, String placeId) {
    try {
      return Jsoup.connect(url)
          .timeout(TIMEOUT_MILLIS)
          .maxBodySize(MAX_BODY_SIZE)
          .followRedirects(false)
          .userAgent(MOBILE_USER_AGENT)
          .header("Accept-Language", "ko-KR,ko;q=0.9")
          .ignoreContentType(true)
          .execute();
    } catch (Exception e) {
      log.warn("네이버 장소 페이지를 불러오지 못했다(placeId={})", placeId, e);
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }
  }

  /**
   * 네트워크를 타지 않는 매핑부.
   *
   * <p><b>앵커가 place id 로 조립된다</b> — {@code "PlaceDetailBase:{id}"}. 유튜브의 고정 문자열 앵커보다 강하다.
   *
   * <p>🔴 <b>앵커 없이 첫 매치를 집으면 안 된다.</b> {@code "name"} 은 바로 뒤 {@code Menu} 엔티티에도 있어서(실측: {@code 우대갈비
   * 280g}) 경계를 안 두면 메뉴 이름이 가게명 자리에 들어간다. 유튜브에서 {@code "author"} 가 JSON-LD·광고에도 있어 엉뚱한 값을 집었던 것과 같은
   * 함정이다.
   *
   * <p><b>{@code og:description} 은 쓰지 않는다</b> — 실측값이 {@code "방문자리뷰 5,969 · 블로그리뷰 10,491"} 이라 본문으로 쓸
   * 수 없다.
   */
  CrawlResult toCrawlResult(String rawHtml, String placeId) {
    Document doc = Jsoup.parse(rawHtml, placeUrl);
    String entity = JsonScan.objectAfter(rawHtml, "\"PlaceDetailBase:" + placeId + "\"");
    if (entity.isEmpty()) {
      // 구조가 바뀌었다. 제목만이라도 살려 등록은 성공시킨다 — 조용히 실패하지 않도록 로그를 남긴다.
      log.warn("네이버 장소 상세를 찾지 못했다(placeId={}) — 페이지 구조가 바뀌었을 수 있다", placeId);
    }

    String title = unescape(JsonScan.stringValue(entity, "name"));
    if (title.isBlank()) {
      title = stripNaverSuffix(doc.select("meta[property=og:title]").attr("content"));
    }
    if (title.isBlank()) {
      // 없는 장소는 404 가 아니라 200 을 준다(실측 340KB). 제목 유무가 유일한 판정 수단이다.
      log.warn("네이버 장소에 제목이 없다(placeId={}) — 없는 장소이거나 구조가 바뀌었다", placeId);
      throw new CrawlException("장소를 불러올 수 없는 링크예요");
    }

    List<String> parts = new ArrayList<>();
    parts.add(title);
    addIfPresent(parts, unescape(JsonScan.stringValue(entity, "category")));
    addIfPresent(parts, unescape(JsonScan.stringValue(entity, "roadAddress")));
    for (String review : JsonScan.stringArray(entity, "microReviews")) {
      addIfPresent(parts, unescape(review));
    }
    List<String> conveniences = JsonScan.stringArray(entity, "conveniences");
    if (!conveniences.isEmpty()) {
      addIfPresent(parts, String.join(", ", conveniences.stream().map(this::unescape).toList()));
    }

    String thumbnail = doc.select("meta[property=og:image]").attr("content");
    return new CrawlResult(
        title, String.join("\n", parts), thumbnail.isBlank() ? null : thumbnail, "naver.com");
  }

  private static void addIfPresent(List<String> parts, String value) {
    if (!value.isBlank()) {
      parts.add(value);
    }
  }

  /** {@code "몽탄 : 네이버"} → {@code "몽탄"}. */
  private static String stripNaverSuffix(String ogTitle) {
    String trimmed = ogTitle.trim();
    return trimmed.endsWith(OG_TITLE_SUFFIX)
        ? trimmed.substring(0, trimmed.length() - OG_TITLE_SUFFIX.length()).trim()
        : trimmed;
  }

  /**
   * JSON 문자열 이스케이프를 <b>Jackson 에 맡겨</b> 푼다. 손으로 풀면 유니코드 이스케이프의 네 자리가 16진수가 아닐 때 예외가 새어 나간다
   * (2026-08-03 리뷰 M2).
   */
  private String unescape(String raw) {
    if (raw.isEmpty()) {
      return "";
    }
    try {
      return objectMapper.readTree("\"" + raw + "\"").asText();
    } catch (Exception e) {
      // 못 풀면 원문을 쓴다 — 몇 글자가 지저분할 뿐, 등록을 막을 이유가 아니다.
      log.debug("네이버 장소 값의 이스케이프를 풀지 못했다", e);
      return raw;
    }
  }

  private static String host(URI uri) {
    return uri.getHost() == null ? "" : uri.getHost().toLowerCase(Locale.ROOT);
  }
}
