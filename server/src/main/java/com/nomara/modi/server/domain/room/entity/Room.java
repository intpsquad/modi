package com.nomara.modi.server.domain.room.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.time.LocalDate;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

@Entity
@Table(name = "rooms")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Room {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(nullable = false)
  private String name;

  private String coverImage;

  @Column(nullable = false)
  private String goal;

  @Column(columnDefinition = "TEXT")
  private String goalDetail;

  @Column(nullable = false)
  private LocalDate startDate;

  @Column(nullable = false)
  private LocalDate endDate;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, length = 10)
  private RoomStatus status;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public Room(
      String name,
      String coverImage,
      String goal,
      String goalDetail,
      LocalDate startDate,
      LocalDate endDate) {
    this.name = name;
    this.coverImage = coverImage;
    this.goal = goal;
    this.goalDetail = goalDetail;
    this.startDate = startDate;
    this.endDate = endDate;
    this.status = RoomStatus.ACTIVE;
  }

  /** 4-3: end_date 경과 시 자동 전환. */
  public void end() {
    this.status = RoomStatus.ENDED;
  }

  /** S-40-A: 현재 방 설정 저장 — S-10과 동일 필드를 통째로 다시 받는 풀 업데이트. */
  public void update(
      String name,
      String coverImage,
      String goal,
      String goalDetail,
      LocalDate startDate,
      LocalDate endDate) {
    this.name = name;
    this.coverImage = coverImage;
    this.goal = goal;
    this.goalDetail = goalDetail;
    this.startDate = startDate;
    this.endDate = endDate;
  }

  /** S-12: 재시작 시 기간 수정 후 ACTIVE 복귀. */
  public void restart(LocalDate startDate, LocalDate endDate) {
    this.startDate = startDate;
    this.endDate = endDate;
    this.status = RoomStatus.ACTIVE;
  }
}
