package com.nomara.modi.server.domain.auth.client;

import com.nomara.modi.server.domain.auth.service.VerificationEmailTemplate;
import com.nomara.modi.server.global.exception.BadGatewayException;
import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.ClassPathResource;
import org.springframework.mail.MailException;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;

public class SmtpEmailSender implements EmailSender {

  private static final Logger log = LoggerFactory.getLogger(SmtpEmailSender.class);
  private static final String LOGO_RESOURCE_PATH = "email/modi_logo.png";

  private final JavaMailSender mailSender;
  private final String from;

  public SmtpEmailSender(JavaMailSender mailSender, String from) {
    this.mailSender = mailSender;
    this.from = from;
  }

  /**
   * {@code multipart=true}로 생성한 {@link MimeMessageHelper}는 MULTIPART_MODE_MIXED_RELATED다 — {@code
   * text/plain}·{@code text/html} 대체본(alternative)과 인라인 리소스(related, 로고)를 함께 담을 수 있다. 로고의
   * Content-ID는 {@link VerificationEmailTemplate#LOGO_CONTENT_ID}와 반드시 일치해야 템플릿의 {@code cid:} 참조가
   * 실제 첨부와 연결된다.
   */
  @Override
  public void send(String to, String subject, String plainText, String html) {
    try {
      MimeMessage message = mailSender.createMimeMessage();
      MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
      helper.setFrom(from);
      helper.setTo(to);
      helper.setSubject(subject);
      helper.setText(plainText, html);
      helper.addInline(
          VerificationEmailTemplate.LOGO_CONTENT_ID,
          new ClassPathResource(LOGO_RESOURCE_PATH),
          "image/png");
      mailSender.send(message);
    } catch (MailException | MessagingException e) {
      log.warn("이메일 발송 실패: {}", to, e);
      throw new BadGatewayException("이메일을 보내지 못했어요. 잠시 후 다시 시도해 주세요", e);
    }
  }
}
