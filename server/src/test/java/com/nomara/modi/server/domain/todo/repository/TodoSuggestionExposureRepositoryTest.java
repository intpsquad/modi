package com.nomara.modi.server.domain.todo.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.entity.TodoSuggestionExposure;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/**
 * 노출 기록 조회 쿼리. 이 쿼리가 틀리면 증상이 조용하다 — 추천은 정상 동작하고 중복만 계속 나오므로, 셋을 각각 못 박아둔다: <b>최신순</b> · <b>개수
 * 제한</b> · <b>방 격리</b>.
 *
 * <p>{@code TodoSuggestionServiceTest}와 같은 이유로 H2에서 돈다(스키마 정합성은 {@code SchemaValidationTest} 담당).
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class TodoSuggestionExposureRepositoryTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
  }

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

  /**
   * 한 건씩 flush 해서 id 가 저장 순서대로 증가하게 한다. {@code @CreationTimestamp}는 같은 밀리초에 저장된 행에 동일한 값을 줄 수 있는데,
   * 쿼리의 {@code id desc} 타이브레이커가 그 경우의 순서를 결정한다 — 그래서 시각을 벌리는 sleep 이 필요 없다.
   */
  private void expose(Room room, String... titles) {
    for (String title : titles) {
      exposureRepository.saveAndFlush(new TodoSuggestionExposure(room, title));
    }
  }

  @Test
  void returnsTitlesNewestFirst() {
    Room room = room();
    expose(room, "가장 오래된 것", "중간", "가장 최근");

    List<String> titles = exposureRepository.findRecentTitles(room.getId(), PageRequest.of(0, 10));

    assertThat(titles).containsExactly("가장 최근", "중간", "가장 오래된 것");
  }

  @Test
  void honoursTheRequestedLimit() {
    // 상한은 이 pageable 로만 걸린다 — 오래된 행을 지우지 않기 때문이다(V6 주석 ③).
    // 값 자체는 TodoSuggestionExposureStore.MAX_EXCLUDED 가 정한다.
    Room room = room();
    expose(room, "하나", "둘", "셋");

    List<String> titles = exposureRepository.findRecentTitles(room.getId(), PageRequest.of(0, 2));

    assertThat(titles).containsExactly("셋", "둘");
  }

  @Test
  void doesNotLeakTitlesAcrossRooms() {
    // 방마다 목표가 다르므로 다른 방의 후보를 제외 목록에 넣으면 엉뚱한 추천을 막는다.
    Room mine = room();
    Room other = room();
    expose(mine, "내 방 후보");
    expose(other, "남의 방 후보");

    List<String> titles = exposureRepository.findRecentTitles(mine.getId(), PageRequest.of(0, 10));

    assertThat(titles).containsExactly("내 방 후보");
  }

  @Test
  void returnsEmptyForARoomThatNeverAskedForSuggestions() {
    // 첫 추천에서 반드시 지나는 경로다. null 이 아니라 빈 목록이어야 한다.
    // 여기서 limit 값은 의미가 없다(빈 방) — 상한이 바뀔 때 같이 고쳐야 하는 것처럼 보이지 않게 10 으로 둔다.
    assertThat(exposureRepository.findRecentTitles(room().getId(), PageRequest.of(0, 10)))
        .isEmpty();
  }
}
