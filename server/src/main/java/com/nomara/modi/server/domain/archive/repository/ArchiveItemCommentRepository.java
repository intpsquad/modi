package com.nomara.modi.server.domain.archive.repository;

import com.nomara.modi.server.domain.archive.entity.ArchiveItemComment;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ArchiveItemCommentRepository extends JpaRepository<ArchiveItemComment, Long> {

  /** 오래된 순 — 채팅형 UI가 새 댓글을 하단에 이어붙이는 것과 맞춘다. */
  List<ArchiveItemComment> findByItemIdOrderByCreatedAtAscIdAsc(Long itemId);

  long countByItemId(Long itemId);

  /**
   * 수정·삭제 스코프 격리 — 다른 자료의 댓글 id로 접근하면 조회 자체가 안 된다({@code ArchiveItemService.resolveItem}과 같은 원칙).
   */
  Optional<ArchiveItemComment> findByIdAndItemId(Long id, Long itemId);
}
