package com.nomara.modi.server.domain.todo.client;

import com.fasterxml.jackson.annotation.JsonFormat;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.annotation.JsonNaming;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;

/**
 * AI 서버(FastAPI)의 {@code POST /v1/todo-suggestions} 요청 바디.
 *
 * <p>AI 서버는 도메인 DB를 직접 보지 않으므로(ai/CLAUDE.md) 추천에 필요한 재료는 전부 여기에 실어 보낸다. 필드 이름은 파이썬 쪽 {@code
 * modi_ai.schemas} 와 1:1로 맞춰야 하며, 그쪽이 snake_case라 {@link JsonNaming}으로 변환한다.
 */
@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
public record AiSuggestPayload(
    RoomInfo room,
    List<String> categories,
    List<String> existingTodos,
    List<String> excludedTodos,
    List<ArchiveInfo> archive) {

  /**
   * 날짜는 {@code "2026-08-01"} 문자열로 나가야 한다 — 파이썬 쪽 필드 타입이 {@code datetime.date}다.
   *
   * <p>{@link JsonFormat}을 붙이지 않으면 Jackson 기본값(WRITE_DATES_AS_TIMESTAMPS)에 걸려 {@code [2026,8,1]}
   * 배열로 나가고 FastAPI가 422로 거절한다. RestClient는 스프링 부트가 튜닝한 ObjectMapper를 쓰지 않을 수 있어 전역 설정에 기대지 않고 DTO가
   * 직접 형식을 못 박는다(HttpTodoSuggestionClientTest가 실제로 잡아낸 문제).
   */
  @JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
  public record RoomInfo(
      String name,
      String goal,
      String goalDetail,
      @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd") LocalDate startDate,
      @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd") LocalDate endDate) {}

  /**
   * 추천의 근거가 되는 자료.
   *
   * <p>{@code content}는 <b>AI 요약 또는 본문</b>이다 — 어느 쪽인지는 서버가 고른다({@code
   * TodoSuggestionPayloadLoader.pickContent}). 요약을 쓰는 것이 이 필드의 존재 이유고(자료 20건 기준 약 117,000 tok → 약
   * 2,600 tok, {@code ai/docs/EXPERIMENTS.md} #8), 요약이 없는 자료가 정상적으로 있으므로 본문 폴백이 함께 필요하다.
   *
   * <p>{@code null}일 수 있다 — 크롤링 전(PENDING)·실패(FAILED)라 요약도 본문도 없는 항목이다. 그래도 제목·태그가 근거가 되므로 걸러내지
   * 않는다.
   *
   * <p><b>뒤의 네 필드는 AI 서버가 자료 순위를 매기는 축이다</b>. 가중치는 좋아요 3.0 &gt; 핀 2.5 &gt; 유사도 2.0 &gt; 최근성 1.0이고,
   * 융합은 <b>가중 순위 정규화</b>다 — 등수를 축마다 [0,1]로 편 뒤 가중합한다. (원래 확정이던 가중 RRF는 2026-08-02에 실측으로 기각됐다:
   * 좋아요·핀이 사실상 2단계 축이라 17단계인 유사도·최근성을 이기지 못해 가중치 순서가 뒤집혔다 — {@code ai/docs/EXPERIMENTS.md} #22.)
   *
   * <p><b>순위 계산은 AI 서버가 한다</b> — 여기서는 재료만 싣는다. 그래서 코사인을 미리 계산해 스칼라로 보내지 않고 벡터를 그대로 보낸다(방 목표 벡터가 AI
   * 서버 쪽에 있다). 대가는 전송량이다: 자료 18건에 약 390KB.
   *
   * <p>{@code embedding}은 {@code null}일 수 있다. 정상인 경우가 넷이고({@code
   * V7__add_embedding_to_archive_items.sql}) 그때 그 자료는 <b>유사도 축에서만 빠지고</b> 나머지 세 축으로 후보에 남는다.
   */
  @JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
  public record ArchiveInfo(
      Long id,
      String title,
      String content,
      List<String> tags,
      float[] embedding,
      boolean pinned,
      long likeCount,
      /**
       * {@link JsonFormat}이 없으면 {@code RoomInfo.startDate}와 <b>같은 사고</b>가 난다 — Jackson 기본값
       * (WRITE_DATES_AS_TIMESTAMPS)이 {@code 1785384306.000000000} 같은 숫자를 내보내고 FastAPI가 422로 거절한다.
       * 파이썬 쪽 필드 타입은 {@code datetime.datetime}이다.
       */
      @JsonFormat(shape = JsonFormat.Shape.STRING) Instant createdAt) {}
}
