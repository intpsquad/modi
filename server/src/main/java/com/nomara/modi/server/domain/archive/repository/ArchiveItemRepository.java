package com.nomara.modi.server.domain.archive.repository;

import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

public interface ArchiveItemRepository extends JpaRepository<ArchiveItem, Long> {

  List<ArchiveItem> findByRoomIdOrderByCreatedAtDesc(Long roomId, Pageable pageable);

  /**
   * 상세 응답을 만들 항목 한 건 — {@code folder}와 {@code createdBy}를 <b>함께</b> 가져온다(2026-08-08).
   *
   * <p><b>쿼리 수를 줄이려고 둔다.</b> 상세 응답이 폴더 이름과 등록자 닉네임을 싣게 되면서 지연 로딩 두 개를 새로 건드리는데, 상세 조회는 아카이브에서 가장 자주
   * 불리는 경로다. 그냥 {@code findById}면 항목·폴더·등록자로 SELECT 가 3번 나간다.
   *
   * <p>⚠️ <b>{@code LazyInitializationException} 을 막는 것은 이 메서드가 아니다.</b> 처음엔 그렇게 적었는데 변형으로 확인해 보니
   * 틀렸다 — 여기를 {@code findById} 로 되돌려도 테스트가 통과한다. 실제로 예외를 막는 것은 {@code updateUrl} 이 응답을 {@code
   * save()} 의 <b>반환값이 아니라 이 메서드가 돌려준 인스턴스</b>로 만드는 부분이다(그쪽에 근거를 적어 뒀다). 이 join fetch 는 그 위에 얹은
   * 여유분이지 방어선이 아니다.
   *
   * <p>{@code createdBy}는 {@code left join}이다. 탈퇴한 사용자의 자료는 방에 남고 작성자만 {@code null}이 되므로({@code
   * V9__account_deletion_cascades.sql}) inner join 이면 그 자료가 통째로 조회되지 않는다 — 이쪽은 {@code
   * getDetailWorksForItemWithoutCreator} 가 실제로 잡는다.
   */
  @Query(
      "select i from ArchiveItem i "
          + "join fetch i.folder left join fetch i.createdBy where i.id = :id")
  Optional<ArchiveItem> findForDetailById(@Param("id") Long id);

  /** 협업 캐릭터(specs/0016) activityStats.shared — 이 사용자가 등록(공유)한 자료 전체 건수(방 무관). */
  long countByCreatedById(String userId);

  /**
   * 같은 URL 을 최근에 이미 크롤링한 항목 — <b>다시 긁지 않기 위해</b> 찾는다(2026-08-06).
   *
   * <p>🔴 <b>왜 필요한가.</b> 운영 EC2 IP 가 인스타에서 소프트 블록됐고, 참조 문서(test.md)의 처방 셋 중 첫째가 <i>"Cache
   * aggressively (e.g. 24h)"</i> 다. 우리는 같은 링크를 다시 공유해도 매번 새로 긁고 있었다 — 운영 데이터로 인스타 19건 중 4건이 중복 URL
   * 이었다.
   *
   * <p><b>방을 가리지 않는다.</b> 크롤링 결과는 공개 콘텐츠라 방을 넘나들어도 사용자 정보가 새지 않고, 같은 인기 게시물이 여러 방에 공유되는 경우가 이 캐시의
   * 최대 효과 지점이다. 근거는 {@code ArchiveCrawlProcessor} 의 재사용 판정 주석에 모아뒀다.
   *
   * <p>{@code createdAt} 을 기준으로 쓰는 이유: {@code updated_at} 컬럼이 없고, 항목은 생성 직후 크롤링되므로 "언제 긁었나"의 근사로
   * 충분하다.
   */
  Optional<ArchiveItem> findFirstByUrlAndCrawlStatusAndCreatedAtAfterOrderByCreatedAtDesc(
      String url, ArchiveItem.CrawlStatus crawlStatus, Instant createdAfter);

  /**
   * 홈 미리보기용 최근 자료 — 특정 {@code crawlStatus}를 제외하고 최신순으로 가져온다.
   *
   * <p>🔴 <b>왜 걸러내는 것을 쿼리에 두는가</b>: 호출부가 상위 N개를 받은 뒤 자바에서 걸러내면 <b>개수가 줄어든다</b>(실패 자료가 최근에 몰리면 미리보기가
   * 비어 보인다). 페이지 크기를 적용하기 <b>전에</b> 제외해야 한다.
   */
  List<ArchiveItem> findByRoomIdAndCrawlStatusNotOrderByCreatedAtDesc(
      Long roomId, ArchiveItem.CrawlStatus crawlStatus, Pageable pageable);

