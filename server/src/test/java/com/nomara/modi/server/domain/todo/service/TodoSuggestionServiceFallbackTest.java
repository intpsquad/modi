package com.nomara.modi.server.domain.todo.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.nomara.modi.server.domain.todo.client.AiSuggestPayload;
import com.nomara.modi.server.domain.todo.dto.TodoSuggestionCandidate;
import com.nomara.modi.server.domain.todo.dto.TodoSuggestionResponse;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.transaction.CannotCreateTransactionException;

/**
 * 노출 기록 실패가 추천 응답을 깨뜨리지 않는지. 스프링·DB·네트워크 없이 본다 — 협력자 셋을 손으로 끼운다.
 *
 * <p>이 폴백이 없으면 <b>DB 쓰기 장애가 곧 추천 기능 장애</b>가 된다. 후보는 이미 LLM이 만들어 놨고 사용자가 볼 수 있어야 하므로, AI 태깅·요약 실패와
 * 같은 방향으로 삼킨다(대가: 그 회차 후보가 다음에 다시 나올 수 있다).
 */
class TodoSuggestionServiceFallbackTest {

  private static final AiSuggestPayload PAYLOAD =
      new AiSuggestPayload(
          new AiSuggestPayload.RoomInfo(
              "오픽 스터디", "오픽 IH 달성", null, LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 20)),
          List.of(),
          List.of(),
          List.of(),
          List.of());

  private static final TodoSuggestionCandidate CANDIDATE =
      new TodoSuggestionCandidate("답변 틀 만들기", "공부", null);

  /** 협력자 생성자 인자는 오버라이드한 메서드가 건드리지 않으므로 null로 둔다. */
  private static TodoSuggestionPayloadLoader loaderReturningFixedPayload() {
    return new TodoSuggestionPayloadLoader(null, null, null, null, null, null, null, null, false) {
      @Override
      public AiSuggestPayload load(String uid, Long roomId) {
        return PAYLOAD;
      }
    };
  }

  private static TodoSuggestionService serviceWhereRecordingThrows(RuntimeException failure) {
    TodoSuggestionExposureStore failing =
        new TodoSuggestionExposureStore(null, null) {
          @Override
          public void record(Long roomId, List<TodoSuggestionCandidate> candidates) {
            throw failure;
          }
        };
    return new TodoSuggestionService(
        loaderReturningFixedPayload(), failing, payload -> List.of(CANDIDATE));
  }

  @Test
  void returnsCandidatesWhenTheDatabaseRejectsTheWrite() {
    // 실제로 관측되는 타입이다 — record() 시점에 방이 삭제됐으면 getReferenceById 가 만든 FK 가
    // 커밋 때 터진다. IllegalStateException 같은 임의 타입으로 재면 catch 를 좁힌 뒤 위장 통과한다.
    TodoSuggestionService service =
        serviceWhereRecordingThrows(new DataIntegrityViolationException("fk violation"));

    TodoSuggestionResponse response = service.suggest("uid-1", 1L);

    assertThat(response.candidates()).containsExactly(CANDIDATE);
  }

  @Test
  void returnsCandidatesWhenTheTransactionItselfFails() {
    TodoSuggestionService service =
        serviceWhereRecordingThrows(new CannotCreateTransactionException("db down"));

    assertThat(service.suggest("uid-1", 1L).candidates()).containsExactly(CANDIDATE);
  }

  @Test
  void doesNotSwallowProgrammingBugs() {
    // 폴백의 목적은 DB 장애를 넘기는 것이지 우리 버그를 감추는 것이 아니다. catch (Exception) 이면
    // 리팩터링이 기록을 깨뜨려도 테스트는 초록이고 운영은 "중복만 계속 나오는" 원래 증상으로
    // 조용히 돌아간다 — 이 티켓의 근본 원인이 정확히 그 조용함이었다.
    TodoSuggestionService service =
        serviceWhereRecordingThrows(new NullPointerException("리팩터링 사고"));

    assertThatThrownBy(() -> service.suggest("uid-1", 1L)).isInstanceOf(NullPointerException.class);
  }

  @Test
  void recordsExactlyWhatItIsAboutToReturn() {
    // 반환값과 기록이 어긋나면 중복 방지가 조용히 빗나간다 — 그래서 같은 목록인지 못 박는다.
    List<TodoSuggestionCandidate> recorded = new ArrayList<>();
    TodoSuggestionExposureStore capturing =
        new TodoSuggestionExposureStore(null, null) {
          @Override
          public void record(Long roomId, List<TodoSuggestionCandidate> candidates) {
            recorded.addAll(candidates);
          }
        };
    TodoSuggestionService service =
        new TodoSuggestionService(
            loaderReturningFixedPayload(), capturing, payload -> List.of(CANDIDATE));

    TodoSuggestionResponse response = service.suggest("uid-2", 1L);

    assertThat(recorded).isEqualTo(response.candidates());
  }
}
