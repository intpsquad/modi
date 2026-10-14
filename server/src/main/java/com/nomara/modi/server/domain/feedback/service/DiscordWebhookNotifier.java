package com.nomara.modi.server.domain.feedback.service;

import java.time.Duration;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

/**
 * 피드백을 디스코드 채널로 알린다(#114).
 *
 * <p><b>메일을 대체하지 않는다.</b> 둘은 역할이 다르다 — 메일은 회신 주소가 찍혀 있어 <b>답장 창구</b>이고, 디스코드는 팀이 상주하는 곳이라 <b>놓치지 않기
 * 위한 알림</b>이다. 디스코드만 남기면 문의한 분께 답장할 길이 사라진다.
 *
 * <p>웹훅 URL이 없으면 빈 구현처럼 동작한다({@code isConfigured() == false}) — 로컬·CI에서는 아무 일도 일어나지 않는다. {@code
 * KakaoApiClient}와 같은 이유로 {@code @ConditionalOnProperty} 대신 <b>값이 비었는지로</b> 가른다: 호출부가 {@code
 * Optional}을 다루지 않아도 되고, 설정 누락이 빈 알림으로 조용히 흘러가는 대신 로그에 남는다.
 *
 * <p>⚠️ <b>스크린샷은 보내지 않는다.</b> 피드백 이미지는 비공개로 저장한다({@code MinioConfig}가 {@code feedback/*}을 공개로 열지
 * 않는다 — 화면 캡처에 개인정보가 담길 수 있어서다). 채널에 올리면 그 전제가 깨진다. 이미지는 메일 첨부로만 간다.
 */
@Component
public class DiscordWebhookNotifier {

  /** 디스코드 메시지 본문 상한은 2000자다. 넘기면 400 이 떨어지므로 잘라서 보낸다. */
  private static final int MAX_CONTENT_LENGTH = 2000;

  private final String webhookUrl;
  private final RestClient restClient;

  // 생성자가 둘이라 스프링에 어느 쪽인지 알려줘야 한다(KakaoApiClient 와 같은 이유).
  @Autowired
  public DiscordWebhookNotifier(
      @Value("${feedback.discord-webhook-url:}") String webhookUrl,
      @Value("${feedback.discord-connect-timeout-seconds:5}") long connectTimeoutSeconds,
      @Value("${feedback.discord-read-timeout-seconds:5}") long readTimeoutSeconds) {
    this.webhookUrl = webhookUrl == null ? "" : webhookUrl.trim();
    // 🔴 타임아웃을 반드시 건다. 디스코드가 느릴 때 문의 제출 스레드가 같이 묶이면,
    // 사용자는 알림 때문에 제출이 느려지는 것을 겪는다(알림은 부가물일 뿐이다).
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(Duration.ofSeconds(connectTimeoutSeconds));
    requestFactory.setReadTimeout(Duration.ofSeconds(readTimeoutSeconds));
    this.restClient = RestClient.builder().requestFactory(requestFactory).build();
  }

  /** 테스트용 — 가짜 {@link RestClient}를 끼운다({@code KakaoApiClient}와 같은 패턴). */
  DiscordWebhookNotifier(String webhookUrl, RestClient restClient) {
    this.webhookUrl = webhookUrl == null ? "" : webhookUrl.trim();
    this.restClient = restClient;
  }

  public boolean isConfigured() {
    return !webhookUrl.isEmpty();
  }

  /** 던지지 않는다 — 호출부가 채널별로 실패를 격리한다({@link FeedbackNotifier} 참고). */
  public void send(String message) {
    restClient
        .post()
        .uri(webhookUrl)
        .contentType(MediaType.APPLICATION_JSON)
        .body(Map.of("content", truncate(message)))
        .retrieve()
        .toBodilessEntity();
  }

  private static String truncate(String message) {
    if (message.length() <= MAX_CONTENT_LENGTH) {
      return message;
    }
    // 잘렸다는 사실을 본문에 남긴다 — 조용히 사라지면 "왜 내용이 끊겼지"가 된다.
    String notice = "\n…(이후 생략 — 전문은 메일과 DB 에 있다)";
    return message.substring(0, MAX_CONTENT_LENGTH - notice.length()) + notice;
  }
}
