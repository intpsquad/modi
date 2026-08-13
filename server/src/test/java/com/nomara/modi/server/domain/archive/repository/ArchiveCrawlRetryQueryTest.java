package com.nomara.modi.server.domain.archive.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.data.domain.PageRequest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.util.ReflectionTestUtils;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 재시도 배치가 쓰는 세 쿼리를 <b>실제 Postgres</b> 로 잰다(2026-08-06).
 *
 * <p>🔴 <b>왜 목으로는 부족한가.</b> {@code ArchiveCrawlRetrySchedulerTest} 는 리포지토리를 목으로 두므로 "무엇을 넘기는가"만 재고
 * <b>쿼리가 무엇을 돌려주는가</b>는 재지 못한다. 부등호를 뒤집거나 {@code PENDING} 조건을 빼도 거기서는 전부 초록이다 — 운영에서는 아무것도 안 집히거나
 * 끝난 항목까지 집어 외부 사이트를 때린다.
 *
 * <p>Flyway 로 V15 까지 올린 스키마를 그대로 쓴다. 부분 인덱스가 실제로 만들어지는지도 여기서 함께 확인된다(안 되면 마이그레이션이 실패한다).
 */
@Testcontainers
@SpringBootTest
class ArchiveCrawlRetryQueryTest {

  @Container @ServiceConnection
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.enabled", () -> "true");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
  }

  private static int counter = 0;

  @Autowired private ArchiveItemRepository archiveItemRepository;
  @Autowired private ArchiveFolderRepository archiveFolderRepository;
  @Autowired private RoomRepository roomRepository;

  @Test
  void 기한이_된_PENDING_만_집는다() {
    Long due = saved(retryAt(minutesAgo(1)));
    Long notYet = saved(retryAt(minutesFromNow(30)));
    Long neverScheduled = saved(item()); // 마이그레이션 전부터 있던 행이 이 모양이다
    Long alreadyFailed = saved(failedButStillScheduled());

    List<Long> ids = archiveItemRepository.findIdsDueForCrawlRetry(Instant.now(), page(50));

    assertThat(ids).contains(due).doesNotContain(notYet, neverScheduled, alreadyFailed);
  }

  @Test
  void 오래_기다린_것부터_집는다() {
    // 상한에 걸려 잘릴 때 뒤로 밀린 항목이 굶지 않게 하는 것이 이 정렬의 목적이다.
    Long later = saved(retryAt(minutesAgo(1)));
    Long earlier = saved(retryAt(minutesAgo(30)));

    List<Long> ids = archiveItemRepository.findIdsDueForCrawlRetry(Instant.now(), page(50));

    assertThat(ids).containsSubsequence(earlier, later);
  }

  @Test
  void 상한만큼만_집는다() {
    saved(retryAt(minutesAgo(3)));
    saved(retryAt(minutesAgo(2)));
    saved(retryAt(minutesAgo(1)));

    assertThat(archiveItemRepository.findIdsDueForCrawlRetry(Instant.now(), page(2))).hasSize(2);
  }

  @Test
  void 예약을_지워도_본문과_상태는_그대로다() {
    // 벌크 UPDATE 가 한 컬럼만 건드린다는 것이 요점이다 — 엔티티 더티체킹이었다면
    // 비동기 처리기가 먼저 쓴 본문·상태를 옛 값으로 되돌려 쓸 수 있다.
    ArchiveItem item = retryAt(minutesAgo(1));
    item.markCrawlDone("긁은 제목", "긁은 본문", "test.com", null);
    Long id = saved(item);

    archiveItemRepository.clearNextCrawlAt(List.of(id));

    ArchiveItem reloaded = archiveItemRepository.findById(id).orElseThrow();
    assertThat(reloaded.getNextCrawlAt()).isNull();
    assertThat(reloaded.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
    assertThat(reloaded.getBodyText()).isEqualTo("긁은 본문");
  }

  @Test
  void 다시_줄_세우면_그_시각에_다시_잡힌다() {
    Long id = saved(retryAt(minutesAgo(1)));
    archiveItemRepository.clearNextCrawlAt(List.of(id));

    archiveItemRepository.rescheduleCrawl(List.of(id), minutesAgo(1));

    assertThat(archiveItemRepository.findIdsDueForCrawlRetry(Instant.now(), page(50))).contains(id);
  }

  @Test
  void 다시_줄_세워도_재시도_횟수는_안_오른다() {
    // 실패한 것이 아니라 보내지도 못한 것이다 — 여기서 올리면 상한을 헛되게 소진한다.
    ArchiveItem item = retryAt(minutesAgo(1));
    int before = item.getCrawlRetries();
    Long id = saved(item);

    archiveItemRepository.rescheduleCrawl(List.of(id), minutesFromNow(5));

    assertThat(archiveItemRepository.findById(id).orElseThrow().getCrawlRetries())
        .isEqualTo(before);
  }

  // ------------------------------------------------------------------------ 픽스처

  private ArchiveItem item() {
    Room room =
        roomRepository.save(
            new Room(
                "방-" + (++counter),
                null,
                "목표",
                null,
                LocalDate.now(),
                LocalDate.now().plusDays(10)));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "링크 모음"));
    return ArchiveItem.pending(
        folder, room, "https://example.com/a", "https://example.com/a", null);
  }

  private ArchiveItem retryAt(Instant next) {
    ArchiveItem item = item();
    item.scheduleCrawlRetry(next);
    return item;
  }

  /**
   * 끝난 항목에 예약 시각만 남은 상태.
   *
   * <p>정상 경로로는 안 생긴다({@code markCrawlFailed} 가 시각을 비운다) — 배치의 예약 지우기와 처리기의 상태 변경이 서로 다른 트랜잭션이라 이론상
   * 가능한 어긋남을 재현한 것이다. 쿼리의 {@code PENDING} 조건이 그 방어다.
   */
  private ArchiveItem failedButStillScheduled() {
    ArchiveItem item = retryAt(minutesAgo(1));
    ReflectionTestUtils.setField(item, "crawlStatus", ArchiveItem.CrawlStatus.FAILED);
    return item;
  }

  private Long saved(ArchiveItem item) {
    return archiveItemRepository.save(item).getId();
  }

  private static Instant minutesAgo(int minutes) {
    return Instant.now().minusSeconds(minutes * 60L);
  }

  private static Instant minutesFromNow(int minutes) {
    return Instant.now().plusSeconds(minutes * 60L);
  }

  private static PageRequest page(int size) {
    return PageRequest.of(0, size);
  }
}
