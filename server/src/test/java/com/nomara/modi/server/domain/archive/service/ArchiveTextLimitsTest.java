package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class ArchiveTextLimitsTest {

  @Test
  void shorterThanLimitPassesThrough() {
    assertThat(ArchiveTextLimits.truncate("짧은 제목", ArchiveTextLimits.MAX_TITLE)).isEqualTo("짧은 제목");
  }

  @Test
  void longerThanLimitIsCutToExactlyTheLimit() {
    // 회귀: 255자를 넘는 og:title이 title VARCHAR(255)에 그대로 들어가 INSERT가 실패했다.
    String tooLong = "가".repeat(300);

    String truncated = ArchiveTextLimits.truncate(tooLong, ArchiveTextLimits.MAX_TITLE);

    assertThat(truncated).hasSize(ArchiveTextLimits.MAX_TITLE);
  }

  @Test
  void exactlyAtTheLimitIsNotCut() {
    String exact = "가".repeat(ArchiveTextLimits.MAX_TITLE);

    assertThat(ArchiveTextLimits.truncate(exact, ArchiveTextLimits.MAX_TITLE)).isEqualTo(exact);
  }

  @Test
  void nullPassesThrough() {
    // 크롤링 전 PENDING 항목의 bodyText는 null이다.
    assertThat(ArchiveTextLimits.truncate(null, ArchiveTextLimits.MAX_BODY_TEXT)).isNull();
  }

  @Test
  void surrogatePairIsNotSplitInHalf() {
    // 이모지는 char 2개다. 경계에서 쪼개면 고아 서로게이트가 남아 UTF-8 인코딩에서 터질 수 있다.
    String text = "가".repeat(ArchiveTextLimits.MAX_TITLE - 1) + "😀";

    String truncated = ArchiveTextLimits.truncate(text, ArchiveTextLimits.MAX_TITLE);

    assertThat(Character.isHighSurrogate(truncated.charAt(truncated.length() - 1))).isFalse();
    assertThat(truncated).hasSize(ArchiveTextLimits.MAX_TITLE - 1);
  }

  @Test
  void overlongThumbnailBecomesNullInsteadOfBeingCut() {
    // 썸네일은 URL이라 자르면 깨진 주소가 된다 — 차라리 없는 편이 낫다.
    String tooLong = "https://cdn.example.com/" + "a".repeat(ArchiveTextLimits.MAX_THUMBNAIL);

    assertThat(ArchiveTextLimits.nullIfTooLong(tooLong, ArchiveTextLimits.MAX_THUMBNAIL)).isNull();
    assertThat(
            ArchiveTextLimits.nullIfTooLong(
                "https://cdn.example.com/a.png", ArchiveTextLimits.MAX_THUMBNAIL))
        .isEqualTo("https://cdn.example.com/a.png");
    assertThat(ArchiveTextLimits.nullIfTooLong(null, ArchiveTextLimits.MAX_THUMBNAIL)).isNull();
  }
}
