package com.nomara.modi.server.domain.todo.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.dto.TodoSuggestionCandidate;
import com.nomara.modi.server.domain.todo.repository.TodoSuggestionExposureRepository;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/**
 * 노출 기록 쓰기 규칙. 여기서 지키는 것은 <b>{@value TodoSuggestionExposureStore#MAX_EXCLUDED}칸을 낭비하지 않는 것</b>이다 —
 * 같은 제목이 여러 줄 쌓이면 제외 목록이 실질적으로 짧아져 중복 방지가 약해진다.
 *
 * <p>중복 제거의 주 메커니즘은 AI 서버의 {@code filter_candidates}다(우리가 보낸 목록과 겹치지 않게 돌려준다). 이 층은 그 계약이 깨졌을 때를 위한
 * 안전망이라, 여기 테스트는 "계약 위반 입력"을 일부러 넣어 본다.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TodoSuggestionExposureStoreTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
  }

  @Autowired private TodoSuggestionExposureStore store;
  @Autowired private TodoSuggestionExposureRepository exposureRepository;
  @Autowired private RoomRepository roomRepository;

  private static int counter = 0;

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter),
            null,
            "오픽 IH 달성",
            null,
            LocalDate.now(),
            LocalDate.now().plusDays(20)));
  }

  private static TodoSuggestionCandidate candidate(String title) {
    return new TodoSuggestionCandidate(title, "공부", null);
  }

  private List<String> stored(Room room) {
    return exposureRepository.findRecentTitles(room.getId(), PageRequest.of(0, 100));
  }

  @Test
  void recordsEveryCandidateTitle() {
    Room room = room();

    store.record(room.getId(), List.of(candidate("답변 틀 만들기"), candidate("교재 3회독")));

    assertThat(stored(room)).containsExactlyInAnyOrder("답변 틀 만들기", "교재 3회독");
  }

  @Test
  void doesNotStoreATitleThatWasAlreadyRecorded() {
    Room room = room();
    store.record(room.getId(), List.of(candidate("답변 틀 만들기")));

    store.record(room.getId(), List.of(candidate("답변 틀 만들기")));

    assertThat(stored(room)).containsExactly("답변 틀 만들기");
  }

  @Test
  void treatsSpacingAndCaseAsTheSameTitle() {
    // ai/src/modi_ai/suggest.py 의 _normalize 와 같은 기준이다 — 공백 전부 제거 + 소문자.
    Room room = room();
    store.record(room.getId(), List.of(candidate("OPIc 답변 틀 만들기")));

    store.record(room.getId(), List.of(candidate("opic답변틀만들기")));

    assertThat(stored(room)).containsExactly("OPIc 답변 틀 만들기");
  }

  @Test
  void dropsDuplicatesInsideOneBatch() {
    Room room = room();

    store.record(room.getId(), List.of(candidate("교재 3회독"), candidate("교재  3회독")));

    assertThat(stored(room)).containsExactly("교재 3회독");
  }

  @Test
  void doesNothingWhenThereAreNoCandidates() {
    // AI 서버가 후보를 하나도 못 내는 경우가 정상적으로 있다(자료가 없는 방 등).
    Room room = room();

    store.record(room.getId(), List.of());

    assertThat(stored(room)).isEmpty();
  }

  @Test
  void skipsBlankTitles() {
    // 빈 제목을 저장하면 정규화 결과가 빈 문자열이 되어 이후 모든 후보와 충돌한다.
    Room room = room();

    store.record(room.getId(), List.of(candidate("   "), candidate("교재 3회독")));

    assertThat(stored(room)).containsExactly("교재 3회독");
  }

  @Test
  void truncatesAnOverlongTitleInsteadOfLosingTheWholeBatch() {
    // AI 서버가 50자로 자르므로 평소엔 닿지 않는다. 그래도 두는 이유: 컬럼 폭을 넘기면 INSERT 가
    // 터져 트랜잭션이 롤백되고 **그 회차 기록이 전부** 사라진다 — 추천은 정상 동작하고 중복만
    // 계속 나오는 조용한 증상이 된다.
    Room room = room();

    store.record(room.getId(), List.of(candidate("가".repeat(300)), candidate("살아남아야 하는 후보")));

    assertThat(stored(room)).hasSize(2).contains("살아남아야 하는 후보");
    assertThat(stored(room).stream().filter(t -> t.startsWith("가")).findFirst())
        .get()
        .satisfies(title -> assertThat(title).hasSize(255));
  }

  /** 정규화는 순수 함수라 DB 없이 본다 — 이 규칙이 무너지면 위 중복 제거가 전부 조용히 실패한다. */
  @Nested
  class Normalize {

    @Test
    void removesEveryKindOfWhitespace() {
      assertThat(TodoSuggestionExposureStore.normalize(" 답변\t틀\n만들기 ")).isEqualTo("답변틀만들기");
    }

    @Test
    void removesUnicodeWhitespaceTooNotJustAsciiSpaces() {
      // 이 단언이 UNICODE_CHARACTER_CLASS 플래그를 지키는 유일한 코드다 — 위 테스트의
      // space/tab/newline 은 플래그가 없어도 통과하므로 규칙을 전혀 못 지킨다(리뷰 지적).
      // NBSP(U+00A0)·전각 공백(U+3000)은 웹에서 복사한 한국어 제목에 실제로 섞여 들어오고,
      // 이게 어긋나면 같은 제목이 다른 것으로 판정돼 중복 방지가 조용히 약해진다.
      assertThat(TodoSuggestionExposureStore.normalize("성수동 어니언　영업시간")).isEqualTo("성수동어니언영업시간");
    }

    @Test
    void lowercasesAscii() {
      assertThat(TodoSuggestionExposureStore.normalize("OPIc IH")).isEqualTo("opicih");
    }

    @Test
    void leavesKoreanAlone() {
      assertThat(TodoSuggestionExposureStore.normalize("교재3회독")).isEqualTo("교재3회독");
    }
  }
}
