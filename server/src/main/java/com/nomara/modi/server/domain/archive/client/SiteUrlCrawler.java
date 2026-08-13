package com.nomara.modi.server.domain.archive.client;

import java.net.URI;

/**
 * 특정 사이트 전용 크롤러. 일반 {@link JsoupUrlCrawler}로는 본문이 안 나오는 곳 — 페이지가 JS 껍데기라 필요한 것이 {@code og:} 메타태그나
 * 별도 API에만 있는 사이트를 위한 것이다.
 *
 * <p><b>왜 일반 크롤러를 고치지 않는가</b>: {@code JsoupUrlCrawler}는 임의 외부 URL을 상대하는 자리라 SSRF 방어·노이즈 제거·본문 루트
 * 판정이 실측으로 다듬어져 있다(EXPERIMENTS #12). 거기에 사이트별 분기를 넣으면 블로그 크롤링이 회귀할 위험을 지는데, 얻는 것은 없다.
 *
 * <p><b>⚠️ 구현체는 URL을 직접 조립하게 된다</b>(예: {@code youtu.be/{id}} → {@code
 * www.youtube.com/watch?v={id}}). 일반 크롤러의 SSRF 방어(사설 IP 차단)를 안 타는 대신 <b>호스트가 고정되고 id/코드가 엄격히 검증되는
 * 것</b>이 방어다. 검증을 느슨하게 하면 서버가 임의 주소를 부르게 된다 — 각 구현체의 검증 정규식이 그 방어선이다.
 */
public interface SiteUrlCrawler extends UrlCrawler {

  /**
   * 이 크롤러가 맡을 주소인가. {@code false}면 {@link CompositeUrlCrawler}가 다음 후보로 넘어간다.
   *
   * <p><b>여기서 예외를 던지지 않는다.</b> 지원 여부 판정일 뿐이고, 실제 실패는 {@code crawl}에서 {@code CrawlException}으로 낸다 —
   * 판정 단계에서 던지면 뒤 후보와 일반 크롤러까지 못 가본 채 등록이 막힌다.
   */
  boolean supports(URI uri);
}
