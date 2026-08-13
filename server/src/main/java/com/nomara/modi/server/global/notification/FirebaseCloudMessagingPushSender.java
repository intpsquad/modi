package com.nomara.modi.server.global.notification;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.Notification;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * 발송 실패는 로그만 남기고 삼킨다 — 콕찌르기 같은 발송 트리거는 {@code pokes} 행 저장 자체는 항상 성공해야 하고(specs/0011), 푸시는 "되면 좋은"
 * 부가 기능이라 예외를 호출자에게 전파하지 않는다.
 */
public class FirebaseCloudMessagingPushSender implements PushSender {

  private static final Logger log = LoggerFactory.getLogger(FirebaseCloudMessagingPushSender.class);

  private final FirebaseMessaging firebaseMessaging;

  public FirebaseCloudMessagingPushSender(FirebaseMessaging firebaseMessaging) {
    this.firebaseMessaging = firebaseMessaging;
  }

  @Override
  public void send(String fcmToken, String title, String body, Map<String, String> data) {
    Message message =
        Message.builder()
            .setToken(fcmToken)
            .setNotification(Notification.builder().setTitle(title).setBody(body).build())
            .putAllData(data)
            .build();
    try {
      firebaseMessaging.send(message);
    } catch (FirebaseMessagingException e) {
      log.warn("FCM 푸시 발송 실패: {}", e.getMessage());
    }
  }
}
