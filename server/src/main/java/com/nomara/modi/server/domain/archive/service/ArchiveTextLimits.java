package com.nomara.modi.server.domain.archive.service;

/**
 * 아카이브 자료 텍스트의 저장 상한. 동기 등록({@code ArchiveItemService})과 크롤링 비동기 반영({@code ArchiveCrawlProcessor})이
 * <b>같은 값을 쓰도록</b> 한곳에 모았다.
 *
 * <p>비동기 경로에는 원래 상한이 없어서, 255자를 넘는 {@code og:title}이 오면 {@code title VARCHAR(255) NOT NULL}에
 * INSERT가 실패했다.
 */
final class ArchiveTextLimits {

  /** {@code archive_items.title} 컬럼 폭과 같다. */
  static final int MAX_TITLE = 255;

  /** {@code body_text}는 TEXT라 DB 제약은 없지만, 프롬프트 입력이므로 여기서 끊는다. */
  static final int MAX_BODY_TEXT = 20_000;

  /** 텍스트 공유에서 본문 앞부분을 제목으로 쓸 때의 길이. */
  static final int TEXT_TITLE_PREVIEW = 50;

  /** {@code archive_items.url} 컬럼 폭과 같다(초과 시 400). */
  static final int MAX_URL_INPUT = 2048;

  /** 요청 본문으로 받아들이는 텍스트의 상한(초과 시 400). */
  static final int MAX_TEXT_INPUT = 50_000;

  /** {@code archive_items.thumbnail} 컬럼 폭과 같다. */
  static final int MAX_THUMBNAIL = 1024;

  /** {@code archive_items.source} 컬럼 폭과 같다. 값은 호스트명이라 실제로는 훨씬 짧다. */
  static final int MAX_SOURCE = 255;

  /**
   * {@code archive_items.summary} 컬럼 폭과 같다. 프롬프트는 300자 이내를 요구하므로(2026-08-04 에 200자에서 올렸다) 이 값은 모델이
   * 그걸 넘겼을 때의 여유분이다 — 요약은 잘려도 뜻이 남으므로 {@code nullIfTooLong}이 아니라 {@code truncate}를 쓴다.
   */
  static final int MAX_SUMMARY = 500;

  /** {@code archive_items.memo} 컬럼 폭과 같다 — 사용자가 자료에 남기는 개인 메모(2026-08-06 도입). */
  static final int MAX_MEMO = 500;

  /**
   * {@code archive_item_comments.body} 컬럼 폭과 같다(2026-08-08,
   * docs/backend/archive-comments-handoff.md). 핸드오프 문서에 구체적인 수치가 없어 {@link #MAX_MEMO}와 같은 값을 저리스크
   * 기본값으로 정했다.
   */
  static final int MAX_COMMENT_BODY = 500;

  private ArchiveTextLimits() {}

  /**
   * {@code max}자를 넘으면 잘라낸다. {@code null}은 그대로 통과시킨다.
   *
   * <p>서로게이트 페어(이모지처럼 char 두 개로 이뤄진 문자)를 경계에서 쪼개지 않는다 — 고아 서로게이트가 남으면 UTF-8 인코딩 단계에서 터진다.
   */
  static String truncate(String text, int max) {
    if (text == null || text.length() <= max) {
      return text;
    }
    int end = Character.isHighSurrogate(text.charAt(max - 1)) ? max - 1 : max;
    return text.substring(0, end);
  }

  /**
   * {@code max}자를 넘으면 {@code null}로 만든다. <b>잘라내면 값 자체가 망가지는 것</b>(썸네일 URL 등)에 쓴다 — 잘린 URL은 깨진 이미지가
   * 될 뿐이라 없는 편이 낫다.
   */
  static String nullIfTooLong(String text, int max) {
    return text == null || text.length() <= max ? text : null;
  }
}
