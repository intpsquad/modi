package com.nomara.modi.server.domain.room.service;

import java.security.SecureRandom;
import java.time.Duration;
import java.util.Optional;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

/** 초대코드는 Redis 단독 저장(specs/0002-data-model.md, 2026-07-23 확정) — Postgres 테이블 없음, TTL 1일. */
@Service
public class InviteCodeService {

  /** 6자, 혼동 문자(0/O, 1/I) 제외 32자 알파벳. */
  private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

  private static final int CODE_LENGTH = 6;
  private static final Duration TTL = Duration.ofDays(1);
  private static final SecureRandom RANDOM = new SecureRandom();

  private final StringRedisTemplate redisTemplate;

  public InviteCodeService(StringRedisTemplate redisTemplate) {
    this.redisTemplate = redisTemplate;
  }

  public String generate(Long roomId) {
    String code;
    boolean stored;
    do {
      code = randomCode();
      Boolean result =
          redisTemplate.opsForValue().setIfAbsent(codeKey(code), roomId.toString(), TTL);
      stored = Boolean.TRUE.equals(result);
    } while (!stored);

    redisTemplate.opsForValue().set(roomKey(roomId), code, TTL);
    return code;
  }

  /** S-40-B — specs/0002-data-model.md 21~24행: 이전 코드를 즉시 무효화한 뒤 새 코드를 발급한다. */
  public String reissue(Long roomId) {
    String oldCode = redisTemplate.opsForValue().get(roomKey(roomId));
    if (oldCode != null) {
      redisTemplate.delete(codeKey(oldCode));
    }
    return generate(roomId);
  }

  /** 현재 유효한 코드를 유지해서 돌려주고, TTL이 끝난 경우에만 새 코드를 만든다. */
  public String getOrCreate(Long roomId) {
    String code = redisTemplate.opsForValue().get(roomKey(roomId));
    if (code != null && resolveRoomId(code).filter(roomId::equals).isPresent()) {
      return code;
    }
    return generate(roomId);
  }

  public Optional<Long> resolveRoomId(String code) {
    String value = redisTemplate.opsForValue().get(codeKey(code.toUpperCase()));
    return Optional.ofNullable(value).map(Long::valueOf);
  }

  private static String codeKey(String code) {
    return "invite:code:" + code;
  }

  private static String roomKey(Long roomId) {
    return "invite:room:" + roomId;
  }

  private static String randomCode() {
    StringBuilder builder = new StringBuilder(CODE_LENGTH);
    for (int i = 0; i < CODE_LENGTH; i++) {
      builder.append(ALPHABET.charAt(RANDOM.nextInt(ALPHABET.length())));
    }
    return builder.toString();
  }
}
