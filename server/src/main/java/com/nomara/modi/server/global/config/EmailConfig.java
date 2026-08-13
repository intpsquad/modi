package com.nomara.modi.server.global.config;

import com.nomara.modi.server.domain.auth.client.EmailSender;
import com.nomara.modi.server.domain.auth.client.SmtpEmailSender;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.mail.javamail.JavaMailSender;

/**
 * {@code spring.mail.host}(= {@code SPRING_MAIL_HOST} 환경변수)가 설정된 경우에만 {@link EmailSender}를 만든다.
 * {@code FirebaseConfig}/{@code MinioConfig}와 동일한 패턴 — {@code application.yml}에 이 프로퍼티의 기본값을 두지
 * 않는다(기본값을 두면 {@code @ConditionalOnProperty}가 항상 참이 되어 크리덴셜 없는 환경에서도 빈이 생기고, 그 뒤 동작이 "빈 없음=503"과
 * 갈린다 — {@code minio.endpoint} 사고와 동형, specs/OPEN.md 참고). 크리덴셜 없는 로컬/CI 환경에서는 이 빈이 생성되지 않고 {@code
 * EmailVerificationService}가 503으로 폴백한다({@code Optional<EmailSender>}).
 *
 * <p>Spring Boot 자신의 {@code MailSenderAutoConfiguration}도 내부적으로 같은 프로퍼티({@code spring.mail.host})로
 * 게이팅돼 있어, 이 조건이 거짓이면 {@code JavaMailSender} 빈 자체가 생기지 않는다(2026-07-31 리뷰로 디컴파일 확인) — 즉 이
 * {@code @ConditionalOnProperty}를 "불필요한 이중 방어"로 오인해 지우면 파라미터 해석 자체가 실패해 컨텍스트 초기화가 하드 크래시한다. 좀비 부팅은
 * 아니지만(즉시 실패라 안전한 실패 모드), 지우면 안 되는 이유는 여전히 유효하다.
 */
@Configuration
public class EmailConfig {

  @Bean
  @ConditionalOnProperty(name = "spring.mail.host")
  public EmailSender emailSender(
      JavaMailSender mailSender, @Value("${spring.mail.username}") String from) {
    return new SmtpEmailSender(mailSender, from);
  }
}
