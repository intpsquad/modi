package com.nomara.modi.server.domain.archive.repository;

import com.nomara.modi.server.domain.archive.entity.ArchiveLike;
import com.nomara.modi.server.domain.archive.entity.ArchiveLikeId;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ArchiveLikeRepository extends JpaRepository<ArchiveLike, ArchiveLikeId> {

  long countByItemId(Long itemId);

  /** 협업 캐릭터 CHEERLEADER 판정(specs/0016) — 이 사용자가 남에게(자기 자신 포함 가능성 없음, 자기 글엔 좋아요 UI 없음) 준 좋아요 수. */
  long countByUserId(String userId);

  /** 폴더별 항목당 좋아요 수 — 좋아요 0개인 항목은 결과에 나타나지 않으므로 호출부에서 기본값 0으로 채워야 한다. */
  @Query(
      "select l.item.id as itemId, count(l) as likeCount "
          + "from ArchiveLike l where l.item.folder.id = :folderId group by l.item.id")
  List<ItemLikeCount> countByItemIdForFolder(@Param("folderId") Long folderId);

  /**
   * 방별 항목당 좋아요 수 — 투두 추천이 자료 순위를 매길 때 쓴다({@code TodoSuggestionPayloadLoader}).
   *
   * <p>폴더 단위가 아니라 방 단위인 이유는 추천이 <b>방의 자료 전체</b>를 근거로 삼기 때문이다. 위와 마찬가지로 <b>좋아요 0개인 항목은 결과에 나타나지
   * 않으므로</b> 호출부에서 0으로 채워야 한다.
   */
  @Query(
      "select l.item.id as itemId, count(l) as likeCount "
          + "from ArchiveLike l where l.item.room.id = :roomId group by l.item.id")
  List<ItemLikeCount> countByItemIdForRoom(@Param("roomId") Long roomId);

  interface ItemLikeCount {
    Long getItemId();

    long getLikeCount();
  }
}
