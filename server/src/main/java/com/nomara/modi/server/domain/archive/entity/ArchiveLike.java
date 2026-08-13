package com.nomara.modi.server.domain.archive.entity;

import com.nomara.modi.server.domain.user.entity.User;
import jakarta.persistence.Column;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.MapsId;
import jakarta.persistence.Table;
import java.time.Instant;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

/** 좋아요 수 = count(*), 좋아요순 정렬 지원. */
@Entity
@Table(name = "archive_likes")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ArchiveLike {

  @EmbeddedId private ArchiveLikeId id;

  @ManyToOne(fetch = FetchType.LAZY)
  @MapsId("itemId")
  @JoinColumn(name = "item_id")
  private ArchiveItem item;

  @ManyToOne(fetch = FetchType.LAZY)
  @MapsId("userId")
  @JoinColumn(name = "user_id")
  private User user;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public ArchiveLike(ArchiveItem item, User user) {
    this.item = item;
    this.user = user;
    this.id = new ArchiveLikeId(item.getId(), user.getId());
  }
}
