package com.nomara.modi.server.domain.archive.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import java.io.IOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.ClientHttpResponse;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * 유튜브 영상 전용 크롤러. <b>YouTube Data API v3 를 부른다 — 페이지 HTML 을 긁지 않는다</b>(→ 2026-08-05 교체).
 *
 * <p>🔴 <b>왜 바꿨나: 운영에서 HTML 경로가 100% 막혔다.</b> 2026-08-04 실측 —
 *
 * <pre>
 *   개발 PC(가정용 IP)   www.youtube.com/watch?v=…  → 200, 1,283,912 bytes
 *   운영 EC2(데이터센터)  같은 URL·같은 UA·같은 헤더
 *                        → 302 → https://www.google.com/sorry/index?continue=…  (387 bytes)
 * </pre>
 *
 * <p>{@code google.com/sorry} 는 구글의 봇 판정 CAPTCHA 페이지다. <b>리다이렉트를 따라가는 것은 답이 아니었다</b> — 목적지가 CAPTCHA
 * 다. 같은 EC2 에서 같은 순간에 Data API 는 200 이었고, HTML 에서 뽑던 것(제목·채널명·설명 전문·썸네일)을 전부 준다. 공식 API 라 봇 판정과
 * 무관하고 응답 계약이 안정적이다.
 *
 * <p><b>oEmbed 는 기각했다</b> — 같은 EC2 에서 200 이지만 <b>설명(description)을 주지 않는다.</b> 설명이 요약·태깅·투두 추천의 주
 * 입력이라 그걸 잃을 수 없다.
 *
 * <p><b>HTML 폴백을 남기지 않았다</b>(2026-08-05 사용자 확정). 남기면 로컬은 HTML·운영은 API 를 타게 되어 <b>"로컬에서 통과한 것이 운영에서
 * 죽는" 어제의 구도가 그대로 남는다.</b> 대신 API 키의 IP 제한을 풀어 로컬·운영이 같은 경로를 탄다.
 *
 * <p>⚠️ <b>{@link #VIDEO_ID} 가 여전히 이 클래스의 방어선이다.</b> 사용자 입력으로 요청을 조립하는 것은 그대로다 — 이제 붙는 곳이 {@code
 * youtube.com} 이 아니라 {@code googleapis.com} 의 쿼리 파라미터일 뿐이다. 11자 base64url 고정으로 잠근다.
 *
 * <p>⚠️ <b>API 키가 요청 URL 의 쿼리에 실린다.</b> 새지 않는 것을 2026-08-05 리뷰에서 spring-web 6.2.8 소스로 확인했다 — {@code
 * DefaultRestClient.createResourceAccessException} 과 {@code
 * DefaultResponseErrorHandler.getErrorMessage} 가 둘 다 {@code ?} 앞에서 자른다. 우리 로그도 URL 을 남기지 않는다.
 *
 * <p>다만 <b>확인된 것은 지금 이 구성에서다.</b> {@code org.springframework.web.client} 를 DEBUG 로 켜면 전체 URL 이 찍히고,
 * 관측(observation)을 켜도 마찬가지다(지금은 {@code RestClient.builder()} 를 직접 써서 {@code
 * ObservationRegistry.NOOP} 이다). 그럴 일이 생기면 키를 쿼리 대신 {@code X-goog-api-key} 헤더로 옮길 것 — 구글이 공식 지원하는
 * 방식이라 그때는 이 표면이 통째로 사라진다.
 */
@Component
public class YouTubeUrlCrawler implements SiteUrlCrawler {

  private static final Logger log = LoggerFactory.getLogger(YouTubeUrlCrawler.class);

  private static final List<String> HOSTS =
      List.of("youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be");

  /** 유튜브 영상 id는 <b>11자 base64url 고정</b>이다. 이 좁음이 방어다 — 넓히지 말 것. */
  private static final Pattern VIDEO_ID = Pattern.compile("[A-Za-z0-9_-]{11}");

  /**
   * 응답 본문 상한. 형제 크롤러 셋과 같은 값을 쓴다({@code JsoupUrlCrawler}·{@code InstagramUrlCrawler}).
   *
   * <p>실제 응답은 몇 KB 다(설명 2,400자 기준 약 4KB). 이 값은 정상치가 아니라 <b>안전망</b>이다.
   */
  private static final int MAX_BODY_SIZE = 2_000_000;

