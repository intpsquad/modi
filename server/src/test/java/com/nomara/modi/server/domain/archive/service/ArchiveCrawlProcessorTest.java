package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.ignoreStubs;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.archive.client.CrawlResult;
import com.nomara.modi.server.domain.archive.client.UrlCrawler;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveItemTag;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemTagRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * 공유 등록 비동기 처리의 <b>갈림길 하나</b>를 잰다: URL 항목은 크롤링하고, 텍스트 항목은 크롤링하지 않는다(2026-08-05).
 *
 * <p>스프링을 띄우지 않는다 — 재는 것이 "어느 분기로 가는가"뿐이라 컨테이너가 필요 없다. 리포지토리만 목이고 요약·임베딩은 진짜 컴포넌트에 가짜 클라이언트를 꽂는다 (그
 * 둘의 폴백 규칙까지 같이 타게 하려는 것이다).
 *
 * <p>{@code folder}/{@code createdBy} 에 {@code null} 을 넣는 이유: {@code process()} 는 둘을 읽지 않는다. 여기서 진짜
 * 엔티티를 만들면 Postgres 컨테이너가 따라와야 하고, 그건 {@code ArchiveItemServiceTest} 가 이미 한다.
 *
 * <p>⚠️ <b>{@code room} 은 더 이상 null 을 못 넣는다</b>(2026-08-09 후속 — 분석 완료 알림 본문에 방 이름을 실으면서 {@code
 * notifyDone}/{@code notifyFailed} 가 {@code item.getRoom().getName()} 을 읽는다). Postgres 없이도 되는 순수
 * POJO라({@code Room} 생성자가 영속성을 요구하지 않는다) {@code ROOM} 상수로 채운다 — 이 채움 자체가 "process()는 필요한 것만 읽는다"는
 * 전제가 얼마나 쉽게 깨지는지 보여준다. 알림이 세는 값은 {@code ArchiveCrawlProcessorNotifyTest} 가 따로 본다.
 */
class ArchiveCrawlProcessorTest {

  private static final Room ROOM =
      new Room("테스트방", null, "목표", null, LocalDate.now(), LocalDate.now());

  private final List<String> crawledUrls = new ArrayList<>();
  private final List<String> savedTags = new ArrayList<>();

  private final ArchiveItemRepository archiveItemRepository = mock(ArchiveItemRepository.class);
  private final ArchiveItemTagRepository archiveItemTagRepository =
      mock(ArchiveItemTagRepository.class);
  // 알림 버퍼는 목이다 — 여기서 재는 것은 상태 전이고, 무엇을 세는지는
  // ArchiveCrawlProcessorNotifyTest 가 따로 본다.
  private final ArchiveAnalysisNotificationBuffer notificationBuffer =
      mock(ArchiveAnalysisNotificationBuffer.class);

  /** 크롤러가 던질 실패. {@code null} 이면 정상 응답한다. */
  private CrawlException crawlFailure;

  /** 부르면 기록하고, 본문을 <b>눈에 띄게 덮어쓴다</b> — 잘못 불렸을 때 본문 단언도 함께 깨지도록. */
  private final UrlCrawler urlCrawler =
      url -> {
        crawledUrls.add(url);
        if (crawlFailure != null) {
          throw crawlFailure;
        }
        return new CrawlResult("크롤링한 제목", "크롤링한 본문", "https://cdn.test/t.jpg", "test.com");
      };

  private final ArchiveCrawlProcessor processor =
      new ArchiveCrawlProcessor(
          archiveItemRepository,
          archiveItemTagRepository,
          urlCrawler,
          Optional.of(bodyText -> List.of("태그:" + bodyText)),
          new ArchiveSummarizer(Optional.of(bodyText -> "요약:" + bodyText)),
          new ArchiveEmbedder(Optional.of(text -> new float[] {1f, 2f, 3f})),
          notificationBuffer);

  ArchiveCrawlProcessorTest() {
    when(archiveItemTagRepository.save(any(ArchiveItemTag.class)))
        .thenAnswer(
            invocation -> {
              savedTags.add(invocation.getArgument(0, ArchiveItemTag.class).getId().getTag());
              return invocation.getArgument(0);
            });
  }

  @Test
  void 텍스트_항목은_크롤러를_부르지_않고_등록_때_본문을_그대로_쓴다() {
    ArchiveItem item = ArchiveItem.textDone(null, ROOM, "공유된 텍스트 제목", "공유된 텍스트 본문", null);
    given(item);

    processor.process(1L);

    assertThat(crawledUrls).isEmpty();
    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
    // 제목·본문은 사용자가 준 것이 정답이다 — markCrawlDone 을 재사용하면 여기가 깨진다.
    assertThat(item.getTitle()).isEqualTo("공유된 텍스트 제목");
    assertThat(item.getBodyText()).isEqualTo("공유된 텍스트 본문");
  }

