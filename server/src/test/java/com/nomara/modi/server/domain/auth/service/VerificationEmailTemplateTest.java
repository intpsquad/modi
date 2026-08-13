package com.nomara.modi.server.domain.auth.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/** 템플릿 로딩·플레이스홀더 치환만 검증하는 순수 유닛 테스트 — 클래스패스 리소스만 읽으므로 스프링 컨텍스트가 필요 없다. */
class VerificationEmailTemplateTest {

  private final VerificationEmailTemplate template = new VerificationEmailTemplate();

  @Test
  void rendersCodeAndExpireMinutesAndLogoCid() {
    String html = template.render("123456", 5);

    assertThat(html).contains("123456");
    assertThat(html).contains("5분");
    assertThat(html).contains("cid:" + VerificationEmailTemplate.LOGO_CONTENT_ID);
  }

  @Test
  void leavesNoUnreplacedPlaceholders() {
    String html = template.render("654321", 5);

    assertThat(html).doesNotContain("{{");
  }
}
