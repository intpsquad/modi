package com.nomara.modi.server.domain.room.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.LocalDate;

public record UpdateRoomRequest(
    @NotBlank String name,
    @NotBlank String goal,
    String goalDetail,
    @NotNull LocalDate startDate,
    @NotNull LocalDate endDate,
    String coverImage) {}
