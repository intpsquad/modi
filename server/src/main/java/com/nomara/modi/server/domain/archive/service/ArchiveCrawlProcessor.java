package com.nomara.modi.server.domain.archive.service;

import com.nomara.modi.server.domain.archive.client.AiTaggingClient;
import com.nomara.modi.server.domain.archive.client.CrawlResult;
import com.nomara.modi.server.domain.archive.client.UrlCrawler;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveItemTag;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemTagRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * S-25-D 외부 공유 등록 전용 — 등록 시점엔 {@code PENDING}으로만 저장되고, 이 컴포넌트가 별도 스레드(`AsyncConfig`)에서 크롤링+AI 태깅을
 * 마친 뒤 {@code DONE}/{@code FAILED}로 갱신한다.
 *
 * <p><b>URL 공유와 텍스트 공유가 둘 다 여기로 온다</b>(2026-08-05). 갈리는 것은 <b>크롤링 한 단계뿐</b>이고, 요약·임베딩·태깅은 같다 — 텍스트
 * 공유가 느렸던 원인도 크롤링이 아니라 그 셋(LLM 3회)이었다. 왜 텍스트까지 비동기로 옮겼는지는 {@code
 * ArchiveItemService.createSharedItem} 참고.
 *
 * <p>{@code @Async}가 걸린 메서드는 반드시 **다른 빈을 통해** 호출해야 프록시가 적용된다(같은 클래스 안에서 자기 자신을 호출하면
 * self-invocation으로 조용히 무시되고 동기 실행됨) — {@code ArchiveItemService}가 이 컴포넌트를 주입받아 호출하는 구조로 그 문제를 피한다.
 *
 * <p><b>⚠️ 알고 있는 부채: 이 메서드는 {@code @Transactional} 안에서 외부 호출을 4회 돈다</b>(크롤링 1 + LLM 3). 최악 대기 약
 * 185초 동안 DB 커넥션 하나를 물고 있다. 에서 {@code TodoSuggestionService}가 맞은 것과 같은 형태이고, 거기서는 읽기·LLM·쓰기를 세 경계로
 * 쪼개 해소했다. 여기를 쪼개지 않은 이유는 이 메서드가 <b>부분 실패 시의 원자성에 기대고</b> 있기 때문이다 — {@code markCrawlFailed()}와 태그
 * 저장이 한 트랜잭션이라야 "본문은 저장됐는데 상태는 PENDING" 같은 중간 상태가 안 생긴다. 지금은 {@code archiveCrawlExecutor}가 max 4
 * 스레드라 Hikari 풀 10 중 최대 4만 점유돼 버티는 것뿐이다. 스레드 풀을 키우기 전에 {@code specs/OPEN.md}의 해당 항목을 먼저 볼 것.
 */
@Component
public class ArchiveCrawlProcessor {

  private static final Logger log = LoggerFactory.getLogger(ArchiveCrawlProcessor.class);

  /**
   * 같은 URL 의 크롤링 결과를 재사용하는 기간. 참조 문서(test.md)의 <i>"Cache aggressively (e.g. 24h)"</i> 를 따른다.
   *
   * <p>상수로 두는 이유: 이 값을 늘려서 얻는 것(호출 절감)과 잃는 것(수정된 게시물의 옛 제목)의 균형은 <b>제품 판단</b>이지 환경별 설정이 아니다. 바꿔야 할
   * 근거가 생기면 그때 프로퍼티로 뺀다.
   */
  private static final Duration CRAWL_CACHE_TTL = Duration.ofHours(24);

  /**
   * 자동 재시도 상한 — 최초 1회 + 재시도 3회 = <b>최대 4번, 최악 60분 안에 확정</b>된다.
   *
   * <p>상한을 두는 이유는 {@code specs/OPEN.md} 의 "영구 PENDING" 우려를 키우지 않기 위해서다. 안 되는 링크가 "분석 중" 으로 영원히 남으면
   * 그건 실패보다 나쁘다.
   */
  private static final int MAX_CRAWL_RETRIES = 3;

  /**
   * 재시도 간격.
   *
   * <p>⚠️ <b>근거는 관측 2건뿐이다</b>(2026-08-05 운영 DB: 12:45 실패 → 12:54 성공 = 9분, 15:18 실패 → 15:36 성공 =
   * 18분). 그 위쪽에 여유를 두고 20분으로 잡았다. 관측이 더 쌓이면 고칠 값이라 여기에 근거를 적어둔다.
   *
   * <p>지수 백오프를 쓰지 않는 이유: 회복이 9~18분에 몰려 있어 고정 간격으로 충분하다. 근거 없이 복잡도를 올리지 않는다.
   */
  private static final Duration RETRY_DELAY = Duration.ofMinutes(20);

