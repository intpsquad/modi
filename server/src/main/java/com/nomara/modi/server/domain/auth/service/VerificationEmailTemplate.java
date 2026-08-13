package com.nomara.modi.server.domain.auth.service;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

/**
 * 인증코드 이메일의 HTML 템플릿(프론트/디자인 핸드오프, {@code docs/email/verification-code-email.html} 참고, 서버 런타임 사본은
 * {@code classpath:email/verification-code-email.html})을 읽어 플레이스홀더를 치환한다(2026-08-05 QA 핸드오프,
 * `specs/OPEN.md`).
 *
 * <p><b>로고는 공개 URL 호스팅이 아니라 CID 인라인 첨부로 넣는다</b> — MinIO는 지금 전부 사용자 업로드 런타임 콘텐츠(프로필 사진·방 커버·아카이브
 * 썸네일)에만 쓰여서, 정적 앱 브랜드 자산을 위해 별도 업로드 인프라·수동 배포 단계를 늘릴 이유가 없다. 로고 PNG를 서버 클래스패스 리소스로 번들해 {@code
 * SmtpEmailSender}가 발송 시점에 {@link #LOGO_CONTENT_ID}로 인라인 첨부한다 — 이 상수는 그 쪽과 반드시 같은 값을 써야 한다(HTML의
 * {@code cid:} 참조와 MIME Content-ID가 일치해야 이미지가 뜬다).
 *
 * <p>템플릿이 단순 {@code {{TOKEN}}} 문법이라 Thymeleaf 등 템플릿 엔진 의존성을 새로 추가할 이유가 없어 {@link String#replace}만
 * 쓴다.
 */
@Component
public class VerificationEmailTemplate {

  public static final String LOGO_CONTENT_ID = "modi_logo";

  private static final String TEMPLATE_PATH = "email/verification-code-email.html";

  private final String template;

  public VerificationEmailTemplate() {
    this.template = readClasspathResource(TEMPLATE_PATH);
  }

  public String render(String code, long expireMinutes) {
    return template
        .replace("{{CODE}}", code)
        .replace("{{EXPIRE_MINUTES}}", String.valueOf(expireMinutes))
        .replace("{{LOGO_URL}}", "cid:" + LOGO_CONTENT_ID);
  }

  private static String readClasspathResource(String path) {
    try (InputStream in = new ClassPathResource(path).getInputStream()) {
      return new String(in.readAllBytes(), StandardCharsets.UTF_8);
    } catch (IOException e) {
      throw new IllegalStateException("이메일 템플릿을 읽을 수 없어요: " + path, e);
    }
  }
}
