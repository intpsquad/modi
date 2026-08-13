package com.nomara.modi.server.domain.room.dto;

import com.nomara.modi.server.domain.room.entity.RoomStatus;
import java.time.LocalDate;

public record RoomSummaryResponse(
    Long id,
    String name,
    String goal,
    String goalDetail,
    RoomStatus status,
    LocalDate startDate,
    LocalDate endDate,
    String coverImage) {

  public static RoomSummaryResponse of(com.nomara.modi.server.domain.room.entity.Room room) {
    return new RoomSummaryResponse(
        room.getId(),
        room.getName(),
        room.getGoal(),
        room.getGoalDetail(),
        room.getStatus(),
        room.getStartDate(),
        room.getEndDate(),
        room.getCoverImage());
  }
}
