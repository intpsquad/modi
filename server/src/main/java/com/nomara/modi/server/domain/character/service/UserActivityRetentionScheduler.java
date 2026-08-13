package com.nomara.modi.server.domain.character.service;

import com.nomara.modi.server.domain.character.repository.UserActivityRepository;
import java.time.Duration;
import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 접속·조회 로그(specs/0016-협업-캐릭터.md) 원본 이벤트를 90일만 보관한다(백엔드 요청, 2026-08-07 확정) — 판정 로직이 최근 활동만 보므로 그보다
 * 오래 남길 이유가 없고, 개인 행동 로그라 무기한 보관을 피한다.
 *
 * <p>매일 한 번 도는 배치라 {@code @Scheduled(cron)}을 쓴다 — 지연 누적을 걱정할 필요 없는 저빈도 정리 작업이라 {@code
 * ArchiveCrawlRetryScheduler}의 {@code fixedDelay}(고빈도, 지연 상한이 의미 있음)와는 성격이 다르다.
 */
@Component
public class UserActivityRetentionScheduler {

  private static final Logger log = LoggerFactory.getLogger(UserActivityRetentionScheduler.class);

  private static final Duration RETENTION = Duration.ofDays(90);

  private final UserActivityRepository userActivityRepository;

  public UserActivityRetentionScheduler(UserActivityRepository userActivityRepository) {
    this.userActivityRepository = userActivityRepository;
  }

  @Scheduled(cron = "${modi.character.activity-retention-cron:0 0 4 * * *}")
  @Transactional
  public void purgeOldEvents() {
    Instant cutoff = Instant.now().minus(RETENTION);
    long deleted = userActivityRepository.deleteByCreatedAtBefore(cutoff);
    if (deleted > 0) {
      log.info("접속·조회 로그 90일 경과분 {}건 삭제", deleted);
    }
  }
}
