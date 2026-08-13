package com.nomara.modi.server.domain.archive.entity;

import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.MapsId;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

/** AI 자동 태깅, 편집 가능. */
@Entity
@Table(name = "archive_item_tags")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ArchiveItemTag {

  @EmbeddedId private ArchiveItemTagId id;

  @ManyToOne(fetch = FetchType.LAZY)
  @MapsId("itemId")
  @JoinColumn(name = "item_id")
  private ArchiveItem item;

  public ArchiveItemTag(ArchiveItem item, String tag) {
    this.item = item;
    this.id = new ArchiveItemTagId(item.getId(), tag);
  }
}
