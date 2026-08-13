package com.nomara.modi.server.domain.character.repository;

import com.nomara.modi.server.domain.character.entity.UserActivity;
import com.nomara.modi.server.domain.character.entity.UserActivityKind;
import java.time.Instant;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;

public interface UserActivityRepository extends JpaRepository<UserActivity, Long> {

  /** 협업 캐릭터 활동성 신호(specs/0016) — 최근 구간 전체 조회·접속 건수. */
  long countByUserIdAndCreatedAtAfter(String userId, Instant after);

  /** 활동성 신호 중 "조회는 많은데 완료는 적다"(LURKER) 판정용 — 종류별로 나눠 세야 할 때. */
  long countByUserIdAndKindAndCreatedAtAfter(String userId, UserActivityKind kind, Instant after);

  /** 로그 보존 90일(백엔드 요청, 2026-08-07) — 매일 배치가 지난 원본 이벤트를 지운다. 호출부가 트랜잭션을 연다. */
  @Modifying
  long deleteByCreatedAtBefore(Instant before);
}
