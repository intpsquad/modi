package com.nomara.modi.server.domain.todo.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.headerDoesNotExist;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.jsonPath;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.nomara.modi.server.domain.todo.dto.TodoSuggestionCandidate;
import com.nomara.modi.server.global.exception.ApiException;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

/**
 * AI 서버와의 계약(snake_case 필드명·내부 키 헤더·실패 변환)을 실제 FastAPI 없이 검증한다. 필드명이 어긋나면 파이썬 쪽에서 422가 나는데, 그 사고를
 * 여기서 잡는 것이 이 테스트의 목적이다.
 */
class HttpTodoSuggestionClientTest {

  private static final String BASE_URL = "http://ai-server:8000";

  private record Fixture(HttpTodoSuggestionClient client, MockRestServiceServer server) {}

  private Fixture fixture(String internalKey) {
    RestClient.Builder builder = RestClient.builder().baseUrl(BASE_URL);
    MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
    return new Fixture(new HttpTodoSuggestionClient(builder.build(), internalKey), server);
  }

  private AiSuggestPayload payload() {
    return new AiSuggestPayload(
        new AiSuggestPayload.RoomInfo(
            "오픽 스터디", "오픽 IH 달성", "8월 중순 접수", LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 20)),
        List.of("공부"),
        List.of("교재 사기"),
        List.of("이미 보여준 후보"),
        List.of(
            new AiSuggestPayload.ArchiveInfo(
                12L,
                "오픽 공부법",
                "본문",
                List.of("오픽"),
                true,
                3L,
                Instant.parse("2026-07-30T04:05:06Z"))));
  }

  @Test
  void serializesBodyWithSnakeCaseFieldNames() {
    Fixture f = fixture("");
    f.server()
        .expect(requestTo(BASE_URL + "/v1/todo-suggestions"))
        .andExpect(method(HttpMethod.POST))
        .andExpect(jsonPath("$.room.goal_detail").value("8월 중순 접수"))
        .andExpect(jsonPath("$.room.start_date").value("2026-08-01"))
        .andExpect(jsonPath("$.existing_todos[0]").value("교재 사기"))
        // 이 필드가 snake_case 로 나가지 않으면 파이썬이 422 를 주고 중복 방지가 통째로 죽는다
        // 빈 배열만 확인하면 필드명이 틀려도 통과하므로 값까지 본다.
        .andExpect(jsonPath("$.excluded_todos[0]").value("이미 보여준 후보"))
        .andExpect(jsonPath("$.archive[0].content").value("본문"))
        .andRespond(withSuccess("{\"candidates\":[]}", MediaType.APPLICATION_JSON));

    f.client().suggest(payload());

    f.server().verify();
  }

  /**
   * 자료 선별 축(좋아요·핀·최신). AI 서버가 순위 모드에서 프롬프트에 실을 자료를 고를 때 쓴다 — 없으면 등록 역순 그대로 들어간다. (유사도 축용 임베딩은 #129
   * 로 싣지 않는다.)
   *
   * <p><b>{@code created_at}이 문자열인지가 이 테스트의 핵심이다.</b> {@code Instant}에 {@link
   * com.fasterxml.jackson.annotation.JsonFormat}을 안 붙이면 Jackson 기본값(WRITE_DATES_AS_TIMESTAMPS)에 걸려
   * 숫자로 나가고 FastAPI가 422로 거절한다 — {@code RoomInfo.startDate}에서 이미 한 번 겪은 사고다.
   */
  @Test
  void serializesArchiveSelectionAxes() {
    Fixture f = fixture("");
    f.server()
        .expect(requestTo(BASE_URL + "/v1/todo-suggestions"))
        .andExpect(jsonPath("$.archive[0].like_count").value(3))
        .andExpect(jsonPath("$.archive[0].pinned").value(true))
        .andExpect(jsonPath("$.archive[0].created_at").value("2026-07-30T04:05:06Z"))
        .andRespond(withSuccess("{\"candidates\":[]}", MediaType.APPLICATION_JSON));

    f.client().suggest(payload());

    f.server().verify();
  }

  /**
   * 🔴 추천 요청에 <b>임베딩 벡터를 싣지 않는다</b>(#129). AI 서버는 #109 부터 벡터를 읽지 않는데 자료당 약 21KB 를 실어 보내고 있었다.
   *
   * <p>{@code jsonPath(...).doesNotExist()} 로는 못 잰다 — 값이 {@code null} 이어도 통과한다. 본문 글자로 본다.
   */
  @Test
  void doesNotSendEmbeddingVectors() {
    Fixture f = fixture("");
    f.server()
        .expect(requestTo(BASE_URL + "/v1/todo-suggestions"))
        .andExpect(content().string(not(containsString("embedding"))))
        .andRespond(withSuccess("{\"candidates\":[]}", MediaType.APPLICATION_JSON));

    f.client().suggest(payload());

    f.server().verify();
  }

  /** 크롤링 전이라 본문이 없는 자료도 나머지 축은 그대로 나가야 한다. */
  @Test
  void serializesArchiveWithoutContent() {
    Fixture f = fixture("");
    f.server()
        .expect(requestTo(BASE_URL + "/v1/todo-suggestions"))
        .andExpect(jsonPath("$.archive[0].title").value("크롤링 전"))
        .andExpect(jsonPath("$.archive[0].like_count").value(0))
        .andRespond(withSuccess("{\"candidates\":[]}", MediaType.APPLICATION_JSON));

    f.client()
        .suggest(
            new AiSuggestPayload(
                new AiSuggestPayload.RoomInfo(
                    "방", "목표", null, LocalDate.of(2026, 8, 1), LocalDate.of(2026, 8, 20)),
                List.of(),
                List.of(),
                List.of(),
                List.of(
                    new AiSuggestPayload.ArchiveInfo(
                        7L, "크롤링 전", null, List.of(), false, 0L, Instant.EPOCH))));

    f.server().verify();
  }

  @Test
  void sendsInternalKeyHeaderWhenConfigured() {
    Fixture f = fixture("secret-key");
    f.server()
        .expect(header("X-Internal-Key", "secret-key"))
        .andRespond(withSuccess("{\"candidates\":[]}", MediaType.APPLICATION_JSON));

    f.client().suggest(payload());

    f.server().verify();
  }

  @Test
  void omitsInternalKeyHeaderWhenBlank() {
    Fixture f = fixture("");
    f.server()
        .expect(headerDoesNotExist("X-Internal-Key"))
        .andRespond(withSuccess("{\"candidates\":[]}", MediaType.APPLICATION_JSON));

    f.client().suggest(payload());

    f.server().verify();
  }

  @Test
  void mapsSnakeCaseResponseIntoCandidates() {
    Fixture f = fixture("");
    f.server()
        .expect(content().contentType(MediaType.APPLICATION_JSON))
        .andRespond(
            withSuccess(
                """
                {"candidates":[{"title":"답변 틀 만들기","category":"공부","source_item_id":12}]}
                """,
                MediaType.APPLICATION_JSON));

    List<TodoSuggestionCandidate> candidates = f.client().suggest(payload());

    assertThat(candidates).hasSize(1);
    assertThat(candidates.getFirst().title()).isEqualTo("답변 틀 만들기");
    assertThat(candidates.getFirst().sourceItemId()).isEqualTo(12L);
  }

  /**
   * AI 서버가 {@code category} 를 **더 이상 보내지 않는다** 후보는 카테고리 없이 나가고 사용자가 투두 탭에서 직접 분류한다.
   *
   * <p>🔴 이 테스트가 배포 안전성의 근거다. Java record 는 JSON 에 키가 없으면 예외가 아니라 {@code null} 을 넣는데, 그 동작에 기대어
   * "Spring 을 안 고쳐도 된다 · 배포 순서를 맞출 필요가 없다"고 판단했다. 전역 Jackson 설정이 바뀌거나 record 가 검증을 갖게 되면 여기서 깨져야 한다
   * — 안 그러면 운영에서 추천이 502 로 죽는다.
   */
  @Test
  void aResponseWithoutCategoryStillParses() {
    Fixture f = fixture("");
    f.server()
        .expect(content().contentType(MediaType.APPLICATION_JSON))
        .andRespond(
            withSuccess(
                """
                {"candidates":[{"title":"답변 틀 만들기","source_item_id":12}]}
                """,
                MediaType.APPLICATION_JSON));

    List<TodoSuggestionCandidate> candidates = f.client().suggest(payload());

    assertThat(candidates).hasSize(1);
    assertThat(candidates.getFirst().title()).isEqualTo("답변 틀 만들기");
    assertThat(candidates.getFirst().sourceItemId()).isEqualTo(12L);
    assertThat(candidates.getFirst().category()).isNull();
  }

  @Test
  void turnsAiServerFailureIntoBadGateway() {
    Fixture f = fixture("");
    f.server().expect(requestTo(BASE_URL + "/v1/todo-suggestions")).andRespond(withServerError());

    ApiException error =
        catchThrowableOfType(() -> f.client().suggest(payload()), ApiException.class);

    assertThat(error.getStatus()).isEqualTo(HttpStatus.BAD_GATEWAY);
  }
}
