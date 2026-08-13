package com.nomara.modi.server.domain.schedule.dto;

import com.nomara.modi.server.domain.schedule.entity.Schedule;
import java.time.LocalDate;
import java.time.LocalTime;

public record ScheduleResponse(
    Long id,
    String title,
    LocalDate date,
    LocalTime time,
    LocalDate endDate,
    LocalTime endTime,
    String detail,
    String place) {

  public static ScheduleResponse of(Schedule schedule) {
    return new ScheduleResponse(
        schedule.getId(),
        schedule.getTitle(),
        schedule.getDate(),
        schedule.getTime(),
        schedule.getEndDate(),
        schedule.getEndTime(),
        schedule.getDetail(),
        schedule.getPlace());
  }
}
