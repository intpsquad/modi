package com.nomara.modi.server.domain.room.dto;

import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomStatus;
import java.time.LocalDate;

public record RoomResponse(
    Long id,
    String name,
    String goal,
    String goalDetail,
    LocalDate startDate,
    LocalDate endDate,
    RoomStatus status,
    String coverImage,
    String inviteCode) {

  public static RoomResponse of(Room room, String inviteCode) {
    return new RoomResponse(
        room.getId(),
        room.getName(),
        room.getGoal(),
        room.getGoalDetail(),
        room.getStartDate(),
        room.getEndDate(),
        room.getStatus(),
        room.getCoverImage(),
        inviteCode);
  }
}
