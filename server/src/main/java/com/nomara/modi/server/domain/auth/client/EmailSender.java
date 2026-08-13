package com.nomara.modi.server.domain.auth.client;

/**
 * 이메일 발송 경계. {@code TodoSuggestionClient}/{@code FirebaseTokenIssuer}와 같은 이유로 인터페이스로 둔다 — 테스트에서 실제
 * SMTP를 부르지 않고 가짜를 끼울 수 있다.
 *
 * <p>{@code plainText}/{@code html}을 둘 다 받는 이유는 접근성/호환성용 {@code text/plain} 대체본을 {@code text/html}과
 * 함께 멀티파트로 보내기 위해서다(2026-08-05, 인증코드 메일 HTML 전환).
 */
public interface EmailSender {

  void send(String to, String subject, String plainText, String html);
}
