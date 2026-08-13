package com.nomara.modi.server.domain.archive.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.entry;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.net.URI;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * 인스타 크롤러 — <b>네트워크를 타지 않는다</b>. {@code extractShortcode}·{@code toCrawlResult}에 직접 넘기고, 썸네일 다운로드는
 * {@code download()} 이음매를 갈아끼운다.
 *
 * <p><b>픽스처는 실제 응답에서 옮긴 모양이다</b>(2026-08-03, 공개 게시물 {@code DZb-UAhz4Iq}에서 확인). 특히 {@code
 * carousel_media} 가 <b>키는 있고 값이 {@code null}</b> 인 것을 실제 응답에서 확인하고 그대로 옮겼다 — 지어냈으면 이 함정을 재현하지 못했을
 * 것이다.
 */
class InstagramUrlCrawlerTest {

  private static final String SINGLE_VIDEO_JSON =
      """
      {"data":{"xdt_api__v1__media__shortcode__web_info":{"items":[{
        "code":"DZb-UAhz4Iq",
        "media_type":2,
        "user":{"username":"workout_plz"},
        "caption":{"text":"딥워터 한달남았따\\n\\n절대 면재질 옷은 XXX\\n래쉬가드 추천"},
        "carousel_media":null,
        "image_versions2":{"candidates":[
          {"width":640,"height":1136,"url":"https://scontent.cdninstagram.com/big.jpg?oh=1&oe=2"},
          {"width":320,"height":568,"url":"https://scontent.cdninstagram.com/small.jpg"}]}
      }]}}}
      """;

  private static final String ALBUM_JSON =
      """
      {"data":{"xdt_api__v1__media__shortcode__web_info":{"items":[{
        "code":"ALBUM12345",
        "media_type":8,
        "user":{"username":"someone"},
        "caption":{"text":"앨범 캡션"},
        "carousel_media":[
          {"media_type":1,"image_versions2":{"candidates":[
            {"width":1080,"height":1080,"url":"https://scontent.cdninstagram.com/first.jpg"}]}},
          {"media_type":1,"image_versions2":{"candidates":[
            {"width":1080,"height":1080,"url":"https://scontent.cdninstagram.com/second.jpg"}]}}],
        "image_versions2":{"candidates":[
          {"width":150,"height":150,"url":"https://scontent.cdninstagram.com/cover.jpg"}]}
      }]}}}
      """;

  private static final String EMPTY_ITEMS_JSON =
      "{\"data\":{\"xdt_api__v1__media__shortcode__web_info\":{\"items\":[]}}}";

  /** 저장된 것을 들여다보는 가짜. 실제 MinIO 를 안 띄운다. */
  private static final class RecordingStorage implements ObjectStorage {
    private final List<String> keys = new ArrayList<>();
    private final List<String> contentTypes = new ArrayList<>();
    private byte[] lastBytes;

    @Override
    public String createPresignedUploadUrl(String objectKey, Duration expiry) {
      throw new UnsupportedOperationException();
    }

    @Override
    public void put(String objectKey, byte[] content, String contentType) {
      keys.add(objectKey);
      contentTypes.add(contentType);
      lastBytes = content;
    }

    @Override
    public String publicUrl(String objectKey) {
      return "https://minio.test/bucket/" + objectKey;
    }
  }

  /**
   * 이 파일의 테스트는 매핑·파싱·URL 판정을 본다 — <b>차단이 아닌 상태</b>가 그 전제다. 쿨다운 동작 자체는 {@code
   * InstagramUrlCrawlerResponseTest} 가 루프백 서버로 잰다.
   */
  private static final CrawlBlockCooldown NEVER_BLOCKED =
      new CrawlBlockCooldown() {
        @Override
        public boolean isBlocked(String site) {
          return false;
        }

        @Override
        public void markBlocked(String site) {}
      };

  /** {@code download()} 를 갈아끼운 크롤러. */
  private static InstagramUrlCrawler crawlerWith(
      Optional<ObjectStorage> storage, Downloader downloader) {
    return new InstagramUrlCrawler(
        new ObjectMapper(),
        storage,
        NEVER_BLOCKED,
        "26713194205046842",
        "https://www.instagram.com") {
      @Override
      Downloaded download(String imageUrl) throws Exception {
        return downloader.get(imageUrl);
      }
    };
  }