  /**
   * 요청을 <b>보내지도 못한</b> 실패(쿨다운 단락)만 계속될 때의 총 대기 상한 — 등록 시각 기준(2026-08-06 리뷰 P2).
   *
   * <p>그 실패는 재시도 횟수를 안 태우므로 {@link #MAX_CRAWL_RETRIES} 가 안 걸린다. 상한이 아예 없으면 차단이 길어질 때 항목이 "분석 중"으로
   * 영원히 남는데, 그건 실패보다 나쁘다는 것이 이 기능의 전제였다.
   *
   * <p>6시간인 근거: 관측된 차단은 10~20분이고 정상 경로 상한이 60분이다. 그보다 한참 긴 값을 둬서 <b>진짜로 이상할 때만</b> 걸리게 한다.
   */
  private static final Duration MAX_BLOCKED_WAIT = Duration.ofHours(6);

  private final ArchiveItemRepository archiveItemRepository;
  private final ArchiveItemTagRepository archiveItemTagRepository;
  private final UrlCrawler urlCrawler;
  private final Optional<AiTaggingClient> aiTaggingClient;
  private final ArchiveSummarizer archiveSummarizer;
  private final ArchiveEmbedder archiveEmbedder;
  private final ArchiveAnalysisNotificationBuffer notificationBuffer;

  public ArchiveCrawlProcessor(
      ArchiveItemRepository archiveItemRepository,
      ArchiveItemTagRepository archiveItemTagRepository,
      UrlCrawler urlCrawler,
      Optional<AiTaggingClient> aiTaggingClient,
      ArchiveSummarizer archiveSummarizer,
      ArchiveEmbedder archiveEmbedder,
      ArchiveAnalysisNotificationBuffer notificationBuffer) {
    this.archiveItemRepository = archiveItemRepository;
    this.archiveItemTagRepository = archiveItemTagRepository;
    this.urlCrawler = urlCrawler;
    this.aiTaggingClient = aiTaggingClient;
    this.archiveSummarizer = archiveSummarizer;
    this.archiveEmbedder = archiveEmbedder;
    this.notificationBuffer = notificationBuffer;
  }

