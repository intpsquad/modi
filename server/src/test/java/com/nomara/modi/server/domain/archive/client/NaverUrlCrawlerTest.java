package com.nomara.modi.server.domain.archive.client;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URI;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * 네이버 크롤러의 <b>주소 판정부</b> — 어떤 링크를 맡고 어떤 place id 를 뽑는가. 네트워크를 타지 않는다.
 *
 * <p>응답을 어떻게 읽는지는 {@link NaverUrlCrawlerResponseTest} 가 {@code crawl()} 전체를 돌려서 본다.
 *
 * <p>이 파일이 지키는 것은 <b>SSRF 방어선</b>이다 — {@code findPlaceId} 로 뽑은 값이 그대로 요청 URL 이 된다.
 */
class NaverUrlCrawlerTest {

  private final NaverUrlCrawler crawler =
      new NaverUrlCrawler(
          new ObjectMapper(),
          new JsoupUrlCrawler(new UrlSafetyValidator()),
          "naver.me",
          "https://m.place.naver.com/place",
          "naver.com,naver.me");

  // ------------------------------------------------------------------ 지원 판정

  @ParameterizedTest
  @ValueSource(
      strings = {
        "https://naver.me/FoEJcO1X",
        "https://map.naver.com/p/entry/place/1810277002?lng=126.97&lat=37.53",
        // 🔴 지도 **앱** 공유 버튼이 주는 모양 — 경로에 장소가 없고 pinId 에 있다(2026-08-05 실측).
        "https://map.naver.com/?lat=37.5032828&app=Y&pinId=1340737588&pinType=site&menu=location",
        "https://m.place.naver.com/restaurant/1810277002/home",
        "https://m.place.naver.com/place/1810277002/home",
        "https://pcmap.place.naver.com/restaurant/1810277002/home"
      })
  void naverPlaceAndShortLinksAreClaimed(String url) {
    assertThat(crawler.supports(URI.create(url))).isTrue();
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        // 🔴 아래 넷은 **두 조각 + 숫자** 라 호스트를 안 보면 전부 장소로 오인된다(2026-08-05 리뷰가
        // 재현: blog 글번호 `223456789012` 를 place id 로 뽑았다). 전부 일반 크롤러 몫이다.
        "https://blog.naver.com/naver_diary/223456789012",
        "https://m.blog.naver.com/naver_diary/223456789012",
        "https://cafe.naver.com/joonggonara/123456",
        "https://tv.naver.com/v/12345678",
        "https://map.naver.com/p/search/%EB%A7%9B%EC%A7%91", // 검색 결과엔 장소 id 가 없다
        "https://map.naver.com/", // 지도 홈
        "https://naver.me.evil.test/FoEJcO1X", // 호스트 끝에 붙인 피싱성 주소
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
      })
  void everythingElseIsLeftAlone(String url) {
    // 맡고 나서 던지면 일반 크롤러가 시도해볼 기회조차 없어진다 — 유튜브·인스타와 같은 규칙.
    assertThat(crawler.supports(URI.create(url))).isFalse();
  }

  // ------------------------------------------------------------------ place id = SSRF 방어선

  @ParameterizedTest
  @CsvSource({
    "https://map.naver.com/p/entry/place/1810277002?lng=126.97&lat=37.53, 1810277002",
    "https://map.naver.com/p/entry/place/1810277002/home, 1810277002",
    "https://m.place.naver.com/place/1810277002/home, 1810277002",
    "https://m.place.naver.com/restaurant/1810277002/home, 1810277002",
    "https://pcmap.place.naver.com/restaurant/1810277002/home, 1810277002",
    // 🔴 지도 앱 공유(2026-08-05 사용자 신고로 발견). 실측한 그 주소에서 좌표·title 만 뺐다 —
    // CsvSource 는 쉼표로 칸을 가르는데 퍼센트 인코딩된 한글 title 에는 쉼표가 없어 그대로 둬도
    // 되지만, 이 테스트가 재는 것은 pinId 하나라 짧게 둔다.
    "https://map.naver.com/?lat=37.5032828&app=Y&pinId=1340737588&pinType=site, 1340737588",
    // pinId 가 첫 파라미터인 경우도 같아야 한다(문자열 위치에 기대지 않는다).
    "https://map.naver.com/?pinId=1340737588&lat=37.5032828, 1340737588",
    // 경로형이 있으면 그쪽이 이긴다 — 둘 다 있을 때 조용히 갈리지 않도록 못 박는다.
    "https://map.naver.com/p/entry/place/1810277002?pinId=1340737588, 1810277002",
    // 🔴 title 안의 %26 이 진짜 pinId 를 밀어내면 안 된다. getQuery() 를 쓰면 여기서 999 가 나온다
    // — 퍼센트 디코딩이 먼저 일어나 칸이 어긋나기 때문이다(SSRF 는 아니지만 엉뚱한 가게가 저장된다).
    "https://map.naver.com/?title=a%26pinId%3D999&pinId=1340737588, 1340737588"
  })
  void everyPlaceUrlFormResolvesToTheSameId(String url, String expected) {
    assertThat(crawler.findPlaceId(URI.create(url))).isEqualTo(expected);
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "https://m.place.naver.com/restaurant/..%2F..%2Fevil/home", // 경로 탈출
        "https://m.place.naver.com/restaurant/18102770021810277002181027700218/home", // 20자 초과
        "https://m.place.naver.com/restaurant/abc/home", // 숫자가 아님
        "https://m.place.naver.com/restaurant/181027700a/home", // 섞여 있음
        "https://map.naver.com/p/search/food", // place 조각 자체가 없음
        "https://m.place.naver.com/restaurant", // 조각이 하나뿐
        // 🔴 pinId 도 그대로 믿지 않는다 — 이 값이 요청 URL 로 조립된다.
        "https://map.naver.com/?pinId=..%2F..%2Fevil&pinType=site",
        "https://map.naver.com/?pinId=abc&pinType=site",
        "https://map.naver.com/?pinId=&pinType=site",
        "https://map.naver.com/?pinId=13407375881340737588134073758813&pinType=site", // 20자 초과
        // pinId 를 닮은 다른 파라미터에 걸리면 안 된다.
        "https://map.naver.com/?myPinId=1340737588",
        // 장소 호스트가 아니면 pinId 가 있어도 뽑지 않는다.
        "https://blog.naver.com/?pinId=1340737588",
        // 🔴 장소 호스트가 아니면 모양이 맞아도 뽑지 않는다.
        "https://blog.naver.com/naver_diary/223456789012",
        "https://cafe.naver.com/joonggonara/123456"
      })
  void anythingThatIsNotANumericIdYieldsNothing(String url) {
    // ⚠️ 이 값이 그대로 요청 URL 로 조립된다 — 느슨하면 서버가 임의 주소를 부른다.
    assertThat(crawler.findPlaceId(URI.create(url))).isEmpty();
  }
}
