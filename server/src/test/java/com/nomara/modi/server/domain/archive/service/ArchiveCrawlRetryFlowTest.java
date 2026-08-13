package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.archive.client.CompositeUrlCrawler;
import com.nomara.modi.server.domain.archive.client.CrawlResult;
import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.concurrent.Executor;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.core.task.SyncTaskExecutor;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 차단 → 대기 → 자동 성공까지 <b>전 구간</b>을 한 번 돌린다(2026-08-06).
 *
 * <p>🔴 <b>왜 이것이 따로 필요한가.</b> 처리기·배치·쿼리는 각자 테스트가 있지만 셋이 <b>이어져 돌아가는지</b>는 아무도 재지 않는다. 이 기능의 가치는 그
 * 연결에 전부 걸려 있다 — 처리기가 남긴 상태를 배치가 못 찾거나, 배치가 넘긴 것을 처리기가 다르게 해석하면 사용자에게는 여전히 "분석 실패"가 뜬다.
 *
 * <p><b>시계를 앞당기는 방식</b>: 20분을 기다리는 대신 {@code rescheduleCrawl} 로 기한을 과거로 당긴다. 배치 간격이나 재시도 간격을 테스트
 * 때문에 설정값으로 빼지 않기 위해서다 — 운영 코드는 그대로 두고 시간만 움직인다.
 *
 * <p><b>동기 실행기로 바꾼다</b>: {@code @Async} 그대로면 언제 끝나는지 알 수 없어 대기 루프가 필요해진다. 여기서 재는 것은 "어느 스레드에서 도는가"가
 * 아니라 상태 전이라, 같은 스레드에서 돌려 결정적으로 만든다.
 */
@Testcontainers
@SpringBootTest(properties = "spring.main.allow-bean-definition-overriding=true")
class ArchiveCrawlRetryFlowTest {

  @Container @ServiceConnection
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.enabled", () -> "true");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
    // 배치를 사실상 재우고 테스트가 직접 부른다. 안 재우면 컨텍스트가 뜬 뒤 5분마다 깨어나
    // ② 와 ③ 사이에 끼어들어 가짜 크롤러의 두 번째 응답을 가로챈다(2026-08-06 리뷰).
    registry.add("modi.archive.crawl-retry-scan-interval", () -> "3600000");
  }

  /** 크롤링을 같은 스레드에서 끝내 상태 전이를 결정적으로 관찰한다. */
  @TestConfiguration
  static class SyncExecutorConfig {

    @Bean(name = "archiveCrawlExecutor")
    Executor archiveCrawlExecutor() {
      return new SyncTaskExecutor();
    }
  }

  /** 인스타 차단을 흉내낸다 — 첫 호출은 막히고, 두 번째는 풀린 뒤다. */
  @MockitoBean private CompositeUrlCrawler urlCrawler;

  @Autowired private ArchiveCrawlProcessor processor;
  @Autowired private ArchiveCrawlRetryScheduler scheduler;
  @Autowired private ArchiveItemRepository archiveItemRepository;
  @Autowired private ArchiveFolderRepository archiveFolderRepository;
  @Autowired private RoomRepository roomRepository;

  @Test
  void 차단됐다가_풀리면_사용자는_분석_실패를_보지_않는다() {
    when(urlCrawler.crawl(any()))
        .thenThrow(CrawlException.retryable("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요"))
        .thenReturn(new CrawlResult("풀린 뒤 제목", "풀린 뒤 본문", null, "instagram.com"));
    Long id = savedPendingItem("https://www.instagram.com/p/풀리는것/");

    // ① 공유 등록 직후의 크롤링 — 차단에 걸린다.
    processor.process(id);

    ArchiveItem afterBlock = reload(id);
    assertThat(afterBlock.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.PENDING);
    assertThat(afterBlock.getCrawlRetries()).isEqualTo(1);
    assertThat(afterBlock.getNextCrawlAt()).isNotNull();

    // ② 20분이 흘렀다고 치고 기한을 당긴다. 배치는 아직 안 돌았다.
    archiveItemRepository.rescheduleCrawl(List.of(id), Instant.now().minusSeconds(1));

    // ③ 배치가 돈다 — 이번엔 차단이 풀려 있다.
    scheduler.retryDueCrawls();

    ArchiveItem afterRetry = reload(id);
    assertThat(afterRetry.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
    assertThat(afterRetry.getBodyText()).isEqualTo("풀린 뒤 본문");
    assertThat(afterRetry.getTitle()).isEqualTo("풀린 뒤 제목");
    // 끝났으니 배치가 다시 집지 않는다.
    assertThat(afterRetry.getNextCrawlAt()).isNull();
    assertThat(archiveItemRepository.findIdsDueForCrawlRetry(Instant.now(), pageOf50()))
        .doesNotContain(id);
  }

  @Test
  void 계속_막히면_상한에서_실패로_확정된다() {
    // 반대편 말뚝 — "분석 중"이 영원히 남는 것은 실패보다 나쁘다.
    when(urlCrawler.crawl(any()))
        .thenThrow(CrawlException.retryable("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요"));
    Long id = savedPendingItem("https://www.instagram.com/p/계속막히는것/");

    processor.process(id); // 최초 1회
    for (int round = 0; round < 3; round++) { // 재시도 3회
      archiveItemRepository.rescheduleCrawl(List.of(id), Instant.now().minusSeconds(1));
      scheduler.retryDueCrawls();
    }

    ArchiveItem finished = reload(id);
    assertThat(finished.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.FAILED);
    assertThat(finished.getCrawlRetries()).isEqualTo(3);
    assertThat(finished.getNextCrawlAt()).isNull();
  }

  /**
   * 테스트마다 <b>다른 URL</b> 을 쓴다.
   *
   * <p>같은 URL 을 쓰면 24시간 캐시({@code ArchiveCrawlProcessor.reuseRecentCrawl})가 앞 테스트의 {@code DONE} 결과를
   * 베껴 와 크롤러를 아예 안 부른다 — 실제로 그렇게 깨지는 것을 보고 나눴다.
   */
  private Long savedPendingItem(String url) {
    Room room =
        roomRepository.save(
            new Room("방", null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10)));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "링크 모음"));
    return archiveItemRepository.save(ArchiveItem.pending(folder, room, url, url, null)).getId();
  }

  private ArchiveItem reload(Long id) {
    return archiveItemRepository.findById(id).orElseThrow();
  }

  private static org.springframework.data.domain.PageRequest pageOf50() {
    return org.springframework.data.domain.PageRequest.of(0, 50);
  }
}
