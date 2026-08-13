package com.nomara.modi.server.domain.archive.client;

import java.time.Duration;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

/**
 * {@link CrawlBlockCooldown} 의 Redis TTL 구현. {@code EmailVerificationService} 의 재전송 쿨다운과 같은 패턴이다.
 *
 * <p>🔴 <b>Redis 가 죽으면 크롤링을 막지 않는다(fail-open).</b> 이 층은 "덜 때리게" 하는 최적화이지 정확성 요구가 아니다. Redis 장애가 자료
 * 등록 장애로 번지면 그게 더 나쁘다 — {@code CompositeUrlCrawler} 가 예상 못 한 예외를 감싸는 것과 같은 방향이다.
 *
 * <p>⚠️ <b>fail-open 은 조용하면 안 된다.</b> Redis 가 계속 죽어 있으면 쿨다운이 아무 일도 안 하는데 증상이 안 보인다 — 그래서 로그를 남긴다.
 */
@Component
public class RedisCrawlBlockCooldown implements CrawlBlockCooldown {

  private static final Logger log = LoggerFactory.getLogger(RedisCrawlBlockCooldown.class);

  private final StringRedisTemplate redisTemplate;
  private final Duration cooldown;

  /**
   * @param cooldown 차단을 확인한 뒤 이 시간 동안 그 사이트를 부르지 않는다.
   *     <p>🔴 <b>기본값 10분의 근거</b>(2026-08-05 운영 DB 실측). 인스타 차단은 영구가 아니라 <b>10~20분 주기로 켜지고 꺼진다</b> —
   *     실패 뒤에 성공이 붙는다:
   *     <pre>
   *       12:45 FAILED → 12:54 DONE   (9분)
   *       15:18 FAILED → 15:36 DONE   (18분)
   *     </pre>
   *     그리고 실패가 뭉친 구간의 간격은 2~16분이었다. 10분이면 그 뭉치를 대부분 덮으면서 관측된 회복 하한(9분)에 가깝게 다시 시도한다.
   *     <p>⚠️ <b>이 값은 관측 2건에서 나왔다.</b> 더 길면 정상 회복을 놓치고, 더 짧으면 차단을 계속 때린다. 실제 회복 시간이 더 쌓이면 그 근거로 고칠
   *     것 — 그래서 상수가 아니라 프로퍼티다.
   */
  public RedisCrawlBlockCooldown(
      StringRedisTemplate redisTemplate,
      @Value("${modi.archive.block-cooldown:PT10M}") Duration cooldown) {
    this.redisTemplate = redisTemplate;
    this.cooldown = cooldown;
  }

  @Override
  public boolean isBlocked(String site) {
    try {
      return Boolean.TRUE.equals(redisTemplate.hasKey(key(site)));
    } catch (RuntimeException e) {
      log.warn("크롤 쿨다운을 읽지 못했다 — 막지 않고 진행한다(fail-open): site={}", site, e);
      return false;
    }
  }

  @Override
  public void markBlocked(String site) {
    try {
      redisTemplate.opsForValue().set(key(site), "1", cooldown);
      log.warn("{} 차단을 확인했다 — {}분 동안 호출하지 않는다", site, cooldown.toMinutes());
    } catch (RuntimeException e) {
      // 못 적으면 다음 요청이 또 때린다. 지금과 같은 동작이므로 나빠지지는 않는다.
      log.warn("크롤 쿨다운을 적지 못했다(fail-open): site={}", site, e);
    }
  }

  private static String key(String site) {
    return "crawl:blocked:" + site;
  }
}
