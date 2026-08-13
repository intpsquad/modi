package com.nomara.modi.server.domain.archive.entity;

import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.user.entity.User;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.Instant;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

@Entity
@Table(name = "archive_items")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ArchiveItem {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "folder_id", nullable = false)
  private ArchiveFolder folder;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "room_id", nullable = false)
  private Room room;

  @Column(nullable = false)
  private String title;

  private String url;

  /**
   * 폴더에 직접 올린 이미지 자료의 원본 URL(V28, 2026-08-09 후속 확정). {@code url}(링크)·{@code bodyText}(텍스트)와 같은 관례로
   * {@code imageUrl != null}이면 이미지 자료다 — 셋 중 정확히 하나만 채워진다({@link
   * com.nomara.modi.server.domain.archive.service.ArchiveItemService#createItem}).
   */
  @Column(name = "image_url", length = 2048)
  private String imageUrl;

  @Column(name = "body_text", columnDefinition = "TEXT")
  private String bodyText;

  /**
   * 본문의 AI 요약. 투두 추천의 프롬프트 입력으로 쓰고, S-25-B에서 본문 위에 보여준다.
   *
   * <p>{@code null}이 정상인 경우가 셋 있다 — {@code V5__add_summary_to_archive_items.sql} 참고. 길이 상한은 {@code
   * ArchiveTextLimits.MAX_SUMMARY}(컬럼 폭과 같다).
   */
  @Column(length = 500)
  private String summary;

  /**
   * 본문(또는 요약)의 임베딩 벡터. 추천 자료 선별의 입력이며, <b>부터 실제로 읽힌다</b> — {@code TodoSuggestionPayloadLoader}가 추천
   * 요청에 그대로 실어 보내고 AI 서버가 방 목표와의 코사인으로 순위를 매긴다.
   *
   * <p>{@code null}이 정상인 경우가 넷 있다 — {@code V7__add_embedding_to_archive_items.sql} 참고.
   *
   * <p>{@code float[]} ↔ Postgres {@code real[]}는 Hibernate 6의 기본 배열 매핑이다. 이 매핑이 실제로 맞는지 증명하는 것은
   * {@code SchemaValidationTest}뿐이다(Testcontainers + Flyway + {@code ddl-auto=validate}).
   *
   * <p><b>{@code columnDefinition = "real[]"}을 붙이지 않는다.</b> 붙였다가 H2를 쓰는 테스트 13개가 깨졌다 — 그 값은 방언과
   * 무관하게 DDL에 그대로 나가는데 H2의 배열 문법은 {@code REAL ARRAY}라서 {@code archive_items} 생성 자체가 실패한다. 방언이 알아서
   * 고르게 두면 Postgres에서도 {@code real[]}로 맞는다(위 테스트가 증명).
   */
  private float[] embedding;

  private String source;

  private String thumbnail;

  /** 사용자가 자료에 남기는 개인 메모(2026-08-06 도입, nullable). AI가 만드는 {@link #summary}와 달리 순수 사용자 입력이다. */
  @Column(length = 500)
  private String memo;

  @Column(nullable = false)
  private boolean pinned;

  /**
   * 작성자. 탈퇴한 사용자의 자료는 방에 남기고 작성자만 지우므로(2026-08-03 확정, {@code V9__account_deletion_cascades.sql})
   * nullable이다.
   */
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "created_by", nullable = true)
  private User createdBy;

  @Enumerated(EnumType.STRING)
  @Column(name = "crawl_status", nullable = false, length = 10)
  private CrawlStatus crawlStatus;

  /**
   * 자동 재시도를 예약한 횟수({@code V15__add_crawl_retry_to_archive_items.sql}). <b>총 시도 횟수는 {@code 1 +
   * crawlRetries}</b> 다.
   *
   * <p>성공해도 초기화하지 않는다 — "이 자료는 몇 번 만에 됐나"를 나중에 물을 수 있게 기록으로 남긴다.
   */
  @Column(name = "crawl_retries", nullable = false)
  private int crawlRetries;

  /**
   * 다음 크롤링 시도 시각. {@code null}이면 배치가 집어가지 않는다({@code ArchiveCrawlRetryScheduler}).
   *
   * <p>{@code null}인 경우가 셋 있다 — 재시도 대상이 아닌 항목, 배치가 방금 집어간 항목(재선점 방지), 이미 끝난 항목.
   */
  @Column(name = "next_crawl_at")
  private Instant nextCrawlAt;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public ArchiveItem(
      ArchiveFolder folder,
      Room room,
      String title,
      String url,
      String bodyText,
      String source,
      String thumbnail,
      User createdBy) {
    this.folder = folder;
    this.room = room;
    this.title = title;
    this.url = url;
    this.bodyText = bodyText;
    this.source = source;
    this.thumbnail = thumbnail;
    this.createdBy = createdBy;
    this.pinned = false;
    this.crawlStatus = CrawlStatus.DONE;
  }

  /** S-25-D 외부 공유(URL) 등록 — 크롤링 전이라 본문이 없다. */
  public static ArchiveItem pending(
      ArchiveFolder folder, Room room, String title, String url, User createdBy) {
    return pending(folder, room, title, url, createdBy, null);
  }

  /** S-25-C 인앱 등록(URL, 메모 포함) — 크롤링 전이라 본문이 없다. */
  public static ArchiveItem pending(
      ArchiveFolder folder, Room room, String title, String url, User createdBy, String memo) {
    ArchiveItem item = new ArchiveItem();
    item.folder = folder;
    item.room = room;
    item.title = title;
    item.url = url;
    item.bodyText = null;
    item.createdBy = createdBy;
    item.memo = memo;
    item.pinned = false;
    item.crawlStatus = CrawlStatus.PENDING;
    return item;
  }

  /**
   * 텍스트 등록(S-25-C 인앱 · S-25-D 공유) — <b>본문이 이미 있으므로 곧바로 {@code DONE}</b> 이다.
   *
   * <p>🔴 <b>왜 즉시 DONE 인가</b>(2026-08-06 개정). 텍스트는 <b>본문이 등록 시점에 이미 완성</b>이다 — 사용자가 방금 적은 글이라 가져올
   * 것이 없다. 그런데도 {@code PENDING} 으로 두면 앱이 "분석 중" 배지를 그려서, 다 적어 놓은 메모가 아직 처리 중인 것처럼 보인다(2026-08-06
   * 실사용 확인).
   *
   * <p><b>태깅·임베딩은 여전히 뒤에서 돈다.</b> 다만 그건 <b>파생 데이터</b>라 없다고 자료가 미완성인 것이 아니다 — 태그는 몇 초 뒤 조용히 붙는다.
   * {@code crawl_status} 가 답하는 질문은 "본문을 가져왔나"이고, 텍스트는 처음부터 답이 "그렇다"이다.
   *
   * <p>⚠️ 예전 이름({@code pendingText})과 주석은 <b>요약까지 자동으로 돌던 시절</b>의 것이다. 2026-08-06 에 텍스트 자동 요약을 껐고
   * (S-25-B 「AI 요약 만들기」로 옮겼다), 남은 둘로는 사용자를 기다리게 할 이유가 없어졌다.
   *
   * <p>⚠️ 여전히 비동기로 처리기에 넘긴다 — 5초 클라이언트 타임아웃 사고(2026-08-05)를 되돌리지 않기 위해서다. 바뀐 것은 <b>상태뿐</b>이다.
   */
  public static ArchiveItem textDone(
      ArchiveFolder folder, Room room, String title, String bodyText, User createdBy) {
    return textDone(folder, room, title, bodyText, createdBy, null);
  }

  /** S-25-C 인앱 등록(텍스트, 메모 포함) — 위와 같지만 메모를 함께 받는다. */
  public static ArchiveItem textDone(
      ArchiveFolder folder, Room room, String title, String bodyText, User createdBy, String memo) {
    ArchiveItem item = new ArchiveItem();
    item.folder = folder;
    item.room = room;
    item.title = title;
    item.url = null;
    item.bodyText = bodyText;
    item.createdBy = createdBy;
    item.memo = memo;
    item.pinned = false;
    item.crawlStatus = CrawlStatus.DONE;
    return item;
  }

  /**
   * 이미지 등록(S-25-A 폴더 내 직접 업로드, V28 2026-08-09 후속 확정) — 크롤링·AI 태깅/요약/임베딩 대상이 아니라({@code
   * docs/backend/todo-image-archive-handoff.md}와 같은 원칙) 곧바로 {@code DONE}이다. 제목은 사용자가 안 적으면 서비스가
   * 기본값("사진")을 채워 넘긴다.
   */
  public static ArchiveItem imageDone(
      ArchiveFolder folder, Room room, String title, String imageUrl, User createdBy, String memo) {
    ArchiveItem item = new ArchiveItem();
    item.folder = folder;
    item.room = room;
    item.title = title;
    item.imageUrl = imageUrl;
    item.createdBy = createdBy;
    item.memo = memo;
    item.pinned = false;
    item.crawlStatus = CrawlStatus.DONE;
    return item;
  }

  public void pin() {
    this.pinned = true;
  }

  public void unpin() {
    this.pinned = false;
  }

  public void moveToFolder(ArchiveFolder folder) {
    this.folder = folder;
  }

  /**
   * 링크를 바꾼다(자료 편집, 2026-08-06). 새 URL로 다시 분석해야 하므로 {@code PENDING}으로 되돌리고 옛 크롤링 결과·요약·임베딩을 지운다 — 새
   * 링크의 첫 시도이므로 재시도 횟수도 0으로 되돌린다.
   *
   * <p>제목은 새 URL로 프리필한다 — {@link #markCrawlDone}의 {@link #titleIsStillThePrefilledUrl()} 판정을 그대로 태워
   * 재크롤링 결과로 교체되게 하기 위해서다(등록 때와 같은 규칙).
   *
   * <p>태그는 여기서 지우지 않는다 — {@code archive_item_tags}는 별도 테이블이라 호출자(서비스)가 지운다.
   */
  public void editUrl(String newUrl, String placeholderTitle) {
    this.url = newUrl;
    this.title = placeholderTitle;
    this.bodyText = null;
    this.source = null;
    this.thumbnail = null;
    this.summary = null;
    this.embedding = null;
    this.crawlStatus = CrawlStatus.PENDING;
    this.crawlRetries = 0;
    this.nextCrawlAt = null;
  }

  /**
   * 사용자 메모를 반영한다(2026-08-06 도입). {@link #applySummary}와 같은 규칙 — 빈 문자열/공백을 {@code null}로 눌러 "메모 없음"을
   * 한 가지 방식으로만 표현한다.
   */
  public void editMemo(String memo) {
    this.memo = (memo == null || memo.isBlank()) ? null : memo;
  }

  /**
   * 크롤링 결과를 반영한다(S-25-D 비동기 경로).
   *
   * <p>제목은 <b>아직 프리필된 URL 그대로일 때만</b> 교체한다({@link #titleIsStillThePrefilledUrl()}). 공유 다이얼로그가 제목칸에
   * 공유된 URL을 프리필하므로({@code ShareActivity}), 손대지 않고 등록하면 제목이 URL로 남는다 — 그 경우만 크롤링한 제목으로 바꾸고, 사용자가 직접
   * 적은 제목은 덮어쓰지 않는다.
   *
   * <p>길이 상한은 호출자가 적용한다({@code ArchiveTextLimits}) — {@code title}은 {@code VARCHAR(255) NOT
   * NULL}이다.
   */
  public void markCrawlDone(String crawledTitle, String bodyText, String source, String thumbnail) {
    if (titleIsStillThePrefilledUrl() && crawledTitle != null && !crawledTitle.isBlank()) {
      this.title = crawledTitle;
    }
    this.bodyText = bodyText;
    this.source = source;
    this.thumbnail = thumbnail;
    this.crawlStatus = CrawlStatus.DONE;
    this.nextCrawlAt = null;
  }

  /**
   * 저장된 제목이 아직 공유 다이얼로그가 프리필한 URL 그대로인가.
   *
   * <p>완전일치가 아니라 <b>접두사</b>로 보는 이유는 저장 시 제목이 255자로 잘리기 때문이다({@code url} 상한은 2048). 완전일치로 판정하면 긴
   * URL을 공유했을 때 제목이 "중간에서 잘린 URL"로 영영 남는다.
   *
   * <p>{@code url}/{@code title}은 앱이 {@code trim()}해서 보낸 값이라는 전제에 기댄다({@code ShareActivity}) — iOS
   * Share Extension을 만들 때도 같은 전제를 지켜야 한다.
   */
  private boolean titleIsStillThePrefilledUrl() {
    return this.url != null && !this.title.isBlank() && this.url.startsWith(this.title);
  }

  /** 더 해볼 것이 없는 실패 — 사용자에게 "분석 실패"로 보인다. */
  public void markCrawlFailed() {
    this.crawlStatus = CrawlStatus.FAILED;
    this.nextCrawlAt = null;
  }

  /**
   * 다시 해볼 만한 실패 — <b>{@code PENDING} 을 유지한 채</b> 다음 시도 시각만 잡는다(2026-08-06).
   *
   * <p>🔴 <b>상태를 그대로 두는 것이 이 기능의 전부다.</b> 앱은 {@code PENDING} 을 이미 "분석 중"으로 그리고 있어서({@code
   * CrawlStatusBadge}) 앱을 한 줄도 고치지 않고 "분석 실패" 가 사라진다. 사용자는 링크를 공유해두고 나중에 모아보기에서 보므로 20분 지연을 알아채지
   * 못한다.
   *
   * <p>{@link #markCrawlFailed()} 와 짝이다 — 어느 쪽으로 갈지는 {@code CrawlException.isRetryable()} 과 남은 횟수가
   * 정한다({@code ArchiveCrawlProcessor}).
   */
  public void scheduleCrawlRetry(Instant nextAttemptAt) {
    this.crawlRetries++;
    this.nextCrawlAt = nextAttemptAt;
    this.crawlStatus = CrawlStatus.PENDING;
  }

  /**
   * 위와 같지만 <b>재시도 횟수를 올리지 않는다</b> — 요청을 보내지도 못하고 끝났을 때(2026-08-06 리뷰 P2).
   *
   * <p>쿨다운 단락이 그 경우다: 크롤러가 외부 사이트를 한 번도 안 때리고 즉시 실패한다. 그것을 시도로 세면 차단이 길 때 밀려 있던 자료들이 <b>요청 0회로 상한을
   * 소진</b>하고 실패로 확정된다.
   *
   * <p>상한이 안 걸리는 대신 {@code ArchiveCrawlProcessor} 가 <b>등록 후 경과 시간</b>으로 끊는다 — 영원히 "분석 중"으로 남지 않게.
   */
  public void delayCrawlRetry(Instant nextAttemptAt) {
    this.nextCrawlAt = nextAttemptAt;
    this.crawlStatus = CrawlStatus.PENDING;
  }

  /**
   * 크롤링 없이 끝나는 텍스트 공유({@link #textDone})의 완료 처리 — <b>상태만 바꾼다.</b>
   *
   * <p>{@link #markCrawlDone} 을 재사용하지 않는 이유: 그쪽은 제목·본문·출처·썸네일을 <b>덮어쓴다.</b> 텍스트 공유는 사용자가 적은 제목과 본문이
   * 이미 정답이라 덮어쓸 것이 없고, 실수로 {@code null} 을 넘기면 본문이 날아간다.
   */
  public void markDoneWithoutCrawl() {
    this.crawlStatus = CrawlStatus.DONE;
    this.nextCrawlAt = null;
  }

  /**
   * AI 요약을 반영한다. <b>크롤링 상태·본문을 건드리지 않는다</b> — 요약 실패는 자료 등록의 실패가 아니다(AI 태깅 실패 폴백과 같은 방향,
   * specs/OPEN.md 2026-07-27 확정).
   *
   * <p>빈 문자열을 {@code null}로 눌러 <b>"요약 없음"을 한 가지 방식으로만</b> 표현한다. 빈 문자열이 그대로 저장되면 추천 쪽에서 "요약이 있다"고
   * 오판해 근거가 빈 자료를 프롬프트에 넣는다.
   *
   * <p>길이 상한과 앞뒤 공백 제거는 호출자가 한다({@code markCrawlDone}과 같은 규칙).
   */
  public void applySummary(String summary) {
    this.summary = (summary == null || summary.isBlank()) ? null : summary;
  }

  /**
   * 임베딩을 반영한다. {@link #applySummary}와 같은 규칙 — <b>크롤링 상태·본문·요약을 건드리지 않는다.</b> 임베딩 실패는 자료 등록의 실패가
   * 아니다.
   *
   * <p>빈 배열을 {@code null}로 눌러 <b>"임베딩 없음"을 한 가지 방식으로만</b> 표현한다. 길이 0짜리 배열이 그대로 저장되면 읽는 쪽이 "벡터가 있다"고
   * 보고 0차원끼리 코사인을 계산하다 0으로 나누게 된다.
   *
   * <p><b>넘긴 배열도 {@link #getEmbedding()}이 돌려주는 배열도 변형하지 말 것.</b> 방어 복사를 하지 않는다(6KB짜리 배열을 등록마다 두 번
   * 복사할 이유가 없다) — 트랜잭션 안에서 원소를 바꾸면 Hibernate 더티체킹이 조용히 UPDATE를 날린다.
   */
  public void applyEmbedding(float[] embedding) {
    this.embedding = (embedding == null || embedding.length == 0) ? null : embedding;
  }

  public enum CrawlStatus {
    PENDING,
    DONE,
    FAILED
  }
}
