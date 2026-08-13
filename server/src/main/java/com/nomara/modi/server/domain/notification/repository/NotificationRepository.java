package com.nomara.modi.server.domain.notification.repository;

import com.nomara.modi.server.domain.notification.entity.Notification;
import java.time.Instant;
import java.util.List;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface NotificationRepository extends JpaRepository<Notification, Long> {

  /** 알림 내역 목록 — 최신순, [Pageable]로 상한(현재 100건, specs/0017). */
  List<Notification> findByUserIdOrderByCreatedAtDesc(String userId, Pageable pageable);

  /** 홈 벨 배지 — 목록 전체를 안 불러오고 가볍게 개수만. */
  long countByUserIdAndReadAtIsNull(String userId);

  /** S-41 진입 시 전체 읽음 처리 — 여러 행을 한 번에 바꾸는 것이 목적이라 벌크 UPDATE(단건 더티체킹 아님). */
  @Modifying
  @Query(
      "update Notification n set n.readAt = :now "
          + "where n.user.id = :userId and n.readAt is null")
  int markAllRead(@Param("userId") String userId, @Param("now") Instant now);

  /** 보존 90일(specs/0017) — 매일 배치가 지난 기록을 지운다. 호출부가 트랜잭션을 연다. */
  @Modifying
  long deleteByCreatedAtBefore(Instant before);
}
