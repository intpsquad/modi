package com.nomara.modi.server.domain.feedback.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withNoContent;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

/**
 * 디스코드 웹훅 발송(#114).
 *
 * <p>스프링 컨텍스트를 띄우지 않는다 — 이 저장소는 테스트들이 같은 인메모리 DB 를 공유하면서 각자 {@code create-drop} 을 걸어, 컨텍스트가 하나 늘
 * 때마다 캐시 한계에 가까워진다(#101 에서 실제로 무관한 테스트가 깨졌다). 순수 단위 테스트면 그 축을 아예 건드리지 않는다.
 */
class DiscordWebhookNotifierTest {

  private static final String WEBHOOK = "https://discord.test/api/webhooks/1/abc";

  @Test
  void webhookUrlNotSetMeansNotConfigured() {
    // 로컬·CI 에는 웹훅이 없다. 그때 빈 구현처럼 동작해야 피드백 저장이 영향을 받지 않는다.
    assertThat(new DiscordWebhookNotifier("", null).isConfigured()).isFalse();
    assertThat(new DiscordWebhookNotifier(null, null).isConfigured()).isFalse();
    assertThat(new DiscordWebhookNotifier("   ", null).isConfigured())
        .as("공백만 있는 값도 설정 안 함으로 본다 — .env 에 키만 남는 일이 흔하다")
        .isFalse();
  }

  @Test
  void webhookUrlSetMeansConfigured() {
    assertThat(new DiscordWebhookNotifier(WEBHOOK, null).isConfigured()).isTrue();
  }

  @Test
  void sendsContentAsJsonToWebhookUrl() {
    RestClient.Builder builder = RestClient.builder();
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    server
        .expect(requestTo(WEBHOOK))
        .andExpect(method(HttpMethod.POST))
        .andExpect(content().json("{\"content\":\"안녕\"}"))
        .andRespond(withNoContent());

    new DiscordWebhookNotifier(WEBHOOK, builder.build()).send("안녕");

    server.verify();
  }

  @Test
  void tooLongMessageIsTruncatedWithANotice() {
    // 디스코드 본문 상한은 2000자다. 넘기면 400 이 떨어져 알림이 통째로 날아간다.
    RestClient.Builder builder = RestClient.builder();
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    server
        .expect(requestTo(WEBHOOK))
        .andExpect(
            request -> {
              String body = request.getBody().toString();
              assertThat(body)
                  .as("잘렸다는 사실을 본문에 남긴다 — 조용히 사라지면 내용이 왜 끊겼는지 알 수 없다")
                  .contains("이후 생략");
            })
        .andRespond(withNoContent());

    new DiscordWebhookNotifier(WEBHOOK, builder.build()).send("가".repeat(3000));

    server.verify();
  }
}
