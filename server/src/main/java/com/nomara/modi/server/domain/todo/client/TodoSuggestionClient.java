package com.nomara.modi.server.domain.todo.client;

import com.nomara.modi.server.domain.todo.dto.TodoSuggestionCandidate;
import java.util.List;

/**
 * AI 서버 호출 경계. {@code AiTaggingClient}와 같은 이유로 인터페이스로 두었다 — 서비스가 구현에 의존하지 않아 테스트에서 실제 FastAPI·LLM을
 * 부르지 않고 가짜를 끼울 수 있다.
 */
public interface TodoSuggestionClient {

  List<TodoSuggestionCandidate> suggest(AiSuggestPayload payload);
}
