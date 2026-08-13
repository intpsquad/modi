package com.nomara.modi.server.domain.dashboard.dto;

import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomStatus;
import java.time.LocalDate;

public record RoomInfo(
    Long id,
    String name,
    String coverImage,
    String goal,
    String goalDetail,
    LocalDate startDate,
    LocalDate endDate,
    RoomStatus status) {

  public static RoomInfo of(Room room) {
    return new RoomInfo(
        room.getId(),
        room.getName(),
        room.getCoverImage(),
        room.getGoal(),
        room.getGoalDetail(),
        room.getStartDate(),
        room.getEndDate(),
        room.getStatus());
  }
}
