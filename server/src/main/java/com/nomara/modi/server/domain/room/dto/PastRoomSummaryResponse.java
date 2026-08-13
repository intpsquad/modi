package com.nomara.modi.server.domain.room.dto;

import java.time.LocalDate;

public record PastRoomSummaryResponse(
    Long id, String name, LocalDate startDate, LocalDate endDate, double completionRate) {}
