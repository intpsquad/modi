package com.nomara.modi.server.domain.todo.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveLike;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveLikeRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.client.AiSuggestPayload;
import com.nomara.modi.server.domain.todo.dto.TodoSuggestionCandidate;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 추천 페이로드가 <b>자료 선별 4축</b>을 실제 DB에서 제대로 길어 오는지.
 *
 * <p>가짜 리포지토리로는 의미가 없어 Testcontainers를 쓴다. 좋아요 수는 별도 테이블 집계이고, {@code embedding}은 {@code real[]} ↔
 * {@code float[]} 왕복이며, {@code createdAt}은 {@code @CreationTimestamp}가 채우는 값이라 <b>셋 다 진짜
 * Postgres에서만 증명된다.</b>
 */
@Testcontainers
@SpringBootTest
class TodoSuggestionPayloadLoaderTest {

  @Container @ServiceConnection
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

  @Container
  @ServiceConnection(name = "redis")
  static GenericContainer<?> redis =
      new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.enabled", () -> "true");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
  }

  @Autowired private TodoSuggestionPayloadLoader loader;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private ArchiveFolderRepository archiveFolderRepository;
  @Autowired private ArchiveItemRepository archiveItemRepository;
  @Autowired private ArchiveLikeRepository archiveLikeRepository;
  @Autowired private TodoSuggestionExposureStore exposureStore;

  private static int counter = 0;

  private record Fixture(Room room, User member, ArchiveFolder folder) {}

  private Fixture fixture() {
    Room room =
        roomRepository.save(
            new Room(
                "방-" + (++counter),
                null,
                "목표",
                null,
                LocalDate.now(),
                LocalDate.now().plusDays(10)));
    User member = userRepository.save(new User("uid-payload-" + counter, "이름", null));
    roomMemberRepository.save(new RoomMember(room, member));
    return new Fixture(room, member, archiveFolderRepository.save(new ArchiveFolder(room, "폴더")));
  }

  private ArchiveItem item(Fixture f, String title) {
    return archiveItemRepository.save(
        new ArchiveItem(f.folder(), f.room(), title, null, "본문", null, null, f.member()));
  }

  private AiSuggestPayload.ArchiveInfo find(AiSuggestPayload payload, String title) {
    return payload.archive().stream()
        .filter(info -> info.title().equals(title))
        .findFirst()
        .orElseThrow();
  }

  @Test
  void carriesLikeCountPerItemAndZeroForUnliked() {
    Fixture f = fixture();
    User liker = userRepository.save(new User("uid-liker-" + counter, "좋아요", null));
    ArchiveItem liked = item(f, "좋아요 둘");
    ArchiveItem ignored = item(f, "좋아요 없음");
    archiveLikeRepository.save(new ArchiveLike(liked, f.member()));
    archiveLikeRepository.save(new ArchiveLike(liked, liker));

    AiSuggestPayload payload = loader.load(f.member().getId(), f.room().getId());

    assertThat(find(payload, liked.getTitle()).likeCount()).isEqualTo(2L);
    // 좋아요가 없는 항목은 집계 쿼리 결과에 아예 없다 — 0으로 채워지지 않으면 여기서 터진다.
    assertThat(find(payload, ignored.getTitle()).likeCount()).isZero();
  }

  /**
   * 🔴 <b>이미 노출한 후보를 다시 제외하지 않는다</b>(2026-08-09 사용자 확정 되돌림).
   *
   * <p>이 단언이 실패하면 누군가 {@code modi.todo.suggestion.exclude-recent} 기본값을 되켰다는 뜻이다. 버그로 보고 고치기 전에
   * {@code TodoSuggestionPayloadLoader.excludeRecent} javadoc 을 먼저 읽을 것 — 회차마다 후보가 줄던 원인이라
   * <b>일부러</b> 껐다.
   *
   * <p>노출을 실제로 기록한 뒤에 확인한다. 기록 자체는 계속 남아야 하므로(플래그를 되켰을 때 빈 목록에서 시작하지 않도록) "기록은 됐는데 페이로드에는 안 실린다"가
   * 정확한 사양이다.
   */
  @Test
  void doesNotExcludeAlreadySuggestedTitlesByDefault() {
    Fixture f = fixture();
    item(f, "자료");
    exposureStore.record(
        f.room().getId(), List.of(new TodoSuggestionCandidate("이미 보여준 후보", null, null)));

    AiSuggestPayload payload = loader.load(f.member().getId(), f.room().getId());

    assertThat(payload.excludedTodos()).isEmpty();
    // 기록은 남아 있어야 한다 — 플래그를 되켰을 때 곧바로 되살아나야 하기 때문이다.
    assertThat(exposureStore.recentTitles(f.room().getId())).containsExactly("이미 보여준 후보");
  }

  @Test
  void carriesPinnedFlag() {
    Fixture f = fixture();
    ArchiveItem pinned = item(f, "핀 꽂음");
    pinned.pin();
    archiveItemRepository.save(pinned);
    ArchiveItem plain = item(f, "핀 없음");

    AiSuggestPayload payload = loader.load(f.member().getId(), f.room().getId());

    assertThat(find(payload, pinned.getTitle()).pinned()).isTrue();
    assertThat(find(payload, plain.getTitle()).pinned()).isFalse();
  }

  @Test
  void carriesEmbeddingRoundTrippedThroughPostgres() {
    Fixture f = fixture();
    ArchiveItem embedded = item(f, "벡터 있음");
    embedded.applyEmbedding(new float[] {0.5f, -0.25f, 0.125f});
    archiveItemRepository.save(embedded);

    AiSuggestPayload payload = loader.load(f.member().getId(), f.room().getId());

    assertThat(find(payload, embedded.getTitle()).embedding())
        .containsExactly(0.5f, -0.25f, 0.125f);
  }

  /** 임베딩 {@code null}은 정상인 경우가 넷 있다(V7 주석). 그 자료도 페이로드에 남아야 유사도 외 세 축으로 후보가 된다. */
  @Test
  void keepsItemsWithoutEmbedding() {
    Fixture f = fixture();
    ArchiveItem bare = item(f, "벡터 없음");

    AiSuggestPayload payload = loader.load(f.member().getId(), f.room().getId());

    AiSuggestPayload.ArchiveInfo info = find(payload, bare.getTitle());
    assertThat(info.embedding()).isNull();
    assertThat(info.createdAt()).isNotNull();
  }

  @Test
  void carriesCreatedAtForRecencyAxis() {
    Fixture f = fixture();
    ArchiveItem first = item(f, "먼저");
    ArchiveItem second = item(f, "나중");

    AiSuggestPayload payload = loader.load(f.member().getId(), f.room().getId());

    assertThat(find(payload, second.getTitle()).createdAt())
        .isAfterOrEqualTo(find(payload, first.getTitle()).createdAt());
  }

  /**
   * 방 단위 집계 쿼리가 <b>다른 방의 좋아요를 끌어오지 않는지</b>.
   *
   * <p>⚠️ 이 테스트는 <b>쿼리 개수를 재지 않는다</b> — 항목마다 세는 N+1 구현도 통과한다. 쿼리 카운트가 필요하면 {@code
   * hibernate.generate_statistics}를 켜야 하는데 이 저장소에는 그 인프라가 없다.
   */
  @Test
  void doesNotLeakLikesFromOtherRooms() {
    Fixture mine = fixture();
    Fixture other = fixture();
    ArchiveItem theirs = item(other, "남의 방 자료");
    archiveLikeRepository.save(new ArchiveLike(theirs, other.member()));
    ArchiveItem ours = item(mine, "내 방 자료");

    AiSuggestPayload payload = loader.load(mine.member().getId(), mine.room().getId());

    assertThat(payload.archive())
        .extracting(AiSuggestPayload.ArchiveInfo::title)
        .containsExactly(ours.getTitle());
    assertThat(find(payload, ours.getTitle()).likeCount()).isZero();
  }
}
