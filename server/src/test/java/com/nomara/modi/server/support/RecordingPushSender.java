package com.nomara.modi.server.support;

import com.nomara.modi.server.global.notification.PushSender;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 실제 FCM을 부르지 않고 발송 호출을 기록하는 가짜 {@link PushSender}. {@code PokeServiceTest}가 처음 만든 내부 fake(토큰만 기록)를
 * 대체한다 — 알림 트리거 6종 작업(2026-08-05)에서 문구(title/body)까지 검증해야 하는 테스트가 여러 클래스로 늘어 공용 fixture로 뺐다. {@code
 * FakePushSenderConfig}와 함께 {@code @Import}해서 쓴다.
 */
public class RecordingPushSender implements PushSender {

  public record SentPush(String fcmToken, String title, String body, Map<String, String> data) {}

  private final List<SentPush> sent = new ArrayList<>();

  @Override
  public void send(String fcmToken, String title, String body, Map<String, String> data) {
    sent.add(new SentPush(fcmToken, title, body, data));
  }

  public List<SentPush> sent() {
    return sent;
  }

  public List<String> sentToTokens() {
    return sent.stream().map(SentPush::fcmToken).toList();
  }

  /** 같은 스프링 컨텍스트를 재사용하는 테스트 클래스 안에서 테스트 간 기록이 섞이지 않도록 {@code @BeforeEach}에서 호출한다. */
  public void clear() {
    sent.clear();
  }
}