  @Test
  void 텍스트_항목은_등록_시점부터_DONE_이다() {
    // 🔴 2026-08-06. 본문이 이미 완성이라 "분석 중" 배지를 띄울 이유가 없다 — 다 적어 놓은
    // 메모가 아직 처리 중인 것처럼 보였다(실사용 확인). 태깅·임베딩은 뒤에서 조용히 돈다.
    ArchiveItem item = ArchiveItem.textDone(null, ROOM, "제목", "본문", null);

    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
  }

  @Test
  void 텍스트_항목은_자동_요약을_하지_않는다() {
    // 🔴 2026-08-06 사용자 확정. 직접 적은 짧은 메모는 본문이 곧 요약이라 얻는 것이 거의 없으면서
    // LLM 호출만 쓴다. 필요하면 자료 상세에서 「AI 요약 만들기」로 만든다.
    ArchiveItem item = ArchiveItem.textDone(null, ROOM, "제목", "본문", null);
    given(item);

    processor.process(1L);

    assertThat(item.getSummary()).isNull();
  }

  @Test
  void 텍스트_항목도_임베딩_태깅은_돈다() {
    // 요약만 뺐다. 이 둘 때문에 텍스트도 여전히 PENDING 으로 들어온다.
    ArchiveItem item = ArchiveItem.textDone(null, ROOM, "제목", "본문", null);
    given(item);

    processor.process(1L);

    // 요약이 없으므로 **본문으로** 임베딩된다(ArchiveEmbedder 의 폴백).
    assertThat(item.getEmbedding()).containsExactly(1f, 2f, 3f);
    assertThat(savedTags).containsExactly("태그:본문");
  }

  @Test
  void 링크_항목은_그대로_자동_요약한다() {
    // 반대편 말뚝 — 본문이 긴 링크 자료는 요약이 실제로 값을 한다(추천 프롬프트 비용).
    // 이걸 함께 껐다가는 추천 품질이 조용히 나빠진다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    given(item);

    processor.process(1L);

    assertThat(item.getSummary()).isEqualTo("요약:크롤링한 본문");
  }

  @Test
  void URL_항목은_그대로_크롤링한다() {
    // 분기를 뒤집는 변형이 조용히 통과하지 못하게 하는 반대편 말뚝.
    ArchiveItem item =
        ArchiveItem.pending(null, ROOM, "https://example.com/a", "https://example.com/a", null);
    given(item);

    processor.process(1L);

    assertThat(crawledUrls).containsExactly("https://example.com/a");
    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
    assertThat(item.getBodyText()).isEqualTo("크롤링한 본문");
    assertThat(item.getTitle()).isEqualTo("크롤링한 제목");
  }

  // ------------------------------------------------------------------ 24시간 캐시

  @Test
  void 같은_URL_을_최근에_긁었으면_크롤러를_안_부르고_결과를_베낀다() {
    // 🔴 이 커밋의 요점. 운영 IP 가 인스타에서 소프트 블록됐고 참조 문서(test.md)의 처방 첫째가
    // "Cache aggressively (e.g. 24h)" 인데 우리는 같은 링크도 매번 새로 긁고 있었다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    given(item);
    givenCached(done(2L, "https://example.com/a", "캐시된 제목", "캐시된 본문"));

    processor.process(1L);

    assertThat(crawledUrls).isEmpty();
    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
    assertThat(item.getTitle()).isEqualTo("캐시된 제목");
    assertThat(item.getBodyText()).isEqualTo("캐시된 본문");
  }

  @Test
  void 캐시_적중이면_AI_도_다시_부르지_않는다() {
    // 같은 URL 이면 본문이 같다 — 같은 본문에 LLM 을 다시 부를 이유가 없다.
    // 크롤링 1회뿐 아니라 LLM 호출 3회(요약·임베딩·태깅)도 함께 아낀다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    given(item);
    ArchiveItem cached = done(2L, "https://example.com/a", "제목", "본문");
    cached.applySummary("캐시된 요약");
    cached.applyEmbedding(new float[] {9f, 9f});
    givenCached(cached);

    processor.process(1L);

    // 진짜 요약기를 탔다면 "요약:본문" 이 됐을 것이다.
    assertThat(item.getSummary()).isEqualTo("캐시된 요약");
    assertThat(item.getEmbedding()).containsExactly(9f, 9f);
    assertThat(savedTags).doesNotContain("태그:본문");
  }

