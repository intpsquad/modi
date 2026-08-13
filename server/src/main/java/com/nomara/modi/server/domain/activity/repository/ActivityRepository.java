package com.nomara.modi.server.domain.activity.repository;

import com.nomara.modi.server.domain.activity.entity.Activity;
import java.time.Instant;
import java.util.List;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ActivityRepository extends JpaRepository<Activity, Long> {

  List<Activity> findByRoomIdOrderByCreatedAtDesc(Long roomId, Pageable pageable);

  /**
   * 홈 활동 피드 조회(docs/backend/activity-poke-dedup-handoff.md) — {@code POKE}는 (actor, target) 조합당 최신
   * 1건만 후보에 남기고, 그 외 타입은 전부 그대로 둔 뒤 최신순으로 정렬한다. 콕 스팸이 {@code limit} 칸을 잠식해 다른 활동을 밀어내는 걸 막으려면
   * <b>정렬·limit 전에</b> 줄여야 해서 후처리가 아니라 쿼리 단계에서 처리한다.
   *
   * <p>대표 행은 {@code max(id)}로 고른다 — {@code id}는 {@code IDENTITY}라 그룹 내에서 항상 유일하지만, {@code
   * createdAt}은 {@code @CreationTimestamp}(JVM 시각)라 동시 요청이면 값이 겹칠 수 있어 그룹당 여러 행이 통과할 위험이 있다. {@code
   * order by}의 {@code id desc}는 {@code createdAt} 동률 시 limit 결과가 비결정적이 되는 걸 막는 타이브레이커다.
   *
   * <p>탈퇴로 {@code actorUser}/{@code targetUser} 중 하나라도 {@code null}인 POKE는 <b>그룹핑 대상에서 제외</b>하고 그대로
   * 통과시킨다 — GROUP BY는 NULL을 서로 같은 값으로 묶으므로, 그룹 키에 null을 포함시키면 실제로는 무관한 두 탈퇴자 쌍의 콕이 우연히 하나로 합쳐져 버릴 수
   * 있다(예: (actor=null, target=B)와 (actor=null, target=null) 두 서로 다른 사건이 한 그룹으로 묶여 하나가 조용히 사라짐).
   */
  @Query(
      "select a from Activity a where a.room.id = :roomId "
          + "and (a.type <> com.nomara.modi.server.domain.activity.entity.ActivityType.POKE "
          + "  or a.actorUser is null or a.targetUser is null "
          + "  or a.id in (select max(p.id) from Activity p "
          + "    where p.room.id = :roomId "
          + "      and p.type = com.nomara.modi.server.domain.activity.entity.ActivityType.POKE "
          + "      and p.actorUser is not null and p.targetUser is not null "
          + "    group by p.actorUser.id, p.targetUser.id)) "
          + "order by a.createdAt desc, a.id desc")
  List<Activity> findRecentByRoomIdWithPokesDeduped(
      @Param("roomId") Long roomId, Pageable pageable);

  /** 홈 활동 피드 NUDGE_QUIET_MEMBER용 — 방 안에서 이 유저가 actor인 가장 최근 활동 시각. */
  @Query(
      "select max(a.createdAt) from Activity a "
          + "where a.room.id = :roomId and a.actorUser.id = :userId")
  Instant findMaxCreatedAtByRoomIdAndActorUserId(
      @Param("roomId") Long roomId, @Param("userId") String userId);
}