  /**
   * 홈 미리보기용 핀 우선 자료 — {@code pinned desc}가 먼저라 핀 자료가 앞을 채우고, 부족분은 최신 비핀으로 자동 보충된다(핀 개수와 무관하게 한 번의
   * 정렬+LIMIT으로 충분 — 별도 자바 병합 불필요).
   */
  List<ArchiveItem> findByRoomIdAndCrawlStatusNotOrderByPinnedDescCreatedAtDesc(
      Long roomId, ArchiveItem.CrawlStatus crawlStatus, Pageable pageable);

  /**
   * 홈 미리보기용 순수 핀 자료(백엔드 요청, 2026-08-07) — {@code pinnedArchives}. 위 {@code previewArchives}용 메서드와
   * 달리 <b>핀이 아닌 항목은 아예 후보에서 뺀다</b> — 핀 0개면 빈 배열이 나온다(패딩 없음).
   */
  List<ArchiveItem> findByRoomIdAndCrawlStatusNotAndPinnedTrueOrderByCreatedAtDesc(
      Long roomId, ArchiveItem.CrawlStatus crawlStatus, Pageable pageable);

  List<ArchiveItem> findByFolderIdOrderByCreatedAtDesc(Long folderId);

  /** 폴더 내 목록 표시용 핀 우선 정렬 — 위와 같은 이유로 핀이 항상 최상단에 온다. */
  List<ArchiveItem> findByFolderIdOrderByPinnedDescCreatedAtDesc(Long folderId);

  long countByFolderId(Long folderId);

  /** 폴더별 항목 개수 — 0개인 폴더는 결과에 나타나지 않으므로 호출부에서 기본값 0으로 채워야 한다. */
  @Query(
      "select i.folder.id as folderId, count(i) as itemCount "
          + "from ArchiveItem i where i.room.id = :roomId group by i.folder.id")
  List<FolderItemCount> countByFolderIdForRoom(@Param("roomId") Long roomId);

  /**
   * 폴더 대표 썸네일 후보 — 방 전체에서 thumbnail 이 있는 항목만 최신순으로 가져온다. 폴더별로 가장 최근(=처음 나오는) 것을 대표로 쓰라고
   * 호출부(Map.putIfAbsent)에 넘기는 용도라, group by 로 폴더당 1건만 뽑지 않는다 — JPQL 의 group by 는 "가장 최근 행의
   * thumbnail"을 직접 못 구한다(집계 함수만 허용).
   */
  @Query(
      "select i.folder.id as folderId, i.thumbnail as thumbnail "
          + "from ArchiveItem i where i.room.id = :roomId and i.thumbnail is not null "
          + "order by i.createdAt desc, i.id desc")
  List<FolderThumbnail> findThumbnailCandidatesForRoom(@Param("roomId") Long roomId);

  /**
   * 임베딩이 아직 없는 항목의 id (백필용).
   *
   * <p>엔티티가 아니라 <b>id만</b> 가져온다 — 백필은 자료 전체를 훑는데, 본문(최대 20,000자)까지 한꺼번에 메모리에 올릴 이유가 없다. 실제 처리는 id로
   * 한 건씩 다시 읽어 각자의 트랜잭션에서 한다.
   *
   * <p>{@code crawl_status = 'PENDING'}은 제외한다 — 임베딩할 본문이 아직 없어서 불러 봐야 {@code null}이 되고, 크롤링이 끝나면
   * {@code ArchiveCrawlProcessor}가 알아서 붙인다.
   */
  @Query(
      "select i.id from ArchiveItem i "
          + "where i.embedding is null and i.crawlStatus <> com.nomara.modi.server.domain.archive"
          + ".entity.ArchiveItem$CrawlStatus.PENDING order by i.id")
  List<Long> findIdsWithoutEmbedding();

