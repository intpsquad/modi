package com.nomara.modi.server.domain.category.entity;

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

/** 방 내 투두 그룹 — 마감·담당자 없음. */
@Entity
@Table(name = "categories")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Category {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "room_id", nullable = false)
  private Room room;

  @Column(nullable = false)
  private String name;

  @Column(nullable = false)
  private int position;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public Category(Room room, String name) {
    this(room, name, 0);
  }

  public Category(Room room, String name, int position) {
    this.room = room;
    this.name = name;
    this.position = position;
  }

  public void rename(String name) {
    this.name = name;
  }

  public void moveTo(int position) {
    this.position = position;
  }
}
