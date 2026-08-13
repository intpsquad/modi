package com.nomara.modi.server.domain.todo.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveItemTag;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemTagRepository;
import com.nomara.modi.server.domain.category.entity.Category;
import com.nomara.modi.server.domain.category.repository.CategoryRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.client.AiSuggestPayload;
import com.nomara.modi.server.domain.todo.client.TodoSuggestionClient;
import com.nomara.modi.server.domain.todo.dto.TodoSuggestionCandidate;
import com.nomara.modi.server.domain.todo.dto.TodoSuggestionResponse;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.entity.TodoSuggestionExposure;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import com.nomara.modi.server.domain.todo.repository.TodoSuggestionExposureRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/**
 * S-16-B 추천의 재료 수집·인가를 검증한다. AI 서버 호출은 가짜 클라이언트로 대체한다 — 실제 FastAPI·LLM을 부르지 않아야 크레딧을 태우지 않고 CI에서도
 * 같은 결과가 나온다.
 *
 * <p><b>다른 서비스 테스트와 달리 Testcontainers를 쓰지 않고 H2(엔티티 기준 DDL)로 돈다.</b> 이 테스트의 관심사는 "무엇이 AI 서버로
 * 나가는가"이지 스키마가 아니고, 스키마 정합성은 {@code SchemaValidationTest}가 Flyway 기준으로 이미 검증한다. Docker 없이 어디서나 도는
 * 편이 이 검증에는 더 낫다(README "server/ 실행"의 Docker Desktop 호환성 주의 참고).
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TodoSuggestionServiceTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    // 기본 테스트 프로필은 ddl-auto: none + flyway off라 테이블이 없다. 엔티티에서 만들어 쓴다.
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    // 🔴 이 클래스는 **운영 기본값과 다른 설정**으로 돈다(2026-08-09). 운영은 false다.
    // 여기서 켜는 이유는 의 보장(ExcludedTodos 묶음)을 계속 테스트하기 위해서다 —
    // 되돌리는 길이 설정 한 줄인데 그때 동작을 확인할 수단이 없으면 안 된다.
    // 기본값(끔) 쪽은 TodoSuggestionPayloadLoaderTest 가 맡는다.
    // (@Nested 에 @TestPropertySource 를 달아봤지만 컨텍스트가 갈리지 않아 안 먹었다.)
    registry.add("modi.todo.suggestion.exclude-recent", () -> "true");
  }

  /** 호출을 기록하는 가짜. 무엇이 AI 서버로 나가는지를 그대로 들여다보기 위해 Mockito 대신 손으로 만든다. */
  static class RecordingClient implements TodoSuggestionClient {
    AiSuggestPayload received;
    List<TodoSuggestionCandidate> toReturn = List.of();

    @Override
    public List<TodoSuggestionCandidate> suggest(AiSuggestPayload payload) {
      this.received = payload;
      return toReturn;
    }
  }

  @TestConfiguration
  static class FakeClientConfig {
    @Bean
    @Primary
    RecordingClient recordingClient() {
      return new RecordingClient();
    }
  }

  @Autowired private TodoSuggestionService todoSuggestionService;
  @Autowired private RecordingClient client;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private CategoryRepository categoryRepository;
  @Autowired private TodoRepository todoRepository;
  @Autowired private ArchiveFolderRepository archiveFolderRepository;
  @Autowired private ArchiveItemRepository archiveItemRepository;
  @Autowired private ArchiveItemTagRepository archiveItemTagRepository;
  @Autowired private TodoSuggestionExposureRepository exposureRepository;

  private static int counter = 0;

  @BeforeEach
  void resetClient() {
    client.received = null;
    client.toReturn = List.of();
  }

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter),
            null,
            "오픽 IH 달성",
            "8월 중순 접수",
            LocalDate.now(),
            LocalDate.now().plusDays(20)));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  @Test
  void nonMemberCannotAskForSuggestions() {
    Room room = room();
    User outsider = user("uid-suggest-outsider");

    ApiException error =
        catchThrowableOfType(
            () -> todoSuggestionService.suggest(outsider.getId(), room.getId()),
            ApiException.class);

    assertThat(error.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
    assertThat(client.received).isNull();
  }

  @Test
  void sendsRoomCategoriesTodosAndArchiveToAiServer() {
    Room room = room();
    User member = user("uid-suggest-member");
    roomMemberRepository.save(new RoomMember(room, member));
    categoryRepository.save(new Category(room, "공부"));
    todoRepository.save(new Todo(room, null, "교재 사기", null));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "자료"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "오픽 공부법", null, "답변 틀을 만들자", null, null, member));
    archiveItemTagRepository.save(new ArchiveItemTag(item, "오픽"));

    todoSuggestionService.suggest(member.getId(), room.getId());

    AiSuggestPayload sent = client.received;
    assertThat(sent.room().goal()).isEqualTo("오픽 IH 달성");
    assertThat(sent.room().goalDetail()).isEqualTo("8월 중순 접수");
    assertThat(sent.categories()).containsExactly("공부");
    assertThat(sent.existingTodos()).containsExactly("교재 사기");
    assertThat(sent.archive()).hasSize(1);
    assertThat(sent.archive().getFirst().title()).isEqualTo("오픽 공부법");
    // 요약이 없는 자료라 본문이 그대로 실린다(V5 이전 등록분과 같은 상태).
    assertThat(sent.archive().getFirst().content()).isEqualTo("답변 틀을 만들자");
    assertThat(sent.archive().getFirst().tags()).containsExactly("오픽");
  }

  @Test
  void doesNotLeakOtherRoomsTodosOrArchive() {
    Room mine = room();
    Room other = room();
    User member = user("uid-suggest-isolation");
    roomMemberRepository.save(new RoomMember(mine, member));
    todoRepository.save(new Todo(other, null, "남의 방 투두", null));
    ArchiveFolder otherFolder = archiveFolderRepository.save(new ArchiveFolder(other, "남의 자료"));
    archiveItemRepository.save(
        new ArchiveItem(otherFolder, other, "남의 자료", null, "본문", null, null, member));

    todoSuggestionService.suggest(member.getId(), mine.getId());

    assertThat(client.received.existingTodos()).isEmpty();
    assertThat(client.received.archive()).isEmpty();
  }

  @Test
  void sendsCrawlPendingItemsWithNullBodyInsteadOfDroppingThem() {
    Room room = room();
    User member = user("uid-suggest-pending");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "자료"));
    archiveItemRepository.save(
        ArchiveItem.pending(folder, room, "아직 크롤링 전", "https://example.com", member));

    todoSuggestionService.suggest(member.getId(), room.getId());

    assertThat(client.received.archive()).hasSize(1);
    assertThat(client.received.archive().getFirst().content()).isNull();
  }

  /**
   * 추천 입력 = <b>요약과 본문 중 짧은 쪽</b>(2026-07-30 확정).
   *
   * <p>요약을 쓰는 것이 이 티켓의 목적이지만, 요약이 없는 자료가 정상적으로 존재하므로 임계값 상수를 만들지 않고 "짧은 쪽" 규칙 하나로 전부 처리한다.
   */
  @Nested
  class ContentSelection {

    private ArchiveItem savedItem(Room room, User member, String bodyText, String summary) {
      ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "자료"));
      ArchiveItem item = new ArchiveItem(folder, room, "제목", null, bodyText, null, null, member);
      item.applySummary(summary);
      return archiveItemRepository.save(item);
    }

    private String sentContent(String bodyText, String summary) {
      Room room = room();
      User member = user("uid-content-" + Math.abs((bodyText + summary).hashCode()));
      roomMemberRepository.save(new RoomMember(room, member));
      savedItem(room, member, bodyText, summary);

      todoSuggestionService.suggest(member.getId(), room.getId());

      return client.received.archive().getFirst().content();
    }

    @Test
    void summaryWinsWhenItIsShorterThanTheBody() {
      // 이게 정상 경로다 — 본문 대신 요약이 나가면서 프롬프트가 줄어든다.
      assertThat(sentContent("가".repeat(500), "짧은 요약")).isEqualTo("짧은 요약");
    }

    @Test
    void bodyWinsWhenTheSummaryIsLonger() {
      // 본문이 한 줄짜리면 요약이 오히려 더 길다. 그때 요약을 쓰면 손해다.
      assertThat(sentContent("한 줄", "이 글은 한 줄로만 되어 있는 아주 짧은 자료다.")).isEqualTo("한 줄");
    }

    @Test
    void bodyIsUsedWhenThereIsNoSummary() {
      // V5 이전에 등록된 자료 · 요약 호출 실패가 이 상태다.
      assertThat(sentContent("본문만 있다", null)).isEqualTo("본문만 있다");
    }

    @Test
    void summaryIsUsedWhenThereIsNoBody() {
      assertThat(sentContent(null, "요약만 있다")).isEqualTo("요약만 있다");
    }
  }

  /**
   * 이미 노출한 후보를 다음 추천에서 제외한다. 이전까지 {@code excludedTodos}는 항상 빈 배열이었고, 그래서 추천을 두 번 누르면 같은 후보가 또 나왔다.
   *
   * <p>AI 서버 쪽은 원래부터 준비돼 있었다 — 프롬프트에 실어 보내고({@code suggest.py}) {@code filter_candidates}가 코드로도
   * 거른다. 여기서 재는 것은 <b>Spring이 그 목록을 실제로 채워 보내는가</b>다.
   *
   * <p>🔴 <b>2026-08-09부터 이 동작은 운영 기본값이 아니다.</b> {@code modi.todo.suggestion.exclude-recent} 기본값이
   * {@code false}로 바뀌었다(사용자 확정 — 회차마다 후보가 줄어 "매번 6~8개" 요구를 못 맞췄다). 이 묶음이 도는 것은 <b>바깥 클래스가
   * {@code @DynamicPropertySource}로 플래그를 켜두기 때문</b>이다.
   *
   * <p>테스트를 지우지 않고 남기는 이유: 되돌리는 길이 설정 한 줄인데 그때 이 보장이 살아 있는지 확인할 수단이 없으면 안 된다. <b>기본값(끔) 쪽 검증은
   * {@code TodoSuggestionPayloadLoaderTest.doesNotExcludeAlreadySuggestedTitlesByDefault}</b>가 맡는다.
   */
  @Nested
  class ExcludedTodos {

    @Test
    void firstSuggestionHasNothingToExclude() {
      // 모든 방이 반드시 한 번 지나는 경로다. null 이 아니라 빈 목록이어야 한다.
      Room room = room();
      User member = user("uid-excluded-first");
      roomMemberRepository.save(new RoomMember(room, member));

      todoSuggestionService.suggest(member.getId(), room.getId());

      assertThat(client.received.excludedTodos()).isEmpty();
    }

    @Test
    void secondSuggestionExcludesWhatTheFirstOneReturned() {
      // 이 티켓의 본체. 1회차가 낸 후보가 2회차 입력의 excluded_todos 로 나가야 한다.
      Room room = room();
      User member = user("uid-excluded-second");
      roomMemberRepository.save(new RoomMember(room, member));
      client.toReturn =
          List.of(
              new TodoSuggestionCandidate("답변 틀 만들기", "공부", null),
              new TodoSuggestionCandidate("교재 3회독", "공부", null));

      todoSuggestionService.suggest(member.getId(), room.getId());
      client.toReturn = List.of();
      todoSuggestionService.suggest(member.getId(), room.getId());

      assertThat(client.received.excludedTodos()).containsExactlyInAnyOrder("답변 틀 만들기", "교재 3회독");
    }

    @Test
    void oneMembersExposureExcludesItForEveryoneInTheRoom() {
      // 기록은 방 단위다(유저 단위 아님) — 방 멤버는 동일 권한이므로 A가 본 후보를 B에게 다시
      // 보여줄 이유가 없다. 이 규칙은 지금 "user_id 컬럼이 없다"는 사실로만 지켜지고 있어서,
      // 나중에 누가 유저별로 쪼개도 아무 테스트가 깨지지 않는다는 리뷰 지적을 받아 추가했다.
      Room room = room();
      User memberA = user("uid-excluded-member-a");
      User memberB = user("uid-excluded-member-b");
      roomMemberRepository.save(new RoomMember(room, memberA));
      roomMemberRepository.save(new RoomMember(room, memberB));
      client.toReturn = List.of(new TodoSuggestionCandidate("A가 본 후보", "공부", null));
      todoSuggestionService.suggest(memberA.getId(), room.getId());

      client.toReturn = List.of();
      todoSuggestionService.suggest(memberB.getId(), room.getId());

      assertThat(client.received.excludedTodos()).containsExactly("A가 본 후보");
    }

    @Test
    void doesNotExcludeCandidatesFromAnotherRoom() {
      // 방마다 목표가 다르다 — 남의 방 후보를 제외하면 엉뚱하게 좋은 추천을 막는다.
      Room mine = room();
      Room other = room();
      User member = user("uid-excluded-isolation");
      roomMemberRepository.save(new RoomMember(mine, member));
      roomMemberRepository.save(new RoomMember(other, member));
      client.toReturn = List.of(new TodoSuggestionCandidate("남의 방 후보", "공부", null));
      todoSuggestionService.suggest(member.getId(), other.getId());

      client.toReturn = List.of();
      todoSuggestionService.suggest(member.getId(), mine.getId());

      assertThat(client.received.excludedTodos()).isEmpty();
    }

    @Test
    void sendsAtMostTheMostRecentWindowOfTitles() {
      // 상한을 조회로만 지키므로(오래된 행을 지우지 않는다) 이 단언이 그 상한의 유일한 증거다.
      // 이름에 숫자를 박지 않는다 — 2026-08-03 에 50 에서 16 으로 줄이며 이름만 남는 사고를 겪었다.
      Room room = room();
      User member = user("uid-excluded-cap");
      roomMemberRepository.save(new RoomMember(room, member));
      for (int i = 1; i <= TodoSuggestionExposureStore.MAX_EXCLUDED + 1; i++) {
        exposureRepository.saveAndFlush(new TodoSuggestionExposure(room, "후보-" + i));
      }

      todoSuggestionService.suggest(member.getId(), room.getId());

      // 상한보다 하나 더 넣었으니 가장 오래된 하나(후보-1)만 밀려나야 한다. 같은 밀리초에 저장돼도
      // 쿼리의 id desc 타이브레이커가 순서를 결정해준다 — sleep 으로 시각을 벌릴 필요가 없다.
      assertThat(client.received.excludedTodos())
          .hasSize(TodoSuggestionExposureStore.MAX_EXCLUDED)
          .contains("후보-" + (TodoSuggestionExposureStore.MAX_EXCLUDED + 1))
          .doesNotContain("후보-1");
    }
  }

  @Test
  void returnsCandidatesFromAiServerAsIs() {
    Room room = room();
    User member = user("uid-suggest-returns");
    roomMemberRepository.save(new RoomMember(room, member));
    client.toReturn = List.of(new TodoSuggestionCandidate("답변 틀 만들기", "공부", 12L));

    TodoSuggestionResponse response = todoSuggestionService.suggest(member.getId(), room.getId());

    assertThat(response.candidates()).hasSize(1);
    assertThat(response.candidates().getFirst().title()).isEqualTo("답변 틀 만들기");
    assertThat(response.candidates().getFirst().category()).isEqualTo("공부");
    assertThat(response.candidates().getFirst().sourceItemId()).isEqualTo(12L);
  }
}