  /**
   * 요약이 아직 없는 항목의 id (백필용). 위 {@link #findIdsWithoutEmbedding()}과 같은 이유로 id만 가져오고 {@code PENDING}을
   * 제외한다.
   *
   * <p><b>왜 필요한가.</b> 요약이 없으면 추천 프롬프트에 <b>본문 전체</b>가 실린다({@code
   * TodoSuggestionPayloadLoader.pickContent}는 요약·본문 중 짧은 쪽을 고른다). 실측(부산 여행 방): 요약 있는 4건이 529자인데 요약
   * 없는 4건이 34,206자로 <b>프롬프트의 98%</b>를 차지했고, 그 본문에는 크롤링에 딸려온 블로그 UI 텍스트가 섞여 있었다.
   */
  @Query(
      "select i.id from ArchiveItem i "
          + "where i.summary is null and i.crawlStatus <> com.nomara.modi.server.domain.archive"
          + ".entity.ArchiveItem$CrawlStatus.PENDING order by i.id")
  List<Long> findIdsWithoutSummary();

  /**
   * 재시도할 때가 된 항목의 id (2026-08-06, {@code ArchiveCrawlRetryScheduler}).
   *
   * <p>엔티티가 아니라 <b>id만</b> 가져온다 — 처리기가 어차피 자기 트랜잭션에서 다시 읽는다. 본문(최대 20,000자)을 여기서 메모리에 올릴 이유가 없다.
   *
   * <p>{@code nextCrawlAt} 오름차순이라 <b>가장 오래 기다린 것부터</b> 나간다. 한 tick 상한에 걸려 잘릴 때 뒤로 밀린 항목이 굶지 않는다.
   *
   * <p>{@code PENDING} 조건이 있어야 하는 이유: {@code next_crawl_at} 을 비우는 것과 상태를 바꾸는 것이 서로 다른 트랜잭션이라, 이론상
   * 이미 끝난 항목이 시각만 남은 채로 보일 수 있다.
   */
  @Query(
      "select i.id from ArchiveItem i "
          + "where i.crawlStatus = com.nomara.modi.server.domain.archive.entity"
          + ".ArchiveItem$CrawlStatus.PENDING "
          + "and i.nextCrawlAt is not null and i.nextCrawlAt <= :dueBy "
          + "order by i.nextCrawlAt")
  List<Long> findIdsDueForCrawlRetry(@Param("dueBy") Instant dueBy, Pageable pageable);

  /**
   * 집어간 항목의 다음 시도 예약을 지운다 — <b>다음 tick 이 같은 항목을 또 집지 않게.</b>
   *
   * <p>🔴 <b>왜 엔티티가 아니라 벌크 UPDATE 인가.</b> 배치가 엔티티를 로드해 필드를 비우면, 그 트랜잭션이 커밋되기 전에 비동기 처리기가 같은 행을 먼저
   * 갱신할 수 있다. 그러면 배치 쪽 더티체킹이 <b>모든 컬럼</b>을 옛 값으로 되돌려 쓴다(본문·상태까지). 이 쿼리는 {@code next_crawl_at} 한 컬럼만
   * 건드려서 그 사고가 성립하지 않는다.
   *
   * <p>처리기에 넘기기 <b>전에</b> 부르고, 자기 트랜잭션에서 바로 커밋된다.
   */
  @Modifying(clearAutomatically = true, flushAutomatically = true)
  @Transactional
  @Query("update ArchiveItem i set i.nextCrawlAt = null where i.id in :ids")
  void clearNextCrawlAt(@Param("ids") Collection<Long> ids);

  /**
   * 집어놓고 처리기에 넘기지 못한 항목을 <b>다시 줄 세운다</b>(2026-08-06).
   *
   * <p>{@code archiveCrawlExecutor} 는 {@code AbortPolicy} 라 큐(50)가 차면 {@code
   * RejectedExecutionException} 을 던진다. 그때 아무것도 안 하면 위에서 예약을 이미 지웠으므로 그 항목은 <b>영영 안 집히는 PENDING</b>
   * 이 된다 — 재시도가 만들려던 상태(영구 "분석 중")를 재시도가 만드는 꼴이다.
   *
   * <p>재시도 횟수는 올리지 않는다. 실패한 것이 아니라 <b>보내지도 못한</b> 것이다.
   */
  @Modifying(clearAutomatically = true, flushAutomatically = true)
  @Transactional
  @Query("update ArchiveItem i set i.nextCrawlAt = :nextCrawlAt where i.id in :ids")
  void rescheduleCrawl(
      @Param("ids") Collection<Long> ids, @Param("nextCrawlAt") Instant nextCrawlAt);

  interface FolderItemCount {
    Long getFolderId();

    long getItemCount();
  }

  interface FolderThumbnail {
    Long getFolderId();

    String getThumbnail();
  }
}