  @Async("archiveCrawlExecutor")
  @Transactional
  public void process(Long itemId) {
    ArchiveItem item = archiveItemRepository.findById(itemId).orElse(null);
    if (item == null) {
      // 크롤링이 끝나기 전에 사용자가 항목을 삭제한 경우 — 조용히 종료.
      return;
    }
    try {
      String bodyText;
      if (item.getUrl() == null) {
        // 텍스트 등록 — 크롤링할 URL이 없다. 본문은 등록 시점에 이미 저장돼 있고 상태도 이미
        // DONE 이다(ArchiveItem.textDone, 2026-08-06). 여기서는 아래 임베딩·태깅만 얹는다.
        //
        // 🔴 크롤러를 부르지 않는다. 부르면 null URL로 SiteUrlCrawler 판별부터 터진다.
        bodyText = item.getBodyText();
        item.markDoneWithoutCrawl();
      } else if (reuseRecentCrawl(item)) {
        // 캐시 적중 — 크롤링도 AI 3회도 건너뛰었다. 아래 요약·임베딩·태깅을 다시 하지 않는다.
        // 사용자에게는 똑같이 "분석이 끝난" 것이므로 알림은 여기서도 센다.
        notifyDone(item);
        return;
      } else {
        CrawlResult crawled = urlCrawler.crawl(item.getUrl());
        // 동기 등록(ArchiveItemService)과 같은 상한을 쓴다 — 여기에만 상한이 없어서 크롤링 결과가 컬럼 폭을
        // 넘으면 INSERT가 실패했다. 이 메서드는 @Transactional이라 그 실패는 메서드가 끝난 뒤 커밋 시점에
        // 터지고 아래 catch에 잡히지 않는다 → markCrawlFailed()도 못 타고 항목이 영구 PENDING으로 남는다.
        bodyText = ArchiveTextLimits.truncate(crawled.bodyText(), ArchiveTextLimits.MAX_BODY_TEXT);
        item.markCrawlDone(
            ArchiveTextLimits.truncate(crawled.title(), ArchiveTextLimits.MAX_TITLE),
            bodyText,
            ArchiveTextLimits.truncate(crawled.source(), ArchiveTextLimits.MAX_SOURCE),
            ArchiveTextLimits.nullIfTooLong(crawled.thumbnail(), ArchiveTextLimits.MAX_THUMBNAIL));
      }
      // 이 경로는 이미 백그라운드라 호출이 하나 늘어도 사용자를 붙잡지 않는다. 실패해도 위에서 정한
      // DONE 상태를 되돌리지 않는다 — 요약·임베딩은 크롤링 성공의 조건이 아니다.
      //
      // 🔴 **텍스트로 등록한 것은 요약하지 않는다**(2026-08-06 사용자 확정). 사용자가 직접 적은
      // 짧은 메모는 본문이 곧 요약이라, 요약해 봐야 얻는 것이 거의 없으면서 LLM 호출만 쓴다.
      // 필요한 사람은 자료 상세에서 「AI 요약 만들기」로 직접 만든다(ArchiveSummaryFiller).
      // 링크 자료는 본문이 길어 요약이 실제로 값을 하므로 그대로 자동이다.
      if (item.getUrl() != null) {
        item.applySummary(archiveSummarizer.summarize(bodyText));
      }
      // 임베딩은 요약 뒤에 — 요약이 임베딩의 입력이다(ArchiveEmbedder). 방금 붙인 값을 엔티티에서
      // 다시 읽어 넘겨 applySummary 의 "빈 문자열 → null" 정규화를 그대로 탄다.
      //
      // ⚠️ 텍스트 항목은 요약이 없으므로 **본문으로** 임베딩된다. 한 방 안에 "요약 기반"과 "본문
      // 기반" 벡터가 섞이는데(ArchiveSummaryFiller 주석 참고), 짧은 메모는 본문이 곧 요약이라
      // 두 축의 차이가 작다고 봤다. 나중에 버튼으로 요약을 만들면 그때 벡터도 함께 갱신된다.
      item.applyEmbedding(archiveEmbedder.embed(item.getSummary(), bodyText));
      for (String tag : suggestTagsSafely(bodyText)) {
        archiveItemTagRepository.save(new ArchiveItemTag(item, tag));
      }
      // 🔴 **텍스트 항목은 알리지 않는다**(2026-08-06). 그쪽은 등록 즉시 DONE 이라 사용자가
      // 기다리는 것이 없다 — 방금 적은 메모에 1분 뒤 "분석이 끝났어요"가 오면 그건 소음이다.
      // 이 알림의 존재 이유는 "크롤링이 언제 끝나는지 알 수 없다"였고, 텍스트엔 그 문제가 없다.
      if (item.getUrl() != null) {
        notifyDone(item);
      }
    } catch (CrawlException e) {
      handleCrawlFailure(item, e);
    } catch (Exception e) {
      // 크롤링이 끝나기 "도중"(findById 이후 커밋 이전)에 사용자가 항목을 삭제한 경우 —
      // markCrawlDone 이후의 태그 저장이 이미 지워진 부모 행을 향한 FK 위반으로 실패할 수 있다.
      // 삭제된 항목이므로 저장할 것이 없어 트랜잭션은 그대로 롤백시키고 조용히 종료한다
      // (@Async void 메서드가 예외를 던지면 Spring 기본 핸들러가 시끄러운 에러 로그만 남기므로 여기서 갈무리).
      log.warn("공유 등록 항목 처리 중 예외(삭제된 항목일 수 있음): itemId={}", itemId, e);
    }
  }

