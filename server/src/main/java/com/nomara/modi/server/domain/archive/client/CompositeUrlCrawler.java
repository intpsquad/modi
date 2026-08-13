package com.nomara.modi.server.domain.archive.client;

import com.nomara.modi.server.domain.archive.exception.CrawlException;
import java.net.URI;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Component;

/**
 * 호스트를 보고 전용 크롤러에 넘기고, 맡을 곳이 없으면 일반 {@link JsoupUrlCrawler}로 보낸다.
 *
 * <p>{@code @Primary}인 이유는 호출부({@code ArchiveItemService}·{@code ArchiveCrawlProcessor})가 {@code
 * UrlCrawler}를 주입받고 있어서다 — <b>호출부를 한 줄도 안 고치고</b> 이 디스패처가 그 자리에 들어간다.
 */
@Primary
@Component
public class CompositeUrlCrawler implements UrlCrawler {

  private static final Logger log = LoggerFactory.getLogger(CompositeUrlCrawler.class);

  private final List<SiteUrlCrawler> siteCrawlers;
  private final JsoupUrlCrawler fallback;

  public CompositeUrlCrawler(List<SiteUrlCrawler> siteCrawlers, JsoupUrlCrawler fallback) {
    this.siteCrawlers = List.copyOf(siteCrawlers);
    this.fallback = fallback;
  }

  /**
   * 🔴 <b>예상 못 한 예외를 {@link CrawlException} 으로 감싼다</b>(2026-08-03 리뷰 M2). 크롤러가 그 밖의 {@code
   * RuntimeException} 을 던지면 양쪽 호출부가 둘 다 나쁘게 반응한다.
   *
   * <ul>
   *   <li><b>동기</b>({@code ArchiveItemService}): {@code CrawlException} 만 잡아 400 으로 바꾸므로 나머지는
   *       <b>HTTP 500</b> 이 된다 — 사용자는 원인 모를 오류를 본다.
   *   <li><b>비동기</b>({@code ArchiveCrawlProcessor}): 일반 {@code catch} 가 {@code markCrawlFailed()} 를
   *       안 부르므로 항목이 <b>영구 PENDING</b> 으로 남는다 — 로그 한 줄 말고는 흔적이 없다.
   * </ul>
   *
   * <p>여기서 감싸면 둘 다 "크롤링 실패"라는 정상 경로로 떨어진다. 처리기의 일반 {@code catch} 는 원래 목적(크롤링 도중 항목이 삭제돼 FK 위반이 나는
   * 경우)에만 남는다.
   */
  @Override
  public CrawlResult crawl(String url) {
    UrlCrawler crawler = pick(url);
    try {
      return crawler.crawl(url);
    } catch (CrawlException e) {
      throw e;
    } catch (RuntimeException e) {
      log.error("크롤러가 예상 못 한 예외를 던졌다({})", crawler.getClass().getSimpleName(), e);
      // 🔴 **일부러 retryable 이 아니다**(2026-08-06). 문구는 "다시 시도해 주세요" 지만, 여기 오는 것은
      // 상대의 일시적 상태가 아니라 **우리 쪽 버그**다(NPE·파싱 오류 등). 세 번 더 걸어도 같은 예외가
      // 나면서 외부 사이트만 더 때리고, 사용자에게는 실패 확정이 1시간 늦게 온다.
      throw new CrawlException("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }
  }

  /**
   * 맡을 크롤러를 고른다.
   *
   * <p><b>URI 파싱 실패를 여기서 처리하지 않는다</b> — 일반 크롤러로 넘겨 {@code validateUrl}이 기존과 <b>같은 문구로</b> 거절하게 한다.
   * 여기서 따로 던지면 잘못된 주소의 에러 메시지가 이 티켓 전후로 달라진다.
   */
  UrlCrawler pick(String url) {
    URI uri;
    try {
      uri = URI.create(url);
    } catch (IllegalArgumentException e) {
      return fallback;
    }
    if (uri.getHost() == null) {
      return fallback;
    }
    for (SiteUrlCrawler crawler : siteCrawlers) {
      if (supportsSafely(crawler, uri)) {
        log.debug("전용 크롤러로 보낸다: {} → {}", uri.getHost(), crawler.getClass().getSimpleName());
        return crawler;
      }
    }
    return fallback;
  }

  /**
   * 판정이 터져도 등록을 막지 않는다 — 일반 크롤러로 떨어뜨린다.
   *
   * <p>{@code supports}는 "예외를 던지지 않는다"가 계약이지만({@link SiteUrlCrawler}), 계약을 어긴 구현 하나가 <b>블로그
   * 링크까지</b> 못 넣게 만드는 것이 이 폴백이 막는 것이다. {@code _map_categories_safely}(AI 서버)와 같은 정책 — 나중에 얹은 층이 본체를
   * 잃게 하면 안 된다.
   */
  private boolean supportsSafely(SiteUrlCrawler crawler, URI uri) {
    try {
      return crawler.supports(uri);
    } catch (RuntimeException e) {
      log.warn("크롤러 지원 판정 실패({}) — 일반 크롤러로 넘긴다", crawler.getClass().getSimpleName(), e);
      return false;
    }
  }
}
