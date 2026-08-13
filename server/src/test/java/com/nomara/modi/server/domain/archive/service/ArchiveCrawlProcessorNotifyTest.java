package com.nomara.modi.server.domain.archive.service;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.archive.client.CrawlResult;
import com.nomara.modi.server.domain.archive.client.UrlCrawler;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemTagRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.user.entity.User;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * 처리기가 <b>어느 지점에서</b> 알림 버퍼에 세는지를 잰다(2026-08-06).
 *
 * <p>🔴 <b>제일 중요한 것은 "세지 않는" 쪽이다.</b> 재시도로 밀린 실패를 세면 20분 뒤 성공할 것에 대해 "가져오지 못했어요"를 먼저 보내게 된다 — 알림이
 * 틀린 말을 하는 것이라 안 보내느니만 못하다.
 *
 * <p>성공은 갈래가 셋(크롤링 · 캐시 재사용 · 텍스트)이라 하나씩 빠뜨리기 쉽다. 셋 다 못 박는다.
 */
class ArchiveCrawlProcessorNotifyTest {

  private static final String UID = "uid-writer";

  private final ArchiveItemRepository archiveItemRepository = mock(ArchiveItemRepository.class);
  private final ArchiveItemTagRepository archiveItemTagRepository =
      mock(ArchiveItemTagRepository.class);
  private final ArchiveAnalysisNotificationBuffer buffer =
      mock(ArchiveAnalysisNotificationBuffer.class);

  private CrawlException crawlFailure;

  private final UrlCrawler urlCrawler =
      url -> {
        if (crawlFailure != null) {
          throw crawlFailure;
        }
        return new CrawlResult("크롤링한 제목", "크롤링한 본문", null, "test.com");
      };

  private final ArchiveCrawlProcessor processor =
      new ArchiveCrawlProcessor(
          archiveItemRepository,
          archiveItemTagRepository,
          urlCrawler,
          Optional.empty(),
          new ArchiveSummarizer(Optional.empty()),
          new ArchiveEmbedder(Optional.empty()),
          buffer);

  private final User writer = new User(UID, "닉네임", null);
  private final Room room = new Room("여행방", null, "목표", null, LocalDate.now(), LocalDate.now());

  // ------------------------------------------------------------------ 세는 쪽

  @Test
  void 크롤링이_끝나면_센다() {
    given(pendingUrl("https://example.com/a"));

    processor.process(1L);

    // 제목은 크롤링 결과로 바뀐 뒤의 값이어야 한다 — 알림에 URL 이 그대로 나가면 무슨 자료인지 모른다.
    verify(buffer).recordDone(UID, "크롤링한 제목", "여행방");
  }

  @Test
  void 캐시를_베껴_썼을_때도_센다() {
    // 사용자에게는 똑같이 "분석이 끝난" 것이다. 여기를 빠뜨리면 캐시 적중한 자료만 알림이 안 온다.
    ArchiveItem item = pendingUrl("https://example.com/a");
    given(item);
    ArchiveItem cached = pendingUrl("https://example.com/a");
    ReflectionTestUtils.setField(cached, "id", 2L);
    cached.markCrawlDone("캐시된 제목", "캐시된 본문", "test.com", null);
    when(archiveItemRepository.findFirstByUrlAndCrawlStatusAndCreatedAtAfterOrderByCreatedAtDesc(
            any(), any(), any()))
        .thenReturn(Optional.of(cached));
    when(archiveItemTagRepository.findByItemId(2L)).thenReturn(List.of());

    processor.process(1L);

    verify(buffer).recordDone(UID, "캐시된 제목", "여행방");
  }

  @Test
  void 텍스트_항목은_알리지_않는다() {
    // 🔴 2026-08-06. 텍스트는 등록 즉시 DONE 이라 사용자가 기다리는 것이 없다 — 방금 적은
    // 메모에 1분 뒤 "분석이 끝났어요"가 오면 소음이다. 이 알림의 존재 이유는 "크롤링이 언제
    // 끝나는지 알 수 없다"였고 텍스트엔 그 문제가 없다.
    given(ArchiveItem.textDone(null, null, "메모 제목", "메모 본문", writer));

    processor.process(1L);

    verify(buffer, never()).recordDone(any(), any(), any());
    verify(buffer, never()).recordFailed(any(), any(), any());
  }

  @Test
  void 실패로_확정되면_실패로_센다() {
    ArchiveItem item = pendingUrl("https://example.com/a");
    given(item);
    crawlFailure = new CrawlException("공개된 게시물만 등록할 수 있어요");

    processor.process(1L);

    verify(buffer).recordFailed(eq(UID), any(), any());
    verify(buffer, never()).recordDone(any(), any(), any());
  }

  @Test
  void 재시도_상한에_닿아_확정된_실패도_센다() {
    ArchiveItem item = pendingUrl("https://example.com/a");
    ReflectionTestUtils.setField(item, "crawlRetries", 3);
    given(item);
    crawlFailure = CrawlException.retryable("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");

    processor.process(1L);

    verify(buffer).recordFailed(eq(UID), any(), any());
  }

  // ------------------------------------------------------------------ 안 세는 쪽

  @Test
  void 재시도로_밀린_것은_아직_아무것도_안_센다() {
    // 🔴 여기가 이 테스트의 요점. 20분 뒤 성공할 것에 대해 "가져오지 못했어요"를 먼저 보내면
    // 알림이 틀린 말을 하는 것이다.
    ArchiveItem item = pendingUrl("https://example.com/a");
    given(item);
    crawlFailure = CrawlException.retryable("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");

    processor.process(1L);

    verify(buffer, never()).recordFailed(any(), any(), any());
    verify(buffer, never()).recordDone(any(), any(), any());
  }

  @Test
  void 보내지도_못해_미뤄진_것도_안_센다() {
    // 쿨다운 단락 — 아직 시도조차 안 했다.
    ArchiveItem item = pendingUrl("https://example.com/a");
    given(item);
    crawlFailure = CrawlException.notAttempted("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");

    processor.process(1L);

    verify(buffer, never()).recordFailed(any(), any(), any());
    verify(buffer, never()).recordDone(any(), any(), any());
  }

  @Test
  void 보내지도_못한_채_상한_시간을_넘기면_그때는_센다() {
    // 반대편 말뚝 — 그 갈래도 결국 FAILED 로 확정되므로 알림은 가야 한다.
    ArchiveItem item = pendingUrl("https://example.com/a");
    ReflectionTestUtils.setField(item, "createdAt", Instant.now().minus(Duration.ofHours(7)));
    given(item);
    crawlFailure = CrawlException.notAttempted("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");

    processor.process(1L);

    verify(buffer).recordFailed(eq(UID), any(), any());
  }

  private ArchiveItem pendingUrl(String url) {
    ArchiveItem item = ArchiveItem.pending(null, room, url, url, writer);
    ReflectionTestUtils.setField(item, "id", 1L);
    return item;
  }

  private void given(ArchiveItem item) {
    when(archiveItemRepository.findById(1L)).thenReturn(Optional.of(item));
  }
}
