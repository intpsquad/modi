package com.nomara.modi.server.domain.archive.entity;

import com.nomara.modi.server.domain.user.entity.User;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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

/**
 * 자료 상세 댓글(docs/backend/archive-comments-handoff.md) — 방 전체가 보는 공유 콘텐츠라 작성자가 탈퇴해도 댓글은 남고 {@code
 * author}만 {@code null}이 된다({@code archive_items.created_by}와 같은 근거).
 *
 * <p>2026-08-09부터 작성자 본인의 수정·삭제를 지원한다(append-only가 아니게 됐다) — {@code author == null}인(탈퇴한 작성자) 댓글은
 * 아무도 수정·삭제할 수 없다({@code ArchiveCommentService}).
 */
@Entity
@Table(name = "archive_item_comments")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ArchiveItemComment {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "item_id", nullable = false)
  private ArchiveItem item;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "author_user_id")
  private User author;

  @Column(nullable = false, length = 500)
  private String body;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public ArchiveItemComment(ArchiveItem item, User author, String body) {
    this.item = item;
    this.author = author;
    this.body = body;
  }

  public void editBody(String body) {
    this.body = body;
  }
}
