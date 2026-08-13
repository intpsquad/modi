package com.nomara.modi.server.domain.todo.repository;

import com.nomara.modi.server.domain.todo.entity.TodoSuggestionExposure;
import java.util.List;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface TodoSuggestionExposureRepository
    extends JpaRepository<TodoSuggestionExposure, Long> {

  /**
   * 방의 최근 노출 제목 — 최신순. {@code pageable}로 개수를 제한해 쓴다(상한은 {@code
   * TodoSuggestionExposureStore.MAX_EXCLUDED}).
   *
   * <p>엔티티가 아니라 제목만 뽑는다. 읽는 쪽이 AI 페이로드의 {@code excluded_todos}(문자열 목록)를 채우는 것이 전부이고, 엔티티를 실어오면 쓰지도
   * 않는 {@code room} LAZY 프록시가 딸려온다.
   *
   * <p>{@code id desc}가 타이브레이커로 붙어 있다. 한 번의 {@code saveAll}로 최대 8행이 같은 마이크로초를 받을 수 있어(후보 상한은 {@code
   * ai/src/modi_ai/prompts.py} 규칙 6) 이것이 없으면 50개 경계에서 어느 행이 잘리는지 비결정적이다.
   */
  @Query(
      "select e.title from TodoSuggestionExposure e "
          + "where e.room.id = :roomId order by e.createdAt desc, e.id desc")
  List<String> findRecentTitles(@Param("roomId") Long roomId, Pageable pageable);
}
