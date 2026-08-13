package com.nomara.modi.server.domain.schedule.repository;

import com.nomara.modi.server.domain.schedule.entity.Schedule;
import java.time.LocalDate;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ScheduleRepository extends JpaRepository<Schedule, Long> {

  /**
   * 일정 구간 [date, endDate ?? date]이 조회 구간 [start, end]과 겹치는지로 필터한다 — 다중일 일정은 시작일이 조회 구간보다 이전이어도(조회
   * 구간 안으로 걸치기만 하면) 보여야 하므로 단순 {@code date BETWEEN}으로는 부족하다. {@code nulls first}로 정렬해 시간 미지정(종일)
   * 일정이 먼저 오게 한다(서비스 계층의 인메모리 재정렬이 더는 필요 없다).
   */
  @Query(
      "select s from Schedule s where s.room.id = :roomId "
          + "and s.date <= :end and coalesce(s.endDate, s.date) >= :start "
          + "order by s.date asc, s.time asc nulls first")
  List<Schedule> findOverlappingByRoomId(
      @Param("roomId") Long roomId, @Param("start") LocalDate start, @Param("end") LocalDate end);

  /**
   * 일정 전날/디데이 알림 배치(specs/0015-알림-트리거.md) — 시작일({@code date})만 기준(다중일 일정의 endDate는 안 봄, 2026-08-05
   * 확정). {@code r.status}(ACTIVE/ENDED)는 요청 시점에만 lazy 갱신되므로({@code RoomService.refreshStatus}) 아무도
   * 열어보지 않은 방은 실제로 끝났어도 DB엔 여전히 ACTIVE로 남아 있을 수 있다 — 그래서 status 대신 {@code r.endDate}를 직접 비교해 "이 방이
   * 오늘 기준으로 아직 끝나지 않았는지"를 계산한다(방 엔티티의 자동 종료 조건 {@code LocalDate.now().isAfter(endDate)}와 동치).
   */
  @Query(
      "select s from Schedule s join fetch s.room r "
          + "where s.date = :date and r.endDate >= :today "
          + "order by r.id asc, s.id asc")
  List<Schedule> findByDateForActiveRooms(
      @Param("date") LocalDate date, @Param("today") LocalDate today);
}
