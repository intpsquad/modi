package com.nomara.modi.server.domain.schedule.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.time.LocalTime;

public record UpdateScheduleRequest(
    @NotBlank @Size(min = 1, max = 50) String title,
    @NotNull LocalDate date,
    LocalTime time,
    LocalDate endDate,
    LocalTime endTime,
    @Size(max = 500) String detail,
    @Size(max = 100) String place) {}