  /**
   * 크롤링 실패를 확정할지, 잠시 뒤 다시 해볼지 정한다(2026-08-06).
   *
   * <p>🔴 <b>여기가 "분석 실패" 를 없애는 자리다.</b> 인스타 소프트 블록은 10~20분이면 풀리는데 지금까지는 그 순간 들어온 공유가 그대로 {@code
   * FAILED} 로 굳었다 — 운영 실패율 58% 의 실체가 그것이다. 다시 해볼 만한 실패는 {@code PENDING} 으로 두면 앱이 그대로 "분석 중" 을
   * 보여주고({@code CrawlStatusBadge}), 배치가 조용히 다시 긁는다.
   *
   * <p><b>재시도 자체가 차단을 키울 수 있다</b>는 것이 이 갈래의 위험이다. 세 겹으로 막는다 — 여기의 횟수 상한, 배치의 한 tick 상한, 그리고
   * 쿨다운({@code RedisCrawlBlockCooldown}). 쿨다운 중이면 크롤러가 요청 0회로 즉시 실패하고 그 실패가 다시 여기로 와 20분 뒤로 밀리므로,
   * 배치가 돌아도 인스타를 때리지 않는다.
   */
  private void handleCrawlFailure(ArchiveItem item, CrawlException e) {
    if (!e.isAttempted()) {
      // 요청을 보내지도 못했다(쿨다운 단락) — 시도로 세지 않는다. 세면 차단이 길 때 밀려 있던
      // 자료들이 요청 0회로 상한을 소진하고 실패로 확정된다(리뷰 P2).
      //
      // ⚠️ 이 갈래는 **여기서 끝까지 처리한다.** 아래로 흘려보내면 notAttempted 도 retryable 이라
      // 일반 재시도 갈래에 잡혀 경과 시간 상한이 무의미해진다(테스트가 실제로 잡았다).
      if (waitedTooLong(item)) {
        log.warn(
            "보내보지도 못한 채 너무 오래 기다렸다 — 실패로 확정한다: itemId={} 등록={}", item.getId(), item.getCreatedAt());
        item.markCrawlFailed();
        notifyFailed(item);
        return;
      }
      Instant nextAttemptAt = Instant.now().plus(RETRY_DELAY);
      item.delayCrawlRetry(nextAttemptAt);
      log.info(
          "보내보지도 못해서 뒤로 미룬다(횟수 안 셈): itemId={} 재시도={} 다음={} 사유={}",
          item.getId(),
          item.getCrawlRetries(),
          nextAttemptAt,
          e.getMessage());
      return;
    }
    if (e.isRetryable() && item.getCrawlRetries() < MAX_CRAWL_RETRIES) {
      Instant nextAttemptAt = Instant.now().plus(RETRY_DELAY);
      item.scheduleCrawlRetry(nextAttemptAt);
      log.info(
          "다시 해볼 만한 실패라 분석 중으로 둔다: itemId={} 재시도={}/{} 다음={} 사유={}",
          item.getId(),
          item.getCrawlRetries(),
          MAX_CRAWL_RETRIES,
          nextAttemptAt,
          e.getMessage());
      return;
    }
    log.warn(
        "공유 등록 항목 크롤링 실패로 확정: itemId={} 재시도={} 다시해볼만함={}",
        item.getId(),
        item.getCrawlRetries(),
        e.isRetryable(),
        e);
    item.markCrawlFailed();
    notifyFailed(item);
  }

  /**
   * 분석이 끝났다고 버퍼에 센다 — 실제 발송은 {@code ArchiveAnalysisNotifier} 가 모아서 한다.
   *
   * <p>제목을 함께 넘기는 이유: 1건뿐이면 개수 대신 제목을 그대로 쓴다("「강릉 여행 코스」 분석이 끝났어요").
   */
  private void notifyDone(ArchiveItem item) {
    notificationBuffer.recordDone(createdBy(item), item.getTitle(), item.getRoom().getName());
  }

  /**
   * 실패로 <b>확정</b>됐다고 센다.
   *
   * <p>🔴 재시도로 밀린 것은 여기 오지 않는다 — 위 갈래가 {@code return} 으로 빠진다. 밀린 것을 실패로 세면 20분 뒤 성공할 것에 대해 실패를 먼저
   * 알리게 된다.
   */
  private void notifyFailed(ArchiveItem item) {
    notificationBuffer.recordFailed(createdBy(item), item.getTitle(), item.getRoom().getName());
  }

  /** 작성자가 탈퇴하면 {@code null} 이다({@code V9}) — 보낼 곳이 없다. */
  private static String createdBy(ArchiveItem item) {
    return item.getCreatedBy() == null ? null : item.getCreatedBy().getId();
  }

  /**
   * 등록한 지 너무 오래됐나 — 보내보지도 못한 실패만 반복될 때의 유일한 브레이크.
   *
   * <p>{@code createdAt} 이 {@code null} 이면(아직 영속되지 않은 엔티티 — 단위 테스트) 판단하지 않는다. 모르면 미루는 쪽이 맞다.
   */
  private boolean waitedTooLong(ArchiveItem item) {
    Instant createdAt = item.getCreatedAt();
    return createdAt != null
        && Duration.between(createdAt, Instant.now()).compareTo(MAX_BLOCKED_WAIT) > 0;
  }

