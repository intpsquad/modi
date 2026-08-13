package com.nomara.modi.server.domain.schedule.entity;

import com.nomara.modi.server.domain.room.entity.Room;
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
import java.time.LocalDate;
import java.time.LocalTime;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

/** 투두와 독립·팀 전체용 일정. 담당자 없음. 홈 주간 캘린더는 이 데이터만 연동. */
@Entity
@Table(name = "schedules")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Schedule {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "room_id", nullable = false)
  private Room room;

  @Column(nullable = false)
  private String title;

  @Column(nullable = false)
  private LocalDate date;

  private LocalTime time;

  private LocalDate endDate;

  private LocalTime endTime;

  @Column(columnDefinition = "TEXT")
  private String detail;

  @Column(length = 100)
  private String place;

  /**
   * 작성자(2026-08-06, 홈 활동 피드 SCHEDULE_ADDED 이벤트용). 일정도 방 전체가 보는 공유 콘텐츠라 작성자가 탈퇴해도 일정은 남고 작성자만 {@code
   * null}이 된다(`Todo.createdBy`와 같은 근거). 기존 생성자를 그대로 두고 오버로드를 추가한 이유도 같다(기존 호출부 14곳).
   */
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "created_by")
  private User createdBy;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public Schedule(
      Room room,
      String title,
      LocalDate date,
      LocalTime time,
      LocalDate endDate,
      LocalTime endTime,
      String detail,
      String place) {
    this.room = room;
    this.title = title;
    this.date = date;
    this.time = time;
    this.endDate = normalizeEndDate(date, endDate);
    this.endTime = endTime;
    this.detail = detail;
    this.place = place;
  }

  public Schedule(
      Room room,
      String title,
      LocalDate date,
      LocalTime time,
      LocalDate endDate,
      LocalTime endTime,
      String detail,
      String place,
      User createdBy) {
    this(room, title, date, time, endDate, endTime, detail, place);
    this.createdBy = createdBy;
  }

  public void update(
      String title,
      LocalDate date,
      LocalTime time,
      LocalDate endDate,
      LocalTime endTime,
      String detail,
      String place) {
    this.title = title;
    this.date = date;
    this.time = time;
    this.endDate = normalizeEndDate(date, endDate);
    this.endTime = endTime;
    this.detail = detail;
    this.place = place;
  }

  /** endDate가 date와 같으면 "단일일 일정"의 대표 표현을 null 하나로 고정한다(응답에 불필요한 값이 안 나가게). */
  private static LocalDate normalizeEndDate(LocalDate date, LocalDate endDate) {
    return date.equals(endDate) ? null : endDate;
  }
}
