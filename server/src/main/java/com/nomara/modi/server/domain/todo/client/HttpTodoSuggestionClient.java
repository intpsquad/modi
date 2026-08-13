package com.nomara.modi.server.domain.todo.client;

import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.annotation.JsonNaming;
import com.nomara.modi.server.domain.todo.dto.TodoSuggestionCandidate;
import com.nomara.modi.server.global.exception.BadGatewayException;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * AI 서버(FastAPI) HTTP 호출.
 *
 * <p>태깅({@code OpenAiTaggingClient})은 실패해도 빈 태그로 조용히 넘어가지만 추천은 그 화면의 본체라 그럴 수 없다 — 실패를 502로 올려 앱이
 * 재시도 UI를 띄우게 한다(specs/design.md §6 에러 패턴).
 */
public class HttpTodoSuggestionClient implements TodoSuggestionClient {

  private static final Logger log = LoggerFactory.getLogger(HttpTodoSuggestionClient.class);
  private static final String PATH = "/v1/todo-suggestions";
  private static final String INTERNAL_KEY_HEADER = "X-Internal-Key";

  private final RestClient restClient;
  private final String internalKey;

  public HttpTodoSuggestionClient(RestClient restClient, String internalKey) {
    this.restClient = restClient;
    this.internalKey = internalKey;
  }

  @Override
  public List<TodoSuggestionCandidate> suggest(AiSuggestPayload payload) {
    try {
      AiSuggestResponse response =
          restClient
              .post()
              .uri(PATH)
              .headers(
                  headers -> {
                    // 키가 비어 있으면 헤더를 붙이지 않는다. AI 서버도 비어 있으면 검증을 건너뛰므로
                    // 로컬에서는 양쪽 다 설정 없이 동작한다(ai/docs/DECISIONS.md 2026-07-29 확정).
                    if (!internalKey.isBlank()) {
                      headers.set(INTERNAL_KEY_HEADER, internalKey);
                    }
                  })
              .body(payload)
              .retrieve()
              .body(AiSuggestResponse.class);

      if (response == null || response.candidates() == null) {
        return List.of();
      }
      return response.candidates().stream()
          .map(c -> new TodoSuggestionCandidate(c.title(), c.category(), c.sourceItemId()))
          .toList();
    } catch (RestClientException e) {
      // 연결 실패·타임아웃·4xx·5xx가 전부 여기로 온다. 내부 키 불일치(401)도 설정 오류이므로
      // 원인을 사용자에게 노출하지 않고 같은 메시지로 묶는다.
      log.warn("AI 추천 서버 호출 실패", e);
      throw new BadGatewayException("AI 추천 서버에 연결하지 못했어요");
    }
  }

  /** FastAPI 응답 전용 — 앱에 나가는 {@link TodoSuggestionCandidate}는 camelCase라 따로 둔다. */
  @JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
  record AiSuggestResponse(List<AiCandidate> candidates) {}

  @JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
  record AiCandidate(String title, String category, Long sourceItemId) {}
}
