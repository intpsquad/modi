package com.nomara.modi.server.domain.auth.service;

import com.nomara.modi.server.domain.auth.client.EmailSender;
import com.nomara.modi.server.global.exception.BadRequestException;
import com.nomara.modi.server.global.exception.ConflictException;
import com.nomara.modi.server.global.exception.GoneException;
import com.nomara.modi.server.global.exception.ServiceUnavailableException;
import com.nomara.modi.server.global.exception.TooManyRequestsException;
import java.security.SecureRandom;
import java.time.Duration;
import java.util.Optional;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

/**
 * 이메일 자체 회원가입의 인증코드 발송/검증. 초대코드(specs/0002-data-model.md)와 같은 이유로 Redis 단독 저장 — TTL 5분짜리 6자리 코드에
 * 이력을 남길 필요가 없다. 검증 성공 후 실제 Firebase 계정 생성(이메일/비밀번호)은 앱이 Firebase SDK로 직접 하고, 이 서비스는 "이 이메일을 실제로
 * 소유했고 아직 가입하지 않았다"만 확인한다.
 *
 * <p>재전송 쿨다운(60초)·시도 5회 제한은 2026-07-30 AskUserQuestion으로 확정(specs/OPEN.md). 앱의 재전송 버튼은 코드 TTL(5분)이
 * 다 지나야 눌리므로 실사용 흐름에서 쿨다운에 걸릴 일은 거의 없다 — 이건 앱을 거치지 않은 직접 호출을 막는 API 방어용이다.
 */
@Service
public class EmailVerificationService {

  private static final int CODE_DIGITS = 6;
  private static final Duration CODE_TTL = Duration.ofMinutes(5);
  private static final Duration RESEND_COOLDOWN = Duration.ofSeconds(60);
  private static final int MAX_ATTEMPTS = 5;
  private static final SecureRandom RANDOM = new SecureRandom();

  private final StringRedisTemplate redisTemplate;
  private final EmailAvailabilityChecker availabilityChecker;
  private final Optional<EmailSender> emailSender;
  private final VerificationEmailTemplate emailTemplate;

  public EmailVerificationService(
      StringRedisTemplate redisTemplate,
      EmailAvailabilityChecker availabilityChecker,
      Optional<EmailSender> emailSender,
      VerificationEmailTemplate emailTemplate) {
    this.redisTemplate = redisTemplate;
    this.availabilityChecker = availabilityChecker;
    this.emailSender = emailSender;
    this.emailTemplate = emailTemplate;
  }

  public void sendCode(String rawEmail) {
    String email = normalize(rawEmail);
    if (Boolean.TRUE.equals(redisTemplate.hasKey(cooldownKey(email)))) {
      throw new TooManyRequestsException("잠시 후 다시 시도해 주세요");
    }
    if (availabilityChecker.isRegistered(email)) {
      throw new ConflictException("이미 가입된 이메일이에요");
    }

    EmailSender sender =
        emailSender.orElseThrow(() -> new ServiceUnavailableException("이메일 인증이 지금은 지원되지 않아요"));

    String code = randomCode();
    long expireMinutes = CODE_TTL.toMinutes();
    String plainText = "인증코드: " + code + "\n" + expireMinutes + "분 안에 입력해 주세요.";
    String html = emailTemplate.render(code, expireMinutes);
    // 발송을 먼저 시도한다 — 순서를 반대로 하면(저장 후 발송) 발송이 실패(502)해도 코드·쿨다운이 이미
    // 커밋돼 사용자가 실패 응답을 받고도 즉시 재시도할 수 없다(2026-07-31 리뷰 지적).
    sender.send(email, "[모디] 이메일 인증코드", plainText, html);

    redisTemplate.opsForValue().set(codeKey(email), code, CODE_TTL);
    redisTemplate.delete(attemptsKey(email));
    redisTemplate.opsForValue().set(cooldownKey(email), "1", RESEND_COOLDOWN);
  }

  public void verifyCode(String rawEmail, String code) {
    String email = normalize(rawEmail);
    String stored = redisTemplate.opsForValue().get(codeKey(email));
    if (stored == null) {
      throw new GoneException("인증코드가 만료됐어요");
    }
    if (stored.equals(code)) {
      redisTemplate.delete(codeKey(email));
      redisTemplate.delete(attemptsKey(email));
      return;
    }

    Long attempts = redisTemplate.opsForValue().increment(attemptsKey(email));
    redisTemplate.expire(attemptsKey(email), CODE_TTL);
    if (attempts != null && attempts >= MAX_ATTEMPTS) {
      // 5회 실패 시 코드를 즉시 무효화한다 — 다음 검증 시도부터는 위 stored == null 분기(410)로 떨어진다.
      redisTemplate.delete(codeKey(email));
    }
    throw new BadRequestException("인증코드가 올바르지 않아요");
  }

  /**
   * Firebase Auth의 이메일 조회는 대소문자를 구분하지 않고, 대부분의 메일 공급자도 local-part 대소문자를 구분하지 않는다 — 정규화하지 않으면 대소문자만
   * 바꿔 쿨다운·시도횟수 제한을 우회하면서 같은 메일함으로 계속 코드를 받아볼 수 있다(2026-07-31 리뷰 지적).
   */
  private static String normalize(String email) {
    return email.trim().toLowerCase();
  }

  private static String codeKey(String email) {
    return "email:verify:code:" + email;
  }

  private static String attemptsKey(String email) {
    return "email:verify:attempts:" + email;
  }

  private static String cooldownKey(String email) {
    return "email:verify:cooldown:" + email;
  }

  private static String randomCode() {
    return String.format("%06d", RANDOM.nextInt(1_000_000));
  }
}
