package com.nomara.modi.server.domain.feedback.service;

import com.nomara.modi.server.domain.auth.client.EmailAttachment;
import com.nomara.modi.server.domain.auth.client.EmailSender;
import com.nomara.modi.server.domain.feedback.entity.Feedback;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * 피드백이 들어왔음을 팀에 알린다 — 메일(#70)과 디스코드(#114).
 *
 * <p><b>이 알림은 부가물이다.</b> 저장이 진실이고, 여기서 무슨 일이 나도 제출은 이미 성공한 것이다 — 그래서 실패를 삼키고 로그만 남긴다(호출부 {@code
 * FeedbackService} 참고).
 *
 * <p>{@link EmailSender}가 {@link Optional}인 이유: {@code EmailConfig}가
 * {@code @ConditionalOnProperty(spring.mail.host)}라 크리덴셜 없는 로컬/CI에는 빈이 아예 없다. 인증코드({@code
 * EmailVerificationService})는 이때 503을 던지지만 <b>피드백은 그러면 안 된다</b> — 메일을 못 보낸다고 사용자의 제보를 거절할 이유가 없다.
 */
@Component
public class FeedbackNotifier {

  private static final Logger log = LoggerFactory.getLogger(FeedbackNotifier.class);

  private final Optional<EmailSender> emailSender;
  private final String notifyTo;
  private final DiscordWebhookNotifier discord;

  public FeedbackNotifier(
      Optional<EmailSender> emailSender,
      @Value("${feedback.notify-to}") String notifyTo,
      DiscordWebhookNotifier discord) {
    this.emailSender = emailSender;
    this.notifyTo = notifyTo;
    this.discord = discord;
  }

  /**
   * 메일과 디스코드로 알린다(#114). <b>둘은 서로 독립이다</b> — 한쪽이 실패해도 다른 쪽은 간다.
   *
   * <p>여기서 채널별로 예외를 잡는 이유: 호출부({@code FeedbackService})도 예외를 삼키지만 거기서 잡으면 <b>먼저 터진 채널이 나머지를
   * 막는다.</b> 메일 SMTP 가 죽었다고 디스코드 알림까지 못 갈 이유가 없다.
   */
  public void notifySubmitted(Feedback feedback, EmailAttachment screenshot) {
    sendMail(feedback, screenshot);
    sendDiscord(feedback);
  }

  private void sendMail(Feedback feedback, EmailAttachment screenshot) {
    if (emailSender.isEmpty()) {
      log.info("메일 설정이 없어 피드백 알림을 건너뜁니다: id={}", feedback.getId());
      return;
    }
    try {
      emailSender.get().sendNotification(notifyTo, subject(feedback), body(feedback), screenshot);
    } catch (Exception e) {
      log.warn("피드백 알림 메일 실패: id={}", feedback.getId(), e);
    }
  }

  private void sendDiscord(Feedback feedback) {
    if (!discord.isConfigured()) {
      log.info("디스코드 웹훅이 없어 피드백 알림을 건너뜁니다: id={}", feedback.getId());
      return;
    }
    try {
      // 메일과 같은 정보를 쓴다 — 두 채널의 내용이 갈리면 어느 쪽이 맞는지 따지게 된다.
      discord.send("**" + subject(feedback) + "**\n```\n" + body(feedback) + "\n```");
    } catch (Exception e) {
      log.warn("피드백 디스코드 알림 실패: id={}", feedback.getId(), e);
    }
  }

  private String subject(Feedback feedback) {
    return "[모디 피드백] " + feedback.getType() + " #" + feedback.getId();
  }

  /** 팀이 바로 읽고 답장할 수 있게 회신 주소를 맨 위에 둔다. 스크린샷은 본문이 아니라 첨부로 간다. */
  private String body(Feedback feedback) {
    String userId = feedback.getUser() == null ? "(알 수 없음)" : feedback.getUser().getId();
    String replyEmail =
        feedback.getReplyEmail() == null ? "(미입력 — 답장할 수 없음)" : feedback.getReplyEmail();
    return String.join(
        "\n",
        "회신 주소: " + replyEmail,
        "유형: " + feedback.getType(),
        "보낸 사람: " + userId,
        "앱 버전: " + nullToDash(feedback.getAppVersion()),
        "기기: " + nullToDash(feedback.getDeviceInfo()),
        "접수 시각: " + feedback.getCreatedAt(),
        "스크린샷 키: " + nullToDash(feedback.getImageKey()),
        "",
        "---",
        feedback.getContent());
  }

  private static String nullToDash(String value) {
    return value == null ? "-" : value;
  }
}
