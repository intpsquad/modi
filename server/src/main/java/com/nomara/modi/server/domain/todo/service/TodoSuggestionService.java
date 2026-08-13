package com.nomara.modi.server.domain.todo.service;

import com.nomara.modi.server.domain.todo.client.AiSuggestPayload;
import com.nomara.modi.server.domain.todo.client.TodoSuggestionClient;
import com.nomara.modi.server.domain.todo.dto.TodoSuggestionCandidate;
import com.nomara.modi.server.domain.todo.dto.TodoSuggestionResponse;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.TransactionException;

/**
 * S-16-B AI 투두 추천. 앱 → 서버 → AI 서버(FastAPI) → 게이트웨이 경로에서 가운데를 맡는다.
 *
 * <p><b>이 클래스에 {@code @Transactional}이 없는 것이 의도다.</b> 세 단계의 트랜잭션 요구가 서로 다르다.
 *
 * <ol>
 *   <li>재료 읽기 — 읽기 트랜잭션({@link TodoSuggestionPayloadLoader})
 *   <li>LLM 호출 — <b>트랜잭션 밖.</b> 실측 7~9초({@code ai/docs/EXPERIMENTS.md} #10)이므로 DB 커넥션을 붙잡으면 안 된다
 *   <li>노출 기록 — 쓰기 트랜잭션({@link TodoSuggestionExposureStore})
 * </ol>
 *
 * <p>셋을 한 트랜잭션에 담으면 LLM이 응답하는 동안 커넥션이 점유된다. 동시에 여러 방이 추천을 누르면 풀이 마른다.
 */
@Service
public class TodoSuggestionService {

  private static final Logger log = LoggerFactory.getLogger(TodoSuggestionService.class);

  private final TodoSuggestionPayloadLoader payloadLoader;
  private final TodoSuggestionExposureStore exposureStore;
  private final TodoSuggestionClient suggestionClient;

  public TodoSuggestionService(
      TodoSuggestionPayloadLoader payloadLoader,
      TodoSuggestionExposureStore exposureStore,
      TodoSuggestionClient suggestionClient) {
    this.payloadLoader = payloadLoader;
    this.exposureStore = exposureStore;
    this.suggestionClient = suggestionClient;
  }

  /**
   * ⚠️ <b>구간 계측은 임시 디버깅이 아니라 영구 관측성이다 — 지우지 말 것</b>(2026-08-09). 운영에서 이 엔드포인트가 앱 기준 26~28초였는데 AI 서버
   * 평가 러너가 기록한 라운드는 5.3~6.8초({@code ai/docs/EXPERIMENTS.md} #28)라 <b>약 20초의 행방을 몰랐다.</b> 어느 구간이 먹는지
   * 모르면 추측으로 고치게 되고, 그러면 효과 없는 변경에 하루가 간다.
   *
   * <p>세 구간으로 나눈 이유: {@code load}(DB + 페이로드 구성) · {@code suggest}(HTTP 왕복 + AI 서버 전체) · {@code
   * record}(1 insert). 셋의 합과 전체의 차이가 프레임워크 오버헤드다.
   */
  public TodoSuggestionResponse suggest(String uid, Long roomId) {
    long startedAt = System.nanoTime();
    AiSuggestPayload payload = payloadLoader.load(uid, roomId);
    long loadedAt = System.nanoTime();

    List<TodoSuggestionCandidate> candidates = suggestionClient.suggest(payload);
    long suggestedAt = System.nanoTime();

    recordSafely(roomId, candidates);
    long finishedAt = System.nanoTime();

    log.info(
        "추천 구간(room={}): 페이로드 {}초 · AI 왕복 {}초 · 노출기록 {}초 · 합계 {}초"
            + " (자료 {}건 · 벡터 {}개 ≈ {}KB · 제외 {}건 · 후보 {}개)",
        roomId,
        seconds(startedAt, loadedAt),
        seconds(loadedAt, suggestedAt),
        seconds(suggestedAt, finishedAt),
        seconds(startedAt, finishedAt),
        payload.archive().size(),
        vectorCount(payload),
        estimatedVectorKilobytes(payload),
        payload.excludedTodos().size(),
        candidates.size());

    return new TodoSuggestionResponse(candidates);
  }

  private static String seconds(long fromNanos, long toNanos) {
    return String.format("%.2f", (toNanos - fromNanos) / 1_000_000_000.0);
  }

  private static long vectorCount(AiSuggestPayload payload) {
    return payload.archive().stream().filter(a -> a.embedding() != null).count();
  }

  /**
   * 임베딩이 JSON 으로 나갈 때 차지하는 대략 크기. <b>정확한 바디 크기가 아니라 자릿수를 보려는 것</b>이다 — 진짜로 재려면 한 번 더 직렬화해야 하고, 그
   * 비용이 재려는 대상보다 클 수 있다.
   *
   * <p>가설: 자료가 늘면 이 값이 선형으로 커져 직렬화·전송·pydantic 검증이 지연을 만든다. {@code AiSuggestPayload.ArchiveInfo}
   * javadoc 이 "자료 18건에 약 390KB"라고 적어둔 그 숫자다. float 하나가 소수점 표기로 대략 12바이트를 먹는다고 본다.
   */
  private static long estimatedVectorKilobytes(AiSuggestPayload payload) {
    long floats =
        payload.archive().stream()
            .filter(a -> a.embedding() != null)
            .mapToLong(a -> a.embedding().length)
            .sum();
    return floats * 12 / 1024;
  }

  /**
   * 노출 기록은 후보를 <b>반환할 때</b> 남긴다(2026-07-30 사용자 확정). 앱이 "실제로 보여줬다"를 되보고하는 방식은 기각했다 — 엔드포인트와 앱 변경이
   * 늘고, 그 보고가 실패하면 막으려던 중복 노출이 그대로 재발한다.
   *
   * <p>대가는 사용자가 응답을 받기 전에 이탈하면 <b>못 본 후보도 제외된다</b>는 것이다. 최근 {@value
   * TodoSuggestionExposureStore#MAX_EXCLUDED}개만 보내므로 추천을 계속 누르면 밀려나 되살아난다 — 영구 손실은 아니다.
   *
   * <p>기록이 실패해도 <b>추천 응답은 그대로 낸다.</b> 후보는 이미 만들어졌고 사용자가 볼 수 있어야 한다. AI 태깅·요약 실패 폴백과 같은 방향이다. 대가로 그
   * 회차의 후보가 다음에 다시 나올 수 있다.
   *
   * <p><b>삼키는 범위를 DB 계열로 좁힌 것이 의도다.</b> {@code catch (Exception)}으로 두면 {@code NullPointerException}
   * 같은 프로그래밍 버그까지 함께 삼켜, 리팩터링이 기록을 깨뜨려도 테스트는 초록이고 운영은 "추천은 잘 되는데 중복만 계속 나오는" 원래 증상으로 <b>조용히</b>
   * 되돌아간다. 이 티켓의 근본 원인 자체가 그 조용함이었으므로 같은 함정을 다시 만들지 않는다.
   *
   * <p>같은 이유로 {@code warn}이 아니라 {@code error}다 — 중복 방지가 죽은 것은 사용자에게 보이는 기능 저하이고, 알람에 걸려야 한다.
   */
  private void recordSafely(Long roomId, List<TodoSuggestionCandidate> candidates) {
    try {
      exposureStore.record(roomId, candidates);
    } catch (DataAccessException | TransactionException e) {
      log.error("추천 후보 노출 기록 실패 — 후보는 그대로 반환한다(다음 추천에 중복이 나올 수 있다)", e);
    }
  }
}
