package com.nomara.modi.server.domain.todo.repository;

import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.entity.TodoAssignee;
import com.nomara.modi.server.domain.todo.entity.TodoAssigneeId;
import com.nomara.modi.server.domain.user.entity.User;
import java.time.Instant;
import java.util.List;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TodoAssigneeRepository extends JpaRepository<TodoAssignee, TodoAssigneeId> {

  @Query(
      "select ta.todo from TodoAssignee ta "
          + "where ta.todo.room.id = :roomId and ta.user.id = :uid and ta.todo.completed = false "
          + "order by ta.todo.createdAt asc")
  List<Todo> findMyIncompleteTodos(
      @Param("roomId") Long roomId, @Param("uid") String uid, Pageable pageable);

  @Query(
      "select ta.user.id, count(ta), sum(case when ta.todo.completed then 1 else 0 end) "
          + "from TodoAssignee ta where ta.todo.room.id = :roomId group by ta.user.id")
  List<Object[]> aggregateProgressByRoomId(@Param("roomId") Long roomId);

  @Query(
      "select ta.todo from TodoAssignee ta "
          + "where ta.todo.room.id = :roomId and ta.user.id = :userId "
          + "order by ta.todo.createdAt asc")
  List<Todo> findTodosByRoomIdAndUserId(
      @Param("roomId") Long roomId, @Param("userId") String userId);

  List<TodoAssignee> findByTodoIdIn(List<Long> todoIds);

  boolean existsByTodoId(Long todoId);

  /** 홈 활동 피드 공동 완료 문구(docs/backend/live-banner-copy-handoff.md §2)용 — 이 투두의 담당자 전원. */
  @Query("select ta.user from TodoAssignee ta where ta.todo.id = :todoId")
  List<User> findAssigneeUsersByTodoId(@Param("todoId") Long todoId);

  /** 홈 활동 피드 TODO_ALL_DONE 판정용 — 한 유저의 방 안 담당 진행률만(전체 방 집계보다 가볍다). */
  @Query(
      "select count(ta), sum(case when ta.todo.completed then 1 else 0 end) "
          + "from TodoAssignee ta where ta.todo.room.id = :roomId and ta.user.id = :userId")
  List<Object[]> aggregateProgressByRoomIdAndUserId(
      @Param("roomId") Long roomId, @Param("userId") String userId);

  /** 홈 활동 피드 NUDGE_QUIET_MEMBER용 — 방 안에서 이 유저가 담당한 투두 중 가장 최근 완료 시각. */
  @Query(
      "select max(ta.todo.completedAt) from TodoAssignee ta "
          + "where ta.todo.room.id = :roomId and ta.user.id = :userId and ta.todo.completed = true")
  Instant findMaxCompletedAtByRoomIdAndUserId(
      @Param("roomId") Long roomId, @Param("userId") String userId);

  @Modifying
  void deleteByTodoId(Long todoId);

  /** 협업 캐릭터(specs/0016) 완료율 — 방 무관, 이 사용자가 전체 방에서 담당한 전체/완료 건수. */
  @Query(
      "select count(ta), sum(case when ta.todo.completed then 1 else 0 end) "
          + "from TodoAssignee ta where ta.user.id = :userId")
  List<Object[]> aggregateProgressByUserId(@Param("userId") String userId);

  /**
   * 협업 캐릭터(specs/0016) 타이밍·스트릭 계산용 — 이 사용자가 담당해 완료한 투두 전체(방 무관). {@code dueDate}·{@code
   * completedAt}·{@code createdAt}만 있으면 되므로 엔티티를 그대로 돌려준다(건수가 캐릭터 판정 대상 정도라 가벼움).
   */
  @Query(
      "select ta.todo from TodoAssignee ta "
          + "where ta.user.id = :userId and ta.todo.completed = true")
  List<Todo> findCompletedTodosByUserId(@Param("userId") String userId);
}