  private interface Downloader {
    InstagramUrlCrawler.Downloaded get(String url) throws Exception;
  }

  private static final Downloader OK_JPEG =
      url -> new InstagramUrlCrawler.Downloaded(new byte[] {1, 2, 3}, "image/jpeg");

  private final InstagramUrlCrawler plain =
      new InstagramUrlCrawler(
          new ObjectMapper(),
          Optional.empty(),
          NEVER_BLOCKED,
          "26713194205046842",
          "https://www.instagram.com");

  // ------------------------------------------------------------------ 지원 판정

  @ParameterizedTest
  @ValueSource(
      strings = {
        "https://www.instagram.com/p/DZb-UAhz4Iq/",
        "https://www.instagram.com/reel/DZb-UAhz4Iq/",
        "https://www.instagram.com/tv/DZb-UAhz4Iq/",
        "https://instagram.com/p/DZb-UAhz4Iq/?igsh=abc123"
      })
  void postUrlsAreClaimed(String url) {
    assertThat(plain.supports(URI.create(url))).isTrue();
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "https://www.instagram.com/workout_plz/", // 프로필 — 일반 크롤러로
        "https://www.instagram.com/explore/tags/부산/", // 태그 페이지
        "https://www.instagram.com/", // 홈
        "https://instagram.com.evil.test/p/ABC/" // 호스트 끝에 붙인 피싱성 주소
      })
  void nonPostUrlsAreLeftAlone(String url) {
    assertThat(plain.supports(URI.create(url))).isFalse();
  }

  // ------------------------------------------------------------------ shortcode = SSRF 방어선

  @Test
  void theShortcodeSurvivesShareTrackingParams() {
    // 인스타 앱의 공유 버튼이 ?igsh=... 를 붙인다 — 실사용에서 제일 흔한 형태다.
    assertThat(
            plain.extractShortcode(
                URI.create("https://www.instagram.com/reel/DZb-UAhz4Iq/?igsh=MXY")))
        .isEqualTo("DZb-UAhz4Iq");
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "https://www.instagram.com/p/../../evil/", // 경로 탈출
        "https://www.instagram.com/p//", // 빈 코드
        "https://www.instagram.com/p/a/", // 너무 짧다
        "https://www.instagram.com/p/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/", // 40자 — 너무 길다
        "https://www.instagram.com/p/abc@def/" // 알파벳 밖
      })
  void anythingThatIsNotAShortcodeIsRejected(String url) {
    // ⚠️ 사용자 입력으로 요청 URL 을 조립하므로 여기가 방어선이다.
    assertThatThrownBy(() -> plain.extractShortcode(URI.create(url)))
        .isInstanceOf(CrawlException.class);
  }

  // ------------------------------------------------------------------ 파싱

  @Test
  void theCaptionBecomesTheBody() {
    CrawlResult result = plain.toCrawlResult(SINGLE_VIDEO_JSON, "DZb-UAhz4Iq");

    assertThat(result.bodyText()).contains("딥워터 한달남았따").contains("래쉬가드 추천");
    assertThat(result.bodyText()).contains("@workout_plz");
    assertThat(result.source()).isEqualTo("instagram.com");
  }

  @Test
  void theTitleIsTheFirstLineOfTheCaption() {
    // 인스타 게시물에는 제목이 없다.
    assertThat(plain.toCrawlResult(SINGLE_VIDEO_JSON, "DZb-UAhz4Iq").title())
        .isEqualTo("딥워터 한달남았따");
  }

  @Test
  void aCaptionlessPostFallsBackToTheHandle() {
    // 사진만 올린 게시물이 흔하다 — 빈 본문으로 실패시키지 않는다.
    String json =
        """
        {"data":{"xdt_api__v1__media__shortcode__web_info":{"items":[{
          "user":{"username":"nocap"},"caption":null,"carousel_media":null,
          "image_versions2":{"candidates":[{"url":"https://cdn/x.jpg"}]}}]}}}
        """;

    CrawlResult result = plain.toCrawlResult(json, "X");

    assertThat(result.title()).isEqualTo("@nocap");
    assertThat(result.bodyText()).isEqualTo("@nocap");
  }

  @Test
  void aNullCarouselIsNotAnAlbum() {
    // ⚠️ 실제 응답에서 carousel_media 는 **앨범이 아니어도 키가 있고 값이 null** 이다(실측 확인).
    // "키가 있나"로 분기하면 앨범 가지로 잘못 빠져 미디어가 0개가 된다.
    RecordingStorage storage = new RecordingStorage();
    CrawlResult result =
        crawlerWith(Optional.of(storage), OK_JPEG).toCrawlResult(SINGLE_VIDEO_JSON, "DZb-UAhz4Iq");

    assertThat(result.thumbnail()).startsWith("https://minio.test/bucket/archive/instagram/");
    assertThat(storage.keys).hasSize(1);
  }

  @Test
  void anAlbumUsesItsFirstChild() {
    RecordingStorage storage = new RecordingStorage();
    List<String> requested = new ArrayList<>();
    InstagramUrlCrawler crawler =
        crawlerWith(
            Optional.of(storage),
            url -> {
              requested.add(url);
              return new InstagramUrlCrawler.Downloaded(new byte[] {9}, "image/jpeg");
            });

    crawler.toCrawlResult(ALBUM_JSON, "ALBUM12345");

    assertThat(requested).containsExactly("https://scontent.cdninstagram.com/first.jpg");
  }

  @Test
  void theLargestCandidateIsChosen() {
    List<String> requested = new ArrayList<>();
    crawlerWith(
            Optional.of(new RecordingStorage()),
            url -> {
              requested.add(url);
              return new InstagramUrlCrawler.Downloaded(new byte[] {1}, "image/jpeg");
            })
        .toCrawlResult(SINGLE_VIDEO_JSON, "DZb-UAhz4Iq");

    // candidates[0] 이 가장 크다(실측: 640x1136 → 320x568 내림차순).
    assertThat(requested).containsExactly("https://scontent.cdninstagram.com/big.jpg?oh=1&oe=2");
  }

  @Test
  void anEmptyItemsArrayIsAFailure() {
    // 비공개·삭제·연령제한이거나 doc_id 가 만료됐다.
    assertThatThrownBy(() -> plain.toCrawlResult(EMPTY_ITEMS_JSON, "X"))
        .isInstanceOf(CrawlException.class);
  }

  @Test
  void aLoginPageInsteadOfJsonIsAFailure() {
    // 차단되면 JSON 대신 HTML 이 온다 — 조용히 DONE 으로 저장하지 않는다.
    assertThatThrownBy(() -> plain.toCrawlResult("<!DOCTYPE html><html>...", "X"))
        .isInstanceOf(CrawlException.class);
  }

  // ------------------------------------------------------------------ 썸네일 보관

  @Test
  void theThumbnailIsStoredInOurBucketNotTheExpiringCdnUrl() {
    // 🔴 이 티켓의 핵심 결정. CDN URL 은 oh=/oe= 서명이 붙어 몇 시간이면 만료된다 —
    // 그대로 저장하면 하루 뒤 깨진 이미지가 된다.
    RecordingStorage storage = new RecordingStorage();

    CrawlResult result =
        crawlerWith(Optional.of(storage), OK_JPEG).toCrawlResult(SINGLE_VIDEO_JSON, "DZb-UAhz4Iq");

    assertThat(result.thumbnail()).doesNotContain("cdninstagram.com").doesNotContain("oe=");
    assertThat(storage.keys.get(0)).startsWith("archive/instagram/DZb-UAhz4Iq-").endsWith(".jpg");
    assertThat(storage.contentTypes).containsExactly("image/jpeg");
    assertThat(storage.lastBytes).containsExactly(1, 2, 3);
  }

  @Test
  void withoutMinioWeStoreNoThumbnailRatherThanAnExpiringUrl() {
    // minio.endpoint 미설정 환경. 만료될 URL 을 저장하느니 없는 편이 낫다.
    CrawlResult result = plain.toCrawlResult(SINGLE_VIDEO_JSON, "DZb-UAhz4Iq");

    assertThat(result.thumbnail()).isNull();
    assertThat(result.bodyText()).contains("딥워터 한달남았따"); // 본론은 살아 있다
  }

  @Test
  void aFailedDownloadDoesNotKillTheCrawl() {
    // 썸네일은 본론이 아니다 — 캡션이 본론이다.
    CrawlResult result =
        crawlerWith(
                Optional.of(new RecordingStorage()),
                url -> {
                  throw new java.io.IOException("CDN 타임아웃");
                })
            .toCrawlResult(SINGLE_VIDEO_JSON, "DZb-UAhz4Iq");

    assertThat(result.thumbnail()).isNull();
    assertThat(result.bodyText()).contains("딥워터 한달남았따");
  }

  @Test
  void aFailedUploadDoesNotKillTheCrawl() {
    ObjectStorage brokenStorage =
        new ObjectStorage() {
          @Override
          public String createPresignedUploadUrl(String objectKey, Duration expiry) {
            throw new UnsupportedOperationException();
          }

          @Override
          public void put(String objectKey, byte[] content, String contentType) {
            throw new IllegalStateException("MinIO 다운");
          }

          @Override
          public String publicUrl(String objectKey) {
            throw new UnsupportedOperationException();
          }
        };

    CrawlResult result =
        crawlerWith(Optional.of(brokenStorage), OK_JPEG)
            .toCrawlResult(SINGLE_VIDEO_JSON, "DZb-UAhz4Iq");

    assertThat(result.thumbnail()).isNull();
    assertThat(result.bodyText()).contains("딥워터 한달남았따");
  }

  // ------------------------------------------------------------------ 다운로드 대상 검증 (리뷰 M1)

  @ParameterizedTest
  @ValueSource(
      strings = {
        "https://scontent-ssn1-1.cdninstagram.com/v/t51/x.jpg",
        "https://cdninstagram.com/x.jpg",
        "https://scontent.xx.fbcdn.net/v/x.jpg"
      })
  void instagramCdnHostsAreAllowed(String url) {
    InstagramUrlCrawler.requireInstagramCdn(url); // 안 던지면 통과
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "https://cdninstagram.com.evil.test/x.jpg", // 접미사 위장
        "https://evil.test/x.jpg",
        "http://169.254.169.254/latest/meta-data/", // 클라우드 메타데이터
        "http://127.0.0.1:9000/modi/secret", // 우리 내부
        "file:///etc/passwd",
        "gopher://evil.test/x"
      })
  void anythingOutsideTheInstagramCdnIsRejected(String url) {
    // 🔴 초안은 호스트를 안 보고 리다이렉트까지 따라갔다. "대상이 인스타 응답이라 괜찮다"고 **말로**
    // 면제했는데, 이 티켓이 방금 archive/ 를 공개 읽기로 열었으므로 받아온 것이 무엇이든 우리
    // 도메인에서 공개 제공된다(리뷰 M1).
    assertThatThrownBy(() -> InstagramUrlCrawler.requireInstagramCdn(url))
        .isInstanceOf(CrawlException.class);
  }

  @Test
  void theStoredContentTypeIsOursNotTheRemoteOne() {
    // 원격 값을 그대로 넣으면 공개 버킷 오브젝트의 메타데이터를 외부가 정하게 된다.
    RecordingStorage storage = new RecordingStorage();
    crawlerWith(
            Optional.of(storage),
            url -> new InstagramUrlCrawler.Downloaded(new byte[] {1}, "image/webp; charset=utf-8"))
        .toCrawlResult(SINGLE_VIDEO_JSON, "DZb-UAhz4Iq");

    assertThat(storage.keys.get(0)).endsWith(".webp");
    assertThat(storage.contentTypes).containsExactly("image/webp"); // charset 이 안 딸려간다
  }

  @Test
  void heicAndWebpKeepTheirExtension() {
    // 가장 큰 후보가 .heic 인 경우가 있다(카카오톡 등 일부 클라이언트가 못 그린다).
    // 지금은 그대로 보관하되, 확장자는 실제 content-type 을 따른다.
    RecordingStorage storage = new RecordingStorage();
    crawlerWith(
            Optional.of(storage),
            url -> new InstagramUrlCrawler.Downloaded(new byte[] {1}, "image/webp"))
        .toCrawlResult(SINGLE_VIDEO_JSON, "DZb-UAhz4Iq");

    assertThat(storage.keys.get(0)).endsWith(".webp");
  }

  // ------------------------------------------------------- csrf 토큰 (2026-08-04)

  /**
   * 🔴 <b>{@code Set-Cookie} 만 보면 크롤러가 "이 JVM 의 첫 인스타 요청"에서만 동작한다.</b>
   *
   * <p>실측: 쿠키 없이 요청하면 {@code Set-Cookie: csrftoken} 이 오고, <b>그 쿠키를 달고 다시 요청하면 아무 Set-Cookie 도 안
   * 온다.</b> 20시간 떠 있던 개발 서버에서 인스타가 3연속 실패하고 재시작하니 복구된 게 이 증상이다.
   *
   * <p>본문의 {@code "csrf_token"} 값이 쿠키 값과 <b>문자 단위로 일치</b>한다는 것을 실측으로 확인했다.
   */
  @Nested
  class CsrfToken {

    /** 실제 페이지에서 옮긴 모양 — 값도 실측한 그것이다. */
    private static final String PAGE_HTML =
        """
        <script>requireLazy(["USIDMetadata"],function(m){m.setData(
        {"csrf_token":"M_OyA-dINujOnx9WtuXoz1","device_id":"XYZ"})});</script>
        """;

    @Test
    void theSetCookieValueWinsWhenItIsThere() {
      assertThat(InstagramUrlCrawler.csrfToken("from-cookie", PAGE_HTML)).isEqualTo("from-cookie");
    }

    @Test
    void thePageBodyIsUsedWhenInstagramSendsNoSetCookie() {
      // 이게 이 폴백의 존재 이유다 — 쿠키가 이미 실려 나간 요청의 응답이 이 모양이다.
      assertThat(InstagramUrlCrawler.csrfToken(null, PAGE_HTML))
          .isEqualTo("M_OyA-dINujOnx9WtuXoz1");
    }

    @Test
    void aBlankCookieIsTreatedAsAbsent() {
      // jsoup 이 빈 문자열을 줄 수도 있다 — null 만 보면 그 경우를 놓친다.
      assertThat(InstagramUrlCrawler.csrfToken("   ", PAGE_HTML))
          .isEqualTo("M_OyA-dINujOnx9WtuXoz1");
    }

    @Test
    void nothingIsFoundWhenBothAreMissing() {
      // 빈 문자열이어야 bootstrap 이 "게시물을 불러올 수 없는 링크예요"로 끊는다 —
      // 여기서 null 을 돌려주면 그 판정이 NPE 로 바뀐다.
      assertThat(InstagramUrlCrawler.csrfToken(null, "<html>로그인 페이지</html>")).isEmpty();
      assertThat(InstagramUrlCrawler.csrfToken("", "")).isEmpty();
    }

    @Test
    void anUnterminatedTokenIsNotHalfRead() {
      // 페이지가 상한에 잘렸을 때 반토막 토큰을 쓰면 GraphQL 이 조용히 로그인 페이지를 준다.
      assertThat(InstagramUrlCrawler.csrfToken(null, "{\"csrf_token\":\"M_OyA-dIN")).isEmpty();
    }
  }

  /**
   * 🔴 <b>쿠키와 헤더가 같은 csrf 값으로 나가야 한다.</b> 어긋나면 인스타는 로그인 HTML 을 준다 — 우리 눈에는 "공개된 게시물만 등록할 수 있어요" 로만
   * 보인다.
   *
   * <p>2026-08-04 리뷰(P1-1)가 잡은 구멍: `Set-Cookie: csrftoken=`(빈 값)이 오면 {@code csrfToken()} 은 본문 폴백으로
   * 넘어가는데 {@code putIfAbsent} 는 맵에 이미 있는 빈 값을 안 덮었다.
   */
  @Nested
  class GraphqlCookies {

    @Test
    void anEmptySetCookieValueIsOverwrittenWithTheTokenWeWillSend() {
      // 이게 리뷰가 재현한 그 경로다 — 덮지 않으면 쿠키 `csrftoken=` · 헤더 `PAGE-TOKEN` 로 어긋난다.
      Map<String, String> cookies =
          InstagramUrlCrawler.graphqlCookies(Map.of("csrftoken", "", "mid", "ABC"), "PAGE-TOKEN");

      assertThat(cookies).containsEntry("csrftoken", "PAGE-TOKEN");
    }

    @Test
    void theOtherCookiesSurvive() {
      // `mid` 등은 인스타가 세션을 알아보는 데 쓴다 — 우리가 지울 이유가 없다.
      Map<String, String> cookies =
          InstagramUrlCrawler.graphqlCookies(Map.of("mid", "ABC", "ig_did", "XYZ"), "TOK");

      assertThat(cookies).containsEntry("mid", "ABC").containsEntry("ig_did", "XYZ");
    }

    @Test
    void aMissingCookieIsAdded() {
      // Set-Cookie 가 아예 안 온 경우(쿠키를 이미 들고 나간 요청의 응답).
      assertThat(InstagramUrlCrawler.graphqlCookies(Map.of(), "TOK"))
          .containsEntry("csrftoken", "TOK");
    }

    @Test
    void theCallerMapIsNotMutated() {
      // jsoup 의 응답 쿠키 맵을 우리가 고쳐 쓰면 같은 응답을 다시 읽는 쪽이 영향을 받는다.
      Map<String, String> original = new LinkedHashMap<>(Map.of("csrftoken", "FROM-COOKIE"));
      InstagramUrlCrawler.graphqlCookies(original, "OTHER");

      assertThat(original).containsEntry("csrftoken", "FROM-COOKIE");
    }
  }

  @Nested
  class GraphqlHeaders {

    private final InstagramUrlCrawler.Bootstrap bootstrap =
        new InstagramUrlCrawler.Bootstrap("LSD-TOKEN", "CSRF-TOKEN", Map.of());

    @Test
    void 헤더_순서가_고정이다() {
      // 🔴 이 테스트의 존재 이유는 `Map.of` 로 되돌아가는 것을 막는 것이다. `Map.of` 는 반복 순서가
      // **JVM 기동마다 달라져서**, 같은 요청이 기동마다 다른 헤더 순서로 나갔다(2026-08-05 실측).
      // 외부 안티봇 엔드포인트로 나가는 요청이 비결정적인 것 자체가 결함이다.
      assertThat(InstagramUrlCrawler.graphqlHeaders(bootstrap, "https://www.instagram.com/p/AB/"))
          .containsExactly(
              entry("X-IG-App-ID", "936619743392459"),
              entry("X-FB-LSD", "LSD-TOKEN"),
              entry("X-CSRFToken", "CSRF-TOKEN"),
              entry("X-FB-Friendly-Name", "PolarisPostRootQuery"),
              entry("X-Requested-With", "XMLHttpRequest"),
              entry("Origin", "https://www.instagram.com"),
              entry("Referer", "https://www.instagram.com/p/AB/"),
              entry("Sec-Fetch-Site", "same-origin"),
              entry("Sec-Fetch-Mode", "cors"),
              entry("Sec-Fetch-Dest", "empty"),
              entry("Accept", "*/*"),
              entry("Accept-Language", "en-US,en;q=0.9"));
    }

    @Test
    void 같은_입력이면_언제나_같은_순서다() {
      // 한 JVM 안에서 Map.of 는 순서가 고정이라 이 단언만으로는 회귀를 못 잡는다 — 위 테스트가
      // 순서 자체를 못 박는 쪽이고, 이건 호출마다 흔들리지 않는다는 것만 본다.
      List<String> first =
          List.copyOf(InstagramUrlCrawler.graphqlHeaders(bootstrap, "https://x.test/").keySet());
      List<String> second =
          List.copyOf(InstagramUrlCrawler.graphqlHeaders(bootstrap, "https://x.test/").keySet());

      assertThat(first).isEqualTo(second);
    }
  }
}