  @Test
  void 캐시_적중이면_원본의_태그를_그대로_붙인다() {
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    given(item);
    ArchiveItem cached = done(2L, "https://example.com/a", "제목", "본문");
    givenCached(cached);
    when(archiveItemTagRepository.findByItemId(2L))
        .thenReturn(List.of(new ArchiveItemTag(cached, "맛집"), new ArchiveItemTag(cached, "성수")));

    processor.process(1L);

    assertThat(savedTags).containsExactly("맛집", "성수");
  }

  @Test
  void 캐시가_없으면_평소대로_긁는다() {
    // 반대편 말뚝 — 캐시 분기가 항상 참이 되는 변형을 잡는다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    given(item);

    processor.process(1L);

    assertThat(crawledUrls).containsExactly("https://example.com/a");
    assertThat(item.getBodyText()).isEqualTo("크롤링한 본문");
  }

  @Test
  void 자기_자신은_재사용하지_않는다() {
    // 조회 조건이 바뀌어 자기 자신이 잡히면, 자기 본문을 자기에게 베끼고 크롤링을 영영 건너뛴다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    given(item);
    givenCached(item);

    processor.process(1L);

    assertThat(crawledUrls).containsExactly("https://example.com/a");
  }

  @Test
  void 캐시_조회는_24시간_안쪽만_본다() {
    // 기간 판정은 쿼리가 한다 — 여기서는 **얼마 전부터를 묻는지**를 고정한다.
    // 이 값이 조용히 늘어나면 수정된 게시물의 옛 제목이 오래 남는다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    given(item);
    Instant before = Instant.now();

    processor.process(1L);

    ArgumentCaptor<Instant> since = ArgumentCaptor.forClass(Instant.class);
    verify(archiveItemRepository)
        .findFirstByUrlAndCrawlStatusAndCreatedAtAfterOrderByCreatedAtDesc(
            eq("https://example.com/a"), eq(ArchiveItem.CrawlStatus.DONE), since.capture());
    assertThat(Duration.between(since.getValue(), before))
        .isBetween(Duration.ofHours(23).plusMinutes(59), Duration.ofHours(24));
  }

  @Test
  void 텍스트_항목은_캐시를_보지도_않는다() {
    // url 이 null 이라 조회하면 그 자체가 무의미하고, 다른 텍스트 항목을 엉뚱하게 베낄 수 있다.
    given(ArchiveItem.textDone(null, ROOM, "제목", "본문", null));

    processor.process(1L);

    verifyNoMoreInteractions(ignoreStubs(archiveItemRepository));
  }

  // ------------------------------------------------------------- 실패 시 자동 재시도

