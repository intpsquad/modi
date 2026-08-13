package com.nomara.modi.server.domain.archive.entity;

import com.nomara.modi.server.domain.room.entity.Room;
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

@Entity
@Table(name = "archive_folders")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class ArchiveFolder {

  /** 방마다 항상 보장되는 기본 폴더 이름(백엔드 요청, 2026-08-07). */
  public static final String DEFAULT_FOLDER_NAME = "기본";

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "room_id", nullable = false)
  private Room room;

  @Column(nullable = false)
  private String name;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public ArchiveFolder(Room room, String name) {
    this.room = room;
    this.name = name;
  }

  public void rename(String name) {
    this.name = name;
  }
}
