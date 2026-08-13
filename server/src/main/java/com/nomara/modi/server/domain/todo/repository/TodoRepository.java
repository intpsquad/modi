package com.nomara.modi.server.domain.todo.repository;

import com.nomara.modi.server.domain.todo.entity.Todo;
import java.time.Instant;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TodoRepository extends JpaRepository<Todo, Long> {

  List<Todo> findByRoomIdOrderByPositionAscIdAsc(Long roomId);

  /**
   * category_id가 NULL("기타")도 하나의 그룹으로 다루기 위해 파생 쿼리 대신 {@code @Query}를 쓴다 — 파생 쿼리명(예: {@code
   * findByRoomIdAndCategoryId})은 category_id가 실제로 NULL인 행을 매칭하지 못한다.
   */
  @Query(
      "select t from Todo t where t.room.id = :roomId and "
          + "((:categoryId is null and t.category is null) or (t.category.id = :categoryId)) "
          + "order by t.position asc, t.id asc")
  List<Todo> findByRoomIdAndCategoryId(
      @Param("roomId") Long roomId, @Param("categoryId") Long categoryId);

  long countByRoomId(Long roomId);

  long countByRoomIdAndCompletedTrue(Long roomId);

  /** 홈 활동 피드 WEEKLY_SUMMARY·NUDGE_NONE_TODAY용(방 범위, 완료 시각 구간 카운트). */
  long countByRoomIdAndCompletedAtBetween(Long roomId, Instant start, Instant end);

  /** 홈 활동 피드 NUDGE_UNASSIGNED용 — 담당자가 한 명도 없는(미지정) 미완료 투두 수. */
  @Query(
      "select count(t) from Todo t where t.room.id = :roomId and t.completed = false "
          + "and not exists (select 1 from TodoAssignee ta where ta.todo = t)")
  long countUnassignedIncompleteByRoomId(@Param("roomId") Long roomId);

  /**
   * 모아보기 "이미지" 탭 피드(2026-08-09, docs/backend/todo-image-archive-handoff.md) — 방 전체, 폴더 무관, 핀
   * 우선·최신순.
   */
  @Query(
      "select t from Todo t where t.room.id = :roomId and t.imageUrl is not null "
          + "order by t.imagePinned desc, t.imageAttachedAt desc, t.id desc")
  List<Todo> findImageTodosByRoomId(@Param("roomId") Long roomId);
}