  /** 오류 응답 본문을 로그에 남길 때의 상한. {@link #reason} 주석 참고. */
  private static final int MAX_LOGGED_REASON = 500;

  /**
   * 썸네일 화질 우선순위.
   *
   * <p>⚠️ <b>{@code maxres} 는 모든 영상에 있지 않다</b> — 원본이 720p 미만인 옛날 영상에는 아예 없다(실측 2026-08-04). 폴백이 없으면
   * 그런 영상만 <b>썸네일이 조용히 사라진다</b>(등록은 성공해서 로그에 흔적이 없다).
   */
  private static final List<String> THUMBNAIL_PREFERENCE =
      List.of("maxres", "standard", "high", "medium", "default");

  private final ObjectMapper objectMapper;
  private final RestClient restClient;
  private final String apiKey;

  /**
   * <b>생성자는 하나뿐이다 — 테스트용 오버로드를 두지 말 것.</b> 테스트는 {@code apiUrl} 에 루프백 주소를 넘겨 {@code crawl()} 전체를
   * 돈다({@code YouTubeUrlCrawlerResponseTest}). {@code RestClient} 를 주입받는 생성자를 따로 두면 <b>스프링이 어느 쪽을
   * 쓸지 몰라 컨텍스트가 통째로 안 뜬다</b>("No default constructor found" — 2026-08-05 실측으로
   * {@code @SpringBootTest} 249개가 동반 실패했다). {@code @Autowired} 로 지목해 넘길 수도 있지만, 얻는 것이 테스트 편의뿐이라 함정을
   * 남길 이유가 없다.
   *
   * <p><b>외부 호출엔 타임아웃을 건다</b>({@code KakaoApiClient}·{@code AiServerConfig}·{@code OpenAiConfig} 와
   * 같은 기준). 주지 않으면 Java 21 기본 요청 팩토리에는 타임아웃이 <b>없어서</b> 상대가 멈추면 톰캣 스레드가 영구 점유된다. read 를 10초로 둔 것은 이
   * 호출이 <b>동기 등록(S-25-C)에서 사용자를 붙잡는 경로</b>이기 때문이다 — LLM 호출(60초)과 달리 메타데이터 조회라 길 이유가 없다.
   *
   * <p>⚠️ <b>read 타임아웃은 총 시간을 묶지 않는다.</b> SO_TIMEOUT 은 읽기 <b>1회당</b>이라, 상대가 2초마다 1바이트씩 흘리면 3초 설정으로도
   * 30초를 붙잡힌다(2026-08-05 실측 30,155ms). 교체 전 jsoup 의 {@code timeout()} 은 총 요청 시간이었으므로 <b>이 축만은
   * 후퇴</b>다. 전면 정지는 막지만 느린 드립은 못 막는다 — 총 예산은 {@code specs/OPEN.md} 의 "동기 등록의 크롤링 지연에 총 예산이 없다" 항목에
   * 함께 묶어 뒀다.
   */
  public YouTubeUrlCrawler(
      ObjectMapper objectMapper,
      @Value("${modi.archive.youtube.api-key:}") String apiKey,
      @Value("${modi.archive.youtube.api-url:https://www.googleapis.com/youtube/v3/videos}")
          String apiUrl,
      @Value("${modi.archive.youtube.connect-timeout-seconds:5}") long connectTimeoutSeconds,
      @Value("${modi.archive.youtube.read-timeout-seconds:10}") long readTimeoutSeconds) {
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(Duration.ofSeconds(connectTimeoutSeconds));
    requestFactory.setReadTimeout(Duration.ofSeconds(readTimeoutSeconds));

    this.objectMapper = objectMapper;
    this.restClient = RestClient.builder().baseUrl(apiUrl).requestFactory(requestFactory).build();
    // 값을 다듬는다 — `.env` 뒤에 붙은 공백이나 CRLF 는 isBlank() 를 통과한 뒤 쿼리에 %20/%0D 로
    // 실려 구글이 400 을 준다. 로컬은 build.gradle 이 trim 하지만 EC2 .env → compose 경로는 다르다.
    this.apiKey = apiKey == null ? "" : apiKey.trim();
  }

