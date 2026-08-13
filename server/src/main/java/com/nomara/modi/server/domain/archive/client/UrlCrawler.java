package com.nomara.modi.server.domain.archive.client;

/** 아카이브 자료 등록(S-25-C)의 링크 크롤링 — specs/0010-아카이브-탭.md. */
public interface UrlCrawler {

  /**
   * @throws CrawlException 크롤링에 실패했거나(네트워크/타임아웃/파싱) 주소가 허용되지 않을 때(SSRF 방어)
   */
  CrawlResult crawl(String url);
}
