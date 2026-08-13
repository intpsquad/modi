package com.nomara.modi.server.domain.archive.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import java.net.URI;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * 유튜브 크롤러의 <b>주소 판정부</b> — 어떤 링크를 맡고 어떤 id 를 뽑는가. 네트워크를 타지 않는다.
 *
 * <p><b>응답을 어떻게 읽는지는 여기 없다</b> — 그건 {@link YouTubeUrlCrawlerResponseTest} 가 {@code crawl()} 전체를 돌려서
 * 본다. 그렇게 나눈 이유가 그 파일 주석에 있다(2026-08-04: 파싱부만 테스트하다 이음매가 하루 동안 깨진 채로 있었다).
 *
 * <p>이 파일이 지키는 것은 <b>SSRF 방어선</b>이다. 2026-08-05 에 HTML 스크래핑이 Data API 호출로 바뀌면서 id 가 붙는 곳이 {@code
 * youtube.com/watch?v=} 에서 {@code googleapis.com} 의 쿼리 파라미터로 옮겨갔지만, <b>사용자 입력으로 요청을 조립한다는 사실은
 * 그대로다</b> — 검증이 느슨하면 서버가 임의 주소를 부른다.
 */
class YouTubeUrlCrawlerTest {

  /** 판정부는 네트워크를 안 타므로 키·주소·타임아웃 전부 쓰이지 않는다. */
  private final YouTubeUrlCrawler crawler =
      new YouTubeUrlCrawler(new ObjectMapper(), "", "http://localhost:1/never-called", 1, 1);

  // ------------------------------------------------------------------ 지원 판정

  @ParameterizedTest
  @ValueSource(
      strings = {
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ"
      })
  void youtubeHostsAreClaimed(String url) {
    assertThat(crawler.supports(URI.create(url))).isTrue();
  }

  @Test
  void otherHostsAreLeftToTheGeneralCrawler() {
    assertThat(crawler.supports(URI.create("https://blog.naver.com/x/1"))).isFalse();
    // 호스트 끝에 유튜브가 붙은 피싱성 주소를 가로채면 안 된다.
    assertThat(crawler.supports(URI.create("https://youtube.com.evil.test/watch?v=x"))).isFalse();
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "https://www.youtube.com/playlist?list=PLxxxxxxxxxx",
        "https://www.youtube.com/@RickAstleyYT",
        "https://www.youtube.com/"
      })
  void youtubePagesWithoutAVideoIdAreNotClaimed(String url) {
    // 맡고 나서 던지면 일반 크롤러가 시도해볼 기회조차 없어진다 — 인스타(`/p/` 일 때만 맡는다)와
    // 같은 규칙으로 맞췄다(리뷰 L1).
    assertThat(crawler.supports(URI.create(url))).isFalse();
  }

  // ------------------------------------------------------------------ id 추출 = SSRF 방어선

  @ParameterizedTest
  @ValueSource(
      strings = {
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/watch?app=desktop&v=dQw4w9WgXcQ&t=30s",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abcdef",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ"
      })
  void everyUrlFormResolvesToTheSameVideoId(String url) {
    // 네 형태가 전부 같은 id 로 모이지 않으면 "id 하나로 API 를 부른다"는 설계가 성립하지 않는다.
    assertThat(crawler.extractVideoId(URI.create(url))).isEqualTo("dQw4w9WgXcQ");
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "https://youtu.be/../../evil", // 경로 탈출
        "https://youtu.be/dQw4w9WgXcQextra", // 11자 초과
        "https://youtu.be/short", // 11자 미만
        "https://youtu.be/dQw4w9WgXc%2F", // 인코딩된 슬래시
        "https://www.youtube.com/watch?v=dQw4w9WgXc@", // 알파벳 밖
        "https://www.youtube.com/", // id 없음
        "https://www.youtube.com/@RickAstleyYT" // 채널 페이지
      })
  void anythingThatIsNotAnElevenCharIdIsRejected(String url) {
    // ⚠️ 여기가 이 클래스의 SSRF 방어선이다 — 사용자 입력이 그대로 요청 파라미터가 되기 때문이다.
    assertThatThrownBy(() -> crawler.extractVideoId(URI.create(url)))
        .isInstanceOf(CrawlException.class);
  }

  @Test
  void aTrailingPathSegmentDoesNotSmuggleAnything() {
    // `/shorts/{id}/../../evil` 처럼 뒤에 붙여도 첫 조각만 보고 나머지는 검증에서 걸러진다.
    assertThat(crawler.extractVideoId(URI.create("https://www.youtube.com/shorts/dQw4w9WgXcQ/")))
        .isEqualTo("dQw4w9WgXcQ");
  }
}
