package com.nomara.modi.server.global.notification;

import java.util.Map;

/**
 * FCM 등 푸시 발송을 추상화한다. 크리덴셜이 없는 테스트/CI 환경에서는 빈 자체가 생성되지 않는다({@code FirebaseConfig} 참고).
 *
 * <p>{@code data}는 탭 시 딥링크로 쓰는 키-값(예: {@code type}, {@code roomId}) — 전부 문자열이다(FCM data 페이로드 제약).
 * {@code docs/backend/notification-deeplink-handoff.md}, 2026-08-09.
 */
public interface PushSender {

  void send(String fcmToken, String title, String body, Map<String, String> data);
}
