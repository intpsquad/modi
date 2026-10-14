package com.nomara.modi.server.domain.feedback.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.auth.client.EmailAttachment;
import com.nomara.modi.server.domain.auth.client.EmailSender;
import com.nomara.modi.server.domain.feedback.entity.Feedback;
import com.nomara.modi.server.domain.feedback.entity.FeedbackType;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;

/**
 * 메일과 디스코드는 <b>서로 독립</b>이다(#114) — 한쪽이 죽어도 다른 쪽은 간다.
 *
 * <p>이 계약이 중요한 이유: 두 채널의 실패를 호출부({@code FeedbackService})에서만 잡으면 <b>먼저 터진 채널이 나머지를 막는다.</b> SMTP 가
 * 죽었다고 디스코드 알림까지 못 갈 이유가 없다. 그래서 {@link FeedbackNotifier}가 채널별로 잡는다.
 *
 * <p>스프링 컨텍스트를 띄우지 않는다 — 이유는 {@code DiscordWebhookNotifierTest} 주석 참고.
 */
class FeedbackNotifierChannelTest {

  private static Feedback feedback() {
    return new Feedback(
        null, FeedbackType.BUG, "댓글이 안 지워져요", "me@example.com", "1.1.1(10)", "ios 26", null);
  }

  /** 발송을 기록하고, {@code failing} 이면 실제 SMTP 처럼 던진다. */
  private static class RecordingEmailSender implements EmailSender {
    final List<String> sent = new java.util.ArrayList<>();
    boolean failing;

    @Override
    public void send(String to, String subject, String plainText, String html) {}

    @Override
    public void sendNotification(
        String to, String subject, String plainText, EmailAttachment attachment) {
      if (failing) throw new IllegalStateException("SMTP 죽음");
      sent.add(subject);
    }
  }

  /** 보낸 메시지를 기록하는 가짜 디스코드. */
  private static class RecordingDiscord extends DiscordWebhookNotifier {
    final List<String> sent = new java.util.ArrayList<>();
    boolean failing;

    RecordingDiscord(boolean configured) {
      super(configured ? "https://discord.test/api/webhooks/1/abc" : "", (RestClient) null);
    }

    @Override
    public void send(String message) {
      if (failing) throw new IllegalStateException("디스코드 죽음");
      sent.add(message);
    }
  }

  @Test
  void bothChannelsReceiveTheSameFeedback() {
    RecordingEmailSender mail = new RecordingEmailSender();
    RecordingDiscord discord = new RecordingDiscord(true);

    new FeedbackNotifier(Optional.of(mail), "team@example.com", discord)
        .notifySubmitted(feedback(), null);

    assertThat(mail.sent).hasSize(1);
    assertThat(discord.sent).hasSize(1);
    assertThat(discord.sent.getFirst())
        .as("두 채널의 내용이 갈리면 어느 쪽이 맞는지 따지게 된다")
        .contains("댓글이 안 지워져요")
        .contains("me@example.com");
  }

  @Test
  void mailFailureDoesNotBlockDiscord() {
    RecordingEmailSender mail = new RecordingEmailSender();
    mail.failing = true;
    RecordingDiscord discord = new RecordingDiscord(true);

    new FeedbackNotifier(Optional.of(mail), "team@example.com", discord)
        .notifySubmitted(feedback(), null);

    assertThat(discord.sent).as("SMTP 가 죽어도 디스코드는 가야 한다").hasSize(1);
  }

  @Test
  void discordFailureDoesNotBlockMail() {
    RecordingEmailSender mail = new RecordingEmailSender();
    RecordingDiscord discord = new RecordingDiscord(true);
    discord.failing = true;

    new FeedbackNotifier(Optional.of(mail), "team@example.com", discord)
        .notifySubmitted(feedback(), null);

    assertThat(mail.sent).as("디스코드가 죽어도 메일은 가야 한다").hasSize(1);
  }

  @Test
  void neitherChannelConfiguredIsNotAnError() {
    // 로컬·CI 가 이 상태다. 조용히 건너뛰고 제출은 살아남아야 한다.
    RecordingDiscord discord = new RecordingDiscord(false);

    new FeedbackNotifier(Optional.empty(), "team@example.com", discord)
        .notifySubmitted(feedback(), null);

    assertThat(discord.sent).isEmpty();
  }
}
