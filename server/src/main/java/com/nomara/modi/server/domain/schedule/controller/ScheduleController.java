package com.nomara.modi.server.domain.schedule.controller;

import com.nomara.modi.server.domain.schedule.dto.CreateScheduleRequest;
import com.nomara.modi.server.domain.schedule.dto.ScheduleResponse;
import com.nomara.modi.server.domain.schedule.dto.UpdateScheduleRequest;
import com.nomara.modi.server.domain.schedule.service.ScheduleService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** specs/0009-일정-탭.md — 일정 CRUD(S-20~20-B). */
@RestController
public class ScheduleController {

  private final ScheduleService scheduleService;

  public ScheduleController(ScheduleService scheduleService) {
    this.scheduleService = scheduleService;
  }

  @GetMapping("/rooms/{roomId}/schedules")
  public List<ScheduleResponse> list(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate start,
      @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate end) {
    return scheduleService.listSchedules(uid(request), roomId, start, end);
  }

  @PostMapping("/rooms/{roomId}/schedules")
  @ResponseStatus(HttpStatus.CREATED)
  public ScheduleResponse create(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @Valid @RequestBody CreateScheduleRequest body) {
    return scheduleService.createSchedule(uid(request), roomId, body);
  }

  @PutMapping("/rooms/{roomId}/schedules/{scheduleId}")
  public ScheduleResponse update(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long scheduleId,
      @Valid @RequestBody UpdateScheduleRequest body) {
    return scheduleService.updateSchedule(uid(request), roomId, scheduleId, body);
  }

  @DeleteMapping("/rooms/{roomId}/schedules/{scheduleId}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void delete(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable Long scheduleId) {
    scheduleService.deleteSchedule(uid(request), roomId, scheduleId);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
