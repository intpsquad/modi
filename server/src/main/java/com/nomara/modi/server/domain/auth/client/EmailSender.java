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

  /**
   * 팀 내부 알림 메일(피드백 제출 등, #70). {@link #send}와 <b>일부러 분리</b>했다 — 그쪽은 인증코드 템플릿용 로고를 항상 인라인하므로 재사용하면
   * 무관한 첨부가 붙는다. 여기는 HTML도 로고도 없이 평문만 보내고, {@code attachment}가 있으면 파일로 붙인다.
   *
   * @param attachment 없으면 {@code null}
   */
  void sendNotification(String to, String subject, String plainText, EmailAttachment attachment);
}