  @Test
  void 다시_해볼_만한_실패는_분석중으로_두고_다음_시도를_잡는다() {
    // 🔴 이 커밋의 요점이자 이 작업 전체의 목표 — 사용자에게 "분석 실패" 가 뜨지 않게 한다.
    // 인스타 소프트 블록은 10~20분이면 풀리는데 지금까지는 그 순간 들어온 공유가 그대로 굳었다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    given(item);
    crawlFailure = CrawlException.retryable("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");
    Instant before = Instant.now();

    processor.process(1L);

    // PENDING 이라 앱이 그대로 "분석 중" 을 그린다 — 그래서 앱을 한 줄도 안 고친다.
    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.PENDING);
    assertThat(item.getCrawlRetries()).isEqualTo(1);
    // 아래를 20분으로 잡는 이유: nextCrawlAt 은 before 를 찍은 **뒤에** now()+20분으로 계산되므로
    // 간격은 늘 20분보다 조금 길다. 위쪽에 19~20분을 주면 두 now() 가 같은 클록 틱에 떨어질 때만
    // 통과하는 플래키 테스트가 된다(2026-08-06 변형 검증 중 실제로 발견).
    assertThat(Duration.between(before, item.getNextCrawlAt()))
        .isBetween(Duration.ofMinutes(20), Duration.ofMinutes(21));
  }

  @Test
  void 대상_자체가_원인인_실패는_바로_확정한다() {
    // 반대편 말뚝 — 다시 걸어도 같은 답이 온다. 재시도하면 외부 사이트만 더 때린다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    given(item);
    crawlFailure = new CrawlException("공개된 게시물만 등록할 수 있어요");

    processor.process(1L);

    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.FAILED);
    assertThat(item.getCrawlRetries()).isZero();
    assertThat(item.getNextCrawlAt()).isNull();
  }

  @Test
  void 상한_직전까지는_계속_다시_해본다() {
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    ReflectionTestUtils.setField(item, "crawlRetries", 2);
    given(item);
    crawlFailure = CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요");

    processor.process(1L);

    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.PENDING);
    assertThat(item.getCrawlRetries()).isEqualTo(3);
  }

  @Test
  void 상한에_닿으면_다시_해볼_만해도_실패로_확정한다() {
    // "분석 중" 이 영원히 남는 것은 실패보다 나쁘다 — 최초 1회 + 재시도 3회로 최악 60분 안에 끝난다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    ReflectionTestUtils.setField(item, "crawlRetries", 3);
    given(item);
    crawlFailure = CrawlException.retryable("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");

    processor.process(1L);

    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.FAILED);
    assertThat(item.getCrawlRetries()).isEqualTo(3);
    assertThat(item.getNextCrawlAt()).isNull();
  }

  @Test
  void 보내지도_못한_실패는_재시도_횟수를_안_태운다() {
    // 🔴 쿨다운 단락은 외부 사이트를 한 번도 안 때린다. 그것을 시도로 세면, 차단이 길 때
    // 밀려 있던 자료들이 **요청 0회로 상한을 소진**하고 실패로 확정된다 — 이 기능이 정확히
    // 겨냥한 상황(차단 중 몰려 들어온 공유)에서 무력해진다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    ReflectionTestUtils.setField(item, "crawlRetries", 3); // 상한에 이미 닿아 있다
    given(item);
    crawlFailure = CrawlException.notAttempted("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");

    processor.process(1L);

    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.PENDING);
    assertThat(item.getCrawlRetries()).isEqualTo(3);
    assertThat(item.getNextCrawlAt()).isNotNull();
  }

  @Test
  void 보내지도_못한_채_너무_오래_지나면_실패로_확정한다() {
    // 횟수 상한이 안 걸리는 갈래라 브레이크가 이것뿐이다 — 없으면 영원히 "분석 중"이다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    ReflectionTestUtils.setField(item, "createdAt", Instant.now().minus(Duration.ofHours(7)));
    given(item);
    crawlFailure = CrawlException.notAttempted("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");

    processor.process(1L);

    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.FAILED);
    assertThat(item.getNextCrawlAt()).isNull();
  }

  @Test
  void 등록한_지_얼마_안_됐으면_계속_미룬다() {
    // 반대편 말뚝 — 경과 시간 판정이 항상 참이 되는 변형을 잡는다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    ReflectionTestUtils.setField(item, "createdAt", Instant.now().minus(Duration.ofHours(5)));
    given(item);
    crawlFailure = CrawlException.notAttempted("인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");

    processor.process(1L);

    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.PENDING);
  }

  @Test
  void 보냈다가_실패한_것은_그대로_횟수를_태운다() {
    // notAttempted 갈래가 일반 재시도까지 삼키면 상한이 통째로 무력해진다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    given(item);
    crawlFailure = CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요");

    processor.process(1L);

    assertThat(item.getCrawlRetries()).isEqualTo(1);
  }

  @Test
  void 재시도_끝에_성공하면_다음_시도_예약이_지워진다() {
    // 안 지우면 배치가 이미 끝난 항목을 계속 집어 인스타를 헛되게 때린다.
    ArchiveItem item = pendingUrl(1L, "https://example.com/a");
    ReflectionTestUtils.setField(item, "crawlRetries", 1);
    ReflectionTestUtils.setField(item, "nextCrawlAt", Instant.now().minusSeconds(60));
    given(item);

    processor.process(1L);

    assertThat(item.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
    assertThat(item.getNextCrawlAt()).isNull();
    // 횟수는 기록으로 남긴다 — "몇 번 만에 됐나" 를 나중에 물을 수 있게.
    assertThat(item.getCrawlRetries()).isEqualTo(1);
  }

  private static ArchiveItem pendingUrl(Long id, String url) {
    ArchiveItem item = ArchiveItem.pending(null, ROOM, url, url, null);
    ReflectionTestUtils.setField(item, "id", id);
    return item;
  }

  private static ArchiveItem done(Long id, String url, String title, String bodyText) {
    ArchiveItem item = ArchiveItem.pending(null, ROOM, url, url, null);
    ReflectionTestUtils.setField(item, "id", id);
    item.markCrawlDone(title, bodyText, "cached.test", "https://cdn.test/cached.jpg");
    return item;
  }

  private void givenCached(ArchiveItem cached) {
    when(archiveItemRepository.findFirstByUrlAndCrawlStatusAndCreatedAtAfterOrderByCreatedAtDesc(
            any(), any(), any()))
        .thenReturn(Optional.of(cached));
  }

  private void given(ArchiveItem item) {
    when(archiveItemRepository.findById(1L)).thenReturn(Optional.of(item));
  }
}
