package com.nomara.modi.server.domain.todo.service;

import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.dto.TodoSuggestionCandidate;
import com.nomara.modi.server.domain.todo.entity.TodoSuggestionExposure;
import com.nomara.modi.server.domain.todo.repository.TodoSuggestionExposureRepository;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * "이미 노출한 후보"의 읽기·쓰기. {@link TodoSuggestionService}에서 별 빈으로 뽑은 이유는 둘이다.
 *
 * <p><b>① 쓰기 트랜잭션을 LLM 호출 밖에 두기 위해서다.</b> 자기 호출은 프록시를 타지 않아 같은 클래스에 {@code @Transactional} 메서드를 두면
 * 트랜잭션이 안 열린다. 추천 호출은 실측 7~9초인데({@code ai/docs/EXPERIMENTS.md} #10) 그 시간 동안 DB 커넥션을 붙잡으면 안 된다.
 *
 * <p><b>② 테스트 seam</b> — 기록 실패가 추천 응답을 깨뜨리지 않는지를 스프링·DB 없이 확인할 수 있다.
 */
@Component
class TodoSuggestionExposureStore {

  /**
   * 방별 상한. 오래된 행을 지우는 대신 <b>조회를 이 개수로 제한</b>해서 지킨다(V6 마이그레이션 주석 ③).
   *
   * <p><b>이 목록은 "방금 보여준 것을 바로 또 보여주지 않기" 전용이다.</b> 영구 제외가 아니다 — 채택한 후보는 투두가 되고, 방의 투두는 {@code
   * TodoSuggestionPayloadLoader}가 <b>상한 없이 전부</b> {@code existing_todos}로 실어 보내며 AI 서버의 {@code
   * filter_candidates}가 그것과 겹치는 후보를 버린다. 즉 <b>채택한 것은 이 목록에 없어도 다시 안 나온다.</b>
   *
   * <p><b>16 = 회당 상한 8개({@code ai/src/modi_ai/prompts.py} 규칙 6) × 직전 2회차.</b>
   *
   * <p>⚠️ <b>원래 50이었고 그것이 후보를 말렸다</b>(2026-08-03 수정). 노출 기록이 영구 제외 역할을 <b>중복으로</b> 하면서, 채택하지 않은
   * 후보까지 영구히 막았다. 실제로 관측된 방은 채택 2개에 제외 50개였고 후보가 8개에서 1~2개로 떨어졌다. 같은 방 데이터로 창 크기만 바꿔 3회씩 재보니 후보 평균이
   * <b>50→2.0 · 24→5.3 · 16→6.0 · 8→7.3 · 0→7.0</b>이었다({@code ai/docs/EXPERIMENTS.md} #24).
   *
   * <p>8이 후보 수는 더 낫지만 반복 노출 방지가 한 회차뿐이라, 이 기능을 만든 이유("같은 후보가 3회차 내내 반복")에 너무 가까워진다. 실사용에서 반복 불만이
   * 나오면 24로 올린다(실측 5.3).
   *
   * <p>⚠️ <b>V6 마이그레이션 주석의 "50개"는 당시 값이다.</b> 과거 마이그레이션은 체크섬 때문에 고치지 않는다.
   */
  static final int MAX_EXCLUDED = 16;

  /**
   * {@code title} 컬럼 폭. AI 서버가 이미 50자로 자르므로({@code ai/src/modi_ai/schemas.py} {@code
   * MAX_TITLE_LENGTH}) 평소에는 닿지 않는 방어선이다.
   *
   * <p>그래도 두는 이유: 넘치면 INSERT가 터지고 {@link #record}의 트랜잭션이 통째로 롤백되어 <b>그 회차의 노출 기록이 전부 사라진다.</b> 증상은
   * 조용하다 — 추천은 정상 동작하고 중복만 계속 나온다. 223에서 "프롬프트가 200자를 요구했는데 모델이 231자를 냈다"를 실제로 겪었으므로 계약을 신뢰하지 않는다.
   */
  private static final int MAX_TITLE = 255;

  /**
   * {@code ai/src/modi_ai/suggest.py}의 {@code _normalize}를 미러링한다 — 파이썬 {@code str.split()}과 맞추려고
   * NBSP(U+00A0)·전각 공백(U+3000) 같은 유니코드 공백까지 본다. 플래그를 지우면 그 둘이 살아남아 같은 제목이 다른 것으로 판정된다({@code
   * TodoSuggestionExposureStoreTest.Normalize}가 지킨다).
   *
   * <p><b>완전히 같지는 않다</b> — 파이썬은 U+001C~U+001F(파일·그룹·레코드·유닛 구분자)도 공백으로 보지만 Java {@code
   * \p{IsWhite_Space}}는 아니다. LLM 제목에 제어문자가 올 일이 사실상 없고 파이썬이 최종 필터를 한 번 더 하므로 실질 영향은 없다.
   */
  private static final Pattern WHITESPACE =
      Pattern.compile("\\s+", Pattern.UNICODE_CHARACTER_CLASS);

  private final TodoSuggestionExposureRepository exposureRepository;
  private final RoomRepository roomRepository;

  TodoSuggestionExposureStore(
      TodoSuggestionExposureRepository exposureRepository, RoomRepository roomRepository) {
    this.exposureRepository = exposureRepository;
    this.roomRepository = roomRepository;
  }

  /** AI 서버의 {@code excluded_todos}로 나갈 제목들 — 이 방의 최근 {@value #MAX_EXCLUDED}개. */
  public List<String> recentTitles(Long roomId) {
    return exposureRepository.findRecentTitles(roomId, PageRequest.of(0, MAX_EXCLUDED));
  }

  /**
   * 방금 반환한 후보들을 "노출함"으로 남긴다.
   *
   * <p>중복은 여기서 걸러 넣지 않는다. AI 서버의 {@code filter_candidates}가 이미 우리가 보낸 목록과 겹치지 않게 돌려주므로 주 메커니즘이 아니라,
   * 계약이 깨졌을 때 {@value #MAX_EXCLUDED}칸을 같은 제목으로 낭비하지 않기 위한 안전망이다.
   */
  @Transactional
  public void record(Long roomId, List<TodoSuggestionCandidate> candidates) {
    if (candidates.isEmpty()) {
      return;
    }

    Set<String> known = new HashSet<>();
    for (String title : recentTitles(roomId)) {
      known.add(normalize(title));
    }

    // 프록시라 SELECT 가 나가지 않는다 — FK 를 채우는 것이 전부다. 방 존재·멤버십은 호출 전에 이미 검증됐다.
    Room room = roomRepository.getReferenceById(roomId);
    List<TodoSuggestionExposure> fresh = new ArrayList<>();
    for (TodoSuggestionCandidate candidate : candidates) {
      String title = truncate(candidate.title());
      if (title == null || !known.add(normalize(title))) {
        continue;
      }
      fresh.add(new TodoSuggestionExposure(room, title));
    }

    exposureRepository.saveAll(fresh);
  }

  /** 빈 제목은 저장하지 않는다 — 정규화하면 빈 문자열이 되어 이후 모든 후보를 제외해버린다. */
  private static String truncate(String title) {
    if (title == null) {
      return null;
    }
    String trimmed = title.strip();
    if (trimmed.isEmpty()) {
      return null;
    }
    return trimmed.length() <= MAX_TITLE ? trimmed : trimmed.substring(0, MAX_TITLE);
  }

  /**
   * 중복 판정용 — <b>글자가 같은 것만</b> 잡는다.
   *
   * <p>의미가 같고 표현만 다른 것은 AI 서버가 임베딩 코사인으로 한 번 더 거른다({@code ai/src/modi_ai/suggest.py} 의 {@code
   * drop_semantic_duplicates}). <b>RAG 2단계와는 다른 작업이다</b> — 그쪽은 "어느 자료를 프롬프트에 넣을까"이고 이쪽은 "어느 후보를
   * 버릴까"다 ({@code ai/docs/DECISIONS.md} 의 (A)/(B) 분리).
   */
  static String normalize(String title) {
    return WHITESPACE.matcher(title).replaceAll("").toLowerCase(Locale.ROOT);
  }
}