  /**
   * 같은 URL 을 최근에 이미 긁었으면 <b>그 결과를 베껴 쓰고 크롤링을 건너뛴다.</b> 베꼈으면 {@code true}.
   *
   * <p>🔴 <b>왜</b>(2026-08-06). 운영 EC2 IP 가 인스타에서 소프트 블록됐다. 참조 문서(test.md)의 처방 셋 중 첫째가 <i>"Cache
   * aggressively (e.g. 24h)"</i> 인데 우리는 하나도 안 하고 있었다 — 같은 링크를 다시 공유하면 매번 새로 긁었다. 운영 데이터로 인스타 19건 중
   * <b>4건이 중복 URL</b> 이었다.
   *
   * <p><b>방을 가리지 않는 이유</b> — 셋 다 오늘 확인했다:
   *
   * <ol>
   *   <li>크롤링 결과는 <b>공개 콘텐츠</b>다. 방을 넘나들어도 사용자 정보가 새지 않는다.
   *   <li>항목 삭제가 <b>MinIO 객체를 지우지 않는다</b>({@code ArchiveItemService.deleteItem} 은 DB 만 지운다). 그래서
   *       썸네일 URL 을 공유 참조해도 나중에 깨지지 않는다.
   *   <li>막히는 것은 <b>GraphQL 뿐</b>이고 CDN 이미지는 다른 호스트다 — 아껴야 할 호출을 정확히 건너뛴다.
   * </ol>
   *
   * <p>같은 인기 게시물이 여러 방에 공유되는 경우가 이 캐시의 최대 효과 지점이라, 방을 가리면 효과의 대부분을 버리게 된다. ⚠️ 나중에 <b>비공개 자료</b> 개념이
   * 생기면 이 판단을 다시 봐야 한다.
   *
   * <p><b>요약·임베딩·태그까지 베낀다.</b> 같은 URL 이면 본문이 같고, 같은 본문에 대해 LLM 을 다시 부를 이유가 없다 — 크롤링 1회뿐 아니라 LLM 호출
   * 3회도 함께 아낀다.
   *
   * <p>⚠️ <b>24시간 상한</b>(test.md 권고). 그 안에 게시물이 수정되면 옛 제목이 보일 수 있다 — 하루가 지나면 다시 긁는다.
   *
   * <p>⚠️ <b>동시에 같은 URL 이 들어오면 둘 다 긁는다.</b> 앞의 것이 아직 커밋 전이라 이 조회에 안 잡히기 때문이다(test.md 가 권하는
   * singleflight 를 아직 안 넣었다 — {@code specs/OPEN.md}). 캐시는 <b>순차 재공유</b>를 막고, 동시 공유는 못 막는다.
   */
  private boolean reuseRecentCrawl(ArchiveItem item) {
    ArchiveItem cached =
        archiveItemRepository
            .findFirstByUrlAndCrawlStatusAndCreatedAtAfterOrderByCreatedAtDesc(
                item.getUrl(), ArchiveItem.CrawlStatus.DONE, Instant.now().minus(CRAWL_CACHE_TTL))
            .orElse(null);
    // 자기 자신은 재사용 대상이 아니다. 지금 이 항목은 PENDING 이라 DONE 조회에 안 잡히지만,
    // 조회 조건이 바뀌면 조용히 자기 본문을 자기에게 베끼는 무한 루프 같은 모양이 된다.
    // Objects.equals 인 이유: 아직 영속되지 않은 엔티티는 id 가 null 이다.
    if (cached == null || Objects.equals(cached.getId(), item.getId())) {
      return false;
    }

    log.info(
        "같은 URL 을 최근에 긁었다 — 크롤링·AI 를 건너뛴다: itemId={} 재사용={} url={}",
        item.getId(),
        cached.getId(),
        item.getUrl());
    item.markCrawlDone(
        cached.getTitle(), cached.getBodyText(), cached.getSource(), cached.getThumbnail());
    item.applySummary(cached.getSummary());
    item.applyEmbedding(cached.getEmbedding());
    for (ArchiveItemTag tag : archiveItemTagRepository.findByItemId(cached.getId())) {
      archiveItemTagRepository.save(new ArchiveItemTag(item, tag.getId().getTag()));
    }
    return true;
  }

  private List<String> suggestTagsSafely(String bodyText) {
    if (aiTaggingClient.isEmpty()) {
      return List.of();
    }
    try {
      return aiTaggingClient.get().suggestTags(bodyText);
    } catch (Exception e) {
      log.warn("AI 자동 태깅 실패 — 태그 없이 등록을 진행합니다", e);
      return List.of();
    }
  }
}
