package com.nomara.modi.server.domain.dashboard.dto;

import com.nomara.modi.server.domain.schedule.entity.Schedule;
import java.time.LocalDate;
import java.time.LocalTime;

public record ScheduleBrief(
    Long id, String title, LocalDate date, LocalTime time, LocalDate endDate, LocalTime endTime) {

  public static ScheduleBrief of(Schedule schedule) {
    return new ScheduleBrief(
        schedule.getId(),
        schedule.getTitle(),
        schedule.getDate(),
        schedule.getTime(),
        schedule.getEndDate(),
        schedule.getEndTime());
  }
}
