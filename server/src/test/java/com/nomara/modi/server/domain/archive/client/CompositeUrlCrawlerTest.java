package com.nomara.modi.server.domain.archive.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import java.net.URI;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * 호스트별 디스패처 — <b>네트워크를 타지 않는다</b>. {@code pick()}이 고른 크롤러만 본다.
 *
 * <p><b>여기서 제일 중요한 것은 "기존 블로그가 그대로 간다"</b>이다. 전용 크롤러가 늘어날 때마다 일반 경로를 잠식할 위험이 생기는데, 그건 조용히 일어난다 —
 * 블로그 등록이 갑자기 유튜브 크롤러로 가도 예외 문구만 조금 다를 뿐이라 눈치채기 어렵다.
 */
class CompositeUrlCrawlerTest {

  private final JsoupUrlCrawler fallback = new JsoupUrlCrawler(new UrlSafetyValidator());
  // 디스패처가 보는 것은 supports() 뿐이라 키·주소는 안 쓰인다(인스타의 "0" 과 같은 취급).
  private final YouTubeUrlCrawler youtube =
      new YouTubeUrlCrawler(new ObjectMapper(), "", "http://localhost:1/never-called", 1, 1);
  private final InstagramUrlCrawler instagram =
      new InstagramUrlCrawler(
          new ObjectMapper(),
          Optional.empty(),
          // 디스패처는 supports() 만 보므로 쿨다운은 불리지 않는다 — 불리면 여기서 터진다.
          new CrawlBlockCooldown() {
            @Override
            public boolean isBlocked(String site) {
              throw new AssertionError("디스패처가 쿨다운을 봐서는 안 된다");
            }

            @Override
            public void markBlocked(String site) {
              throw new AssertionError("디스패처가 쿨다운을 건드려서는 안 된다");
            }
          },
          "0",
          "https://www.instagram.com");
  private final NaverUrlCrawler naver =
      new NaverUrlCrawler(
          new ObjectMapper(),
          fallback,
          "naver.me",
          "https://m.place.naver.com/place",
          "naver.com,naver.me");

  private final CompositeUrlCrawler dispatcher =
      new CompositeUrlCrawler(List.of(youtube, instagram, naver), fallback);

  @Test
  void youtubeGoesToTheYoutubeCrawler() {
    assertThat(dispatcher.pick("https://youtu.be/dQw4w9WgXcQ")).isSameAs(youtube);
    assertThat(dispatcher.pick("https://www.youtube.com/shorts/dQw4w9WgXcQ")).isSameAs(youtube);
  }

  @Test
  void instagramPostsGoToTheInstagramCrawler() {
    assertThat(dispatcher.pick("https://www.instagram.com/p/DZb-UAhz4Iq/")).isSameAs(instagram);
    assertThat(dispatcher.pick("https://www.instagram.com/reel/DZb-UAhz4Iq/?igsh=x"))
        .isSameAs(instagram);
  }

  @Test
  void naverShortLinksAndPlacePagesGoToTheNaverCrawler() {
    assertThat(dispatcher.pick("https://naver.me/FoEJcO1X")).isSameAs(naver);
    assertThat(dispatcher.pick("https://m.place.naver.com/restaurant/1810277002/home"))
        .isSameAs(naver);
    assertThat(dispatcher.pick("https://map.naver.com/p/entry/place/1810277002?lng=126.97"))
        .isSameAs(naver);
  }

  @Test
  void everythingElseKeepsGoingToTheGeneralCrawler() {
    // 회귀 방어선 — 이 티켓 전에 되던 것이 그대로 되어야 한다.
    // 🔴 네이버 크롤러가 생겼다고 **블로그까지 가로채면 안 된다** — 그쪽은 일반 크롤러가 잘 하고 있다.
    assertThat(dispatcher.pick("https://blog.naver.com/x/223")).isSameAs(fallback);
    assertThat(dispatcher.pick("https://m.blog.naver.com/x/223")).isSameAs(fallback);
    assertThat(dispatcher.pick("https://news.naver.com/article/001/1")).isSameAs(fallback);
    assertThat(dispatcher.pick("https://map.naver.com/p/search/food")).isSameAs(fallback);
    assertThat(dispatcher.pick("https://example.com/post/1")).isSameAs(fallback);
    // 인스타라도 **게시물이 아니면** 일반 크롤러다 — 프로필 페이지는 og 태그로 충분하다.
    assertThat(dispatcher.pick("https://www.instagram.com/workout_plz/")).isSameAs(fallback);
  }