  @Override
  public boolean supports(URI uri) {
    String host = uri.getHost();
    if (host == null || !HOSTS.contains(host.toLowerCase(Locale.ROOT))) {
      return false;
    }
    // 영상 id 를 못 뽑는 주소(재생목록·채널·홈)는 **맡지 않는다** — 맡고 나서 던지면 일반 크롤러가
    // 시도해볼 기회조차 없어진다. 인스타 쪽(`/p/` 경로일 때만 맡는다)과 같은 규칙으로 맞췄다.
    try {
      extractVideoId(uri);
      return true;
    } catch (CrawlException e) {
      return false;
    }
  }

  /**
   * <b>키가 없어도 이 크롤러가 계속 맡는다.</b> {@code supports} 를 {@code false} 로 떨어뜨리면 일반 크롤러가 유튜브의 JS 껍데기를 받아
   * "본문을 찾을 수 없는 링크예요"를 내는데, 그건 <b>원인과 무관한 더 헷갈리는 문구</b>다. 여기서 끊고 로그에 키 미설정을 남긴다.
   */
  @Override
  public CrawlResult crawl(String url) {
    String videoId = extractVideoId(URI.create(url));

    if (apiKey.isBlank()) {
      log.error(
          "YOUTUBE_API_KEY 가 설정되지 않아 유튜브 자료를 등록할 수 없다(videoId={}). "
              + "로컬은 server/.env, 운영은 EC2 .env + docker-compose.app.yml 의 환경변수 통과를 확인할 것",
          videoId);
      throw new CrawlException("영상을 불러올 수 없는 링크예요");
    }

    return toCrawlResult(fetchSnippet(videoId), videoId);
  }

  /**
   * {@code videos.list} 를 부른다. 호출당 1 유닛이고 기본 쿼터는 하루 10,000 유닛이다.
   *
   * <p>🔴 <b>실패 경로마다 로그를 남긴다.</b> 교체 전 코드는 {@code statusCode() >= 300} 에서 <b>아무것도 안 남기고</b> 던졌고,
   * 그래서 2026-08-04 에 운영 장애의 원인을 찾느라 EC2 에 SSH 로 들어가 {@code curl} 을 직접 쳐야 했다. 로그 한 줄이면 끝났을 일이다.
   *
   * <p><b>{@code retrieve()} 가 아니라 {@code exchange()} 인 이유가 셋이다</b>(2026-08-05 리뷰):
   *
   * <ol>
   *   <li><b>본문 크기 상한</b>을 우리가 건다. {@code retrieve().body(byte[].class)} 는 무제한 버퍼링이라 64MB 를 그대로
   *       메모리에 올렸다(실측 296ms). 형제 크롤러 셋이 전부 2MB 상한을 쓰는데 여기만 빠져 있었다.
   *   <li>{@code retrieve()} 는 응답을 변환하기 전에 {@code Content-Type} 을 파싱하는데, 그게 깨지면 {@code
   *       InvalidMediaTypeException}({@code IllegalArgumentException} 계열)이 <b>{@code
   *       RestClientException} 바깥으로 샌다</b> — {@code CompositeUrlCrawler} 가 받아주긴 하지만 유튜브 전용 로그가 안
   *       남는다. 여기서는 헤더를 아예 안 본다.
   *   <li>4xx/5xx 를 <b>예외가 아니라 값</b>으로 다뤄 상태코드와 본문을 같은 자리에서 로그로 남긴다.
   * </ol>
   *
   * <p>⚠️ <b>로그에 요청 URL 을 남기지 않는다</b> — 쿼리에 API 키가 있다(클래스 주석 참고).
   */
  private JsonNode fetchSnippet(String videoId) {
    byte[] body;
    try {
      body =
          restClient
              .get()
              .uri(
                  uriBuilder ->
                      uriBuilder
                          .queryParam("part", "snippet")
                          .queryParam("id", videoId)
                          .queryParam("key", apiKey)
                          .build())
              .exchange((request, response) -> readBody(response, videoId));
    } catch (RestClientException e) {
      // 연결 실패·타임아웃. 스프링이 이 메시지를 만들 때 쿼리를 잘라내므로 키가 안 실린다
      // (DefaultRestClient.createResourceAccessException — 클래스 주석 참고).
      log.warn("유튜브 Data API 를 부르지 못했다(videoId={})", videoId, e);
      // 연결 실패·타임아웃은 상대의 일시적 상태다 — 잠시 뒤 다시 해볼 값이 있다.
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }

    JsonNode root;
    try {
      root = objectMapper.readTree(body);
    } catch (Exception e) {
      log.warn("유튜브 Data API 응답이 JSON 이 아니다(videoId={})", videoId, e);
      throw new CrawlException("영상을 불러올 수 없는 링크예요", e);
    }

    JsonNode items = root.path("items");
    if (!items.isArray() || items.isEmpty()) {
      // 200 인데 items 가 비는 경우 = 비공개·삭제·지역 차단. 사용자가 고칠 수 없는 상태다.
      log.warn("유튜브 Data API 에 영상이 없다(videoId={}) — 비공개·삭제·지역 차단", videoId);
      throw new CrawlException("영상을 불러올 수 없는 링크예요");
    }
    return items.get(0).path("snippet");
  }

  /**
   * 응답 본문을 <b>상한까지만</b> 읽고, 오류 상태면 사유를 남긴 뒤 끊는다.
   *
   * <p>바이트로 읽는 이유: Jackson 이 JSON 규격대로 바이트에서 인코딩을 스스로 판별하므로 응답 헤더의 charset 에 기대지 않는다. ⚠️ String 으로
   * 받으면 깨진다는 뜻은 아니다 — charset 을 <b>안 붙인</b> {@code application/json} 은 {@code
   * StringHttpMessageConverter} 도 UTF-8 로 읽어서 결과가 같다(2026-08-05 변형 테스트로 확인). 갈리는 것은 charset 을
   * <b>틀리게</b> 붙였을 때다({@code charset=ISO-8859-1} → String 경로만 한글이 깨진다).
   */
  private byte[] readBody(ClientHttpResponse response, String videoId) throws IOException {
    // 상한 + 1 을 읽어 "넘었는지"를 판별한다. 넘으면 나머지는 읽지 않고 버린다.
    byte[] body = response.getBody().readNBytes(MAX_BODY_SIZE + 1);
    if (body.length > MAX_BODY_SIZE) {
      log.warn("유튜브 Data API 응답이 상한({} bytes)을 넘었다(videoId={})", MAX_BODY_SIZE, videoId);
      throw new CrawlException("영상을 불러올 수 없는 링크예요");
    }

    int status = response.getStatusCode().value();
    if (status >= 400) {
      // 403 은 쿼터 소진이거나 키 제한(IP·API)에 걸린 것이다. 둘 다 사람이 손대야 풀리므로 error 다.
      String reason = reason(body);
      if (status == 403) {
        log.error("유튜브 Data API 가 403 을 줬다(videoId={}) — 쿼터 소진이거나 키 제한이다: {}", videoId, reason);
      } else {
        log.warn("유튜브 Data API 가 {} 를 줬다(videoId={}): {}", status, videoId, reason);
      }
      throw new CrawlException("영상을 불러올 수 없는 링크예요");
    }

    if (body.length == 0) {
      log.warn("유튜브 Data API 응답이 비었다(videoId={})", videoId);
      throw new CrawlException("영상을 불러올 수 없는 링크예요");
    }
    return body;
  }

  /**
   * 오류 응답 본문을 로그용으로 다듬는다.
   *
   * <p><b>자르는 이유</b>: 관측된 구글 오류는 짧은 JSON 이지만 그건 <b>확인한 계약이 아니라 관측</b>이고, 앞단 프록시가 HTML 오류 페이지를 줄 수도
   * 있다. {@code deploy/docker-compose.app.yml} 은 spring 서비스만 <b>일부러 로그 로테이션에서 제외</b>해 뒀으므로(장애 추적용)
   * 무제한 본문 로깅과 무제한 로그 파일이 겹친다.
   *
   * <p>구글 오류 본문에 API 키가 실려 온 적은 없다(사유 코드만 준다) — 다만 이것도 관측이지 보장은 아니다.
   */
  private static String reason(byte[] body) {
    String text = new String(body, StandardCharsets.UTF_8);
    return text.length() <= MAX_LOGGED_REASON
        ? text
        : text.substring(0, MAX_LOGGED_REASON) + "…(잘림)";
  }