  @Test
  void aMalformedUrlIsLeftToTheGeneralCrawler() {
    // 여기서 따로 던지면 잘못된 주소의 에러 문구가 이 티켓 전후로 달라진다 —
    // JsoupUrlCrawler.validateUrl 이 기존과 같은 문구로 거절하게 둔다.
    assertThat(dispatcher.pick("not a url")).isSameAs(fallback);
    assertThat(dispatcher.pick("mailto:someone@example.com")).isSameAs(fallback);
    assertThat(dispatcher.pick("")).isSameAs(fallback);
  }

  @Test
  void aCrawlerThatThrowsWhileJudgingDoesNotBlockRegistration() {
    // supports() 의 계약은 "던지지 않는다"지만, 계약을 어긴 구현 하나가 **블로그 링크까지** 못 넣게
    // 만드는 것을 막는다. 나중에 얹은 층이 본체를 잃게 하면 안 된다.
    SiteUrlCrawler broken =
        new SiteUrlCrawler() {
          @Override
          public boolean supports(URI uri) {
            throw new IllegalStateException("판정 중 터짐");
          }

          @Override
          public CrawlResult crawl(String url) {
            throw new UnsupportedOperationException();
          }
        };

    CompositeUrlCrawler withBroken = new CompositeUrlCrawler(List.of(broken, youtube), fallback);

    assertThat(withBroken.pick("https://blog.naver.com/x/223")).isSameAs(fallback);
    assertThat(withBroken.pick("https://youtu.be/dQw4w9WgXcQ")).isSameAs(youtube);
  }

  @Test
  void theFirstMatchingCrawlerWins() {
    SiteUrlCrawler claimsEverything =
        new SiteUrlCrawler() {
          @Override
          public boolean supports(URI uri) {
            return true;
          }

          @Override
          public CrawlResult crawl(String url) {
            throw new UnsupportedOperationException();
          }
        };

    assertThat(
            new CompositeUrlCrawler(List.of(claimsEverything, youtube), fallback)
                .pick("https://youtu.be/dQw4w9WgXcQ"))
        .isSameAs(claimsEverything);
  }

  @Test
  void anUnexpectedRuntimeExceptionBecomesACrawlException() {
    // 🔴 감싸지 않으면 동기 등록은 **HTTP 500**(ArchiveItemService 는 CrawlException 만 400 으로
    // 바꾼다), 비동기는 **영구 PENDING**(ArchiveCrawlProcessor 의 일반 catch 가 markCrawlFailed 를
    // 안 부른다)이 된다. 둘 다 로그 한 줄 말고는 흔적이 없다(2026-08-03 리뷰 M2).
    SiteUrlCrawler boom =
        new SiteUrlCrawler() {
          @Override
          public boolean supports(URI uri) {
            return true;
          }

          @Override
          public CrawlResult crawl(String url) {
            throw new NumberFormatException("For input string: \"ZZZZ\" under radix 16");
          }
        };

    assertThatThrownBy(
            () -> new CompositeUrlCrawler(List.of(boom), fallback).crawl("https://example.com/x"))
        .isInstanceOf(CrawlException.class)
        .hasCauseInstanceOf(NumberFormatException.class);
  }

  @Test
  void aCrawlExceptionPassesThroughUnwrapped() {
    // 감싸기가 원래 메시지를 잡아먹으면 안 된다 — 사용자에게 보이는 문구가 그것이다.
    SiteUrlCrawler picky =
        new SiteUrlCrawler() {
          @Override
          public boolean supports(URI uri) {
            return true;
          }

          @Override
          public CrawlResult crawl(String url) {
            throw new CrawlException("공개된 게시물만 등록할 수 있어요");
          }
        };

    assertThatThrownBy(
            () -> new CompositeUrlCrawler(List.of(picky), fallback).crawl("https://example.com/x"))
        .isInstanceOf(CrawlException.class)
        .hasMessage("공개된 게시물만 등록할 수 있어요")
        .hasNoCause();
  }

  @Test
  void withNoSiteCrawlersEverythingGoesToTheFallback() {
    assertThat(new CompositeUrlCrawler(List.of(), fallback).pick("https://youtu.be/dQw4w9WgXcQ"))
        .isSameAs(fallback);
  }
}