  /**
   * 네트워크를 타지 않는 매핑부.
   *
   * <p>{@code bodyText} 에 <b>제목·채널명·설명을 함께</b> 넣는다(교체 전과 같은 순서·같은 구분자). 영상은 블로그와 달리 "본문"이 따로 없어서
   * 설명만 쓰면 설명 없는 영상이 빈 본문으로 실패한다 — 제목과 채널명은 항상 있고 태깅·요약·추천 입력으로도 쓸모가 있다.
   *
   * <p><b>{@code snippet.tags} 는 일부러 안 쓴다.</b> 작성자가 붙인 태그를 공짜로 받지만, 지금 아카이브 태그는 {@code gpt-5-nano}
   * 가 만들고 잘 돌고 있다. 측정 없이 AI 입력을 바꾸지 않는다({@code ai/docs/EXPERIMENTS.md} #6 전례).
   */
  CrawlResult toCrawlResult(JsonNode snippet, String videoId) {
    String title = text(snippet, "title");
    if (title.isBlank()) {
      log.warn("유튜브 Data API 응답에 제목이 없다(videoId={})", videoId);
      throw new CrawlException("영상을 불러올 수 없는 링크예요");
    }

    String channelTitle = text(snippet, "channelTitle");
    String description = text(snippet, "description");

    List<String> parts = new ArrayList<>();
    for (String part : List.of(title, channelTitle, description)) {
      if (!part.isBlank()) {
        parts.add(part);
      }
    }
    String bodyText = String.join("\n", parts).trim();

    String thumbnail = thumbnail(snippet.path("thumbnails"));
    return new CrawlResult(title, bodyText, thumbnail, "youtube.com");
  }

  /** 있는 것 중 가장 큰 화질을 고른다. 하나도 없으면 {@code null} — 썸네일이 없어도 등록은 성공해야 한다. */
  private static String thumbnail(JsonNode thumbnails) {
    for (String quality : THUMBNAIL_PREFERENCE) {
      String url = text(thumbnails.path(quality), "url");
      if (!url.isBlank()) {
        return url;
      }
    }
    return null;
  }

  private static String text(JsonNode node, String field) {
    return node.path(field).asText("").trim();
  }

  /**
   * 네 형태에서 영상 id를 뽑는다. <b>안 맞으면 던진다 — 조립할 요청을 추측하지 않는다.</b>
   *
   * <p>쿼리 파라미터가 붙어 와도 된다({@code ?si=...}·{@code &t=30s}) — 공유 버튼이 붙이는 추적 파라미터다.
   */
  String extractVideoId(URI uri) {
    String host = uri.getHost() == null ? "" : uri.getHost().toLowerCase(Locale.ROOT);
    String path = uri.getPath() == null ? "" : uri.getPath();

    String candidate;
    if ("youtu.be".equals(host)) {
      candidate = trimLeadingSlash(path);
    } else if (path.startsWith("/shorts/")) {
      candidate = path.substring("/shorts/".length());
    } else if (path.startsWith("/embed/")) {
      candidate = path.substring("/embed/".length());
    } else if (path.startsWith("/live/")) {
      candidate = path.substring("/live/".length());
    } else {
      candidate = queryParam(uri.getRawQuery(), "v");
    }
    // 경로가 더 이어지면(`/shorts/{id}/foo`) 첫 조각만 본다 — 아래 검증이 나머지를 걸러낸다.
    int slash = candidate.indexOf('/');
    if (slash >= 0) {
      candidate = candidate.substring(0, slash);
    }

    if (!VIDEO_ID.matcher(candidate).matches()) {
      throw new CrawlException("영상 주소를 알아볼 수 없어요");
    }
    return candidate;
  }

  private static String trimLeadingSlash(String path) {
    return path.startsWith("/") ? path.substring(1) : path;
  }

  private static String queryParam(String rawQuery, String key) {
    if (rawQuery == null) {
      return "";
    }
    for (String pair : rawQuery.split("&")) {
      int eq = pair.indexOf('=');
      if (eq > 0 && key.equals(pair.substring(0, eq))) {
        return pair.substring(eq + 1);
      }
    }
    return "";
  }
}
