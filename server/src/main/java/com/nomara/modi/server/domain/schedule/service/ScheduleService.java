package com.nomara.modi.server.domain.schedule.service;

import com.nomara.modi.server.domain.activity.entity.ActivityType;
import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.exception.RoomNotFoundException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.schedule.dto.CreateScheduleRequest;
import com.nomara.modi.server.domain.schedule.dto.ScheduleResponse;
import com.nomara.modi.server.domain.schedule.dto.UpdateScheduleRequest;
import com.nomara.modi.server.domain.schedule.entity.Schedule;
import com.nomara.modi.server.domain.schedule.exception.ScheduleNotFoundException;
import com.nomara.modi.server.domain.schedule.repository.ScheduleRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.BadRequestException;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** specs/0009-일정-탭.md — 일정 탭(S-20~20-B) CRUD. */
@Service
public class ScheduleService {

  private final ScheduleRepository scheduleRepository;
  private final RoomRepository roomRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final UserRepository userRepository;
  private final ActivityService activityService;

  public ScheduleService(
      ScheduleRepository scheduleRepository,
      RoomRepository roomRepository,
      RoomMemberRepository roomMemberRepository,
      UserRepository userRepository,
      ActivityService activityService) {
    this.scheduleRepository = scheduleRepository;
    this.roomRepository = roomRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.userRepository = userRepository;
    this.activityService = activityService;
  }

  @Transactional(readOnly = true)
  public List<ScheduleResponse> listSchedules(
      String uid, Long roomId, LocalDate start, LocalDate end) {
    requireMembership(uid, roomId);
    return scheduleRepository.findOverlappingByRoomId(roomId, start, end).stream()
        .map(ScheduleResponse::of)
        .toList();
  }

  @Transactional
  public ScheduleResponse createSchedule(String uid, Long roomId, CreateScheduleRequest request) {
    requireMembership(uid, roomId);
    validateRange(request.date(), request.time(), request.endDate(), request.endTime());
    Room room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
    User creator = userRepository.getReferenceById(uid);
    Schedule saved =
        scheduleRepository.save(
            new Schedule(
                room,
                request.title(),
                request.date(),
                request.time(),
                request.endDate(),
                request.endTime(),
                request.detail(),
                request.place(),
                creator));
    activityService.record(room, ActivityType.SCHEDULE_ADDED, creator, null, null, null);
    return ScheduleResponse.of(saved);
  }

  @Transactional
  public ScheduleResponse updateSchedule(
      String uid, Long roomId, Long scheduleId, UpdateScheduleRequest request) {
    requireMembership(uid, roomId);
    validateRange(request.date(), request.time(), request.endDate(), request.endTime());
    Schedule schedule = resolveSchedule(roomId, scheduleId);
    schedule.update(
        request.title(),
        request.date(),
        request.time(),
        request.endDate(),
        request.endTime(),
        request.detail(),
        request.place());
    return ScheduleResponse.of(schedule);
  }

  /** 다중일 일정이면 종료 시간이 다른 날짜에 속하므로 시작 시간과의 순서 제약을 걸지 않는다 — 같은 날에만 "종료 시간은 시작 시간보다 늦어야 한다"를 강제한다. */
  private void validateRange(LocalDate date, LocalTime time, LocalDate endDate, LocalTime endTime) {
    if (endDate != null && endDate.isBefore(date)) {
      throw new BadRequestException("종료 날짜는 시작 날짜보다 빠를 수 없어요");
    }
    if (endTime != null) {
      if (time == null) {
        throw new BadRequestException("종료 시간을 설정하려면 시작 시간을 먼저 설정해야 해요");
      }
      boolean sameDay = endDate == null || endDate.equals(date);
      if (sameDay && !endTime.isAfter(time)) {
        throw new BadRequestException("종료 시간은 시작 시간보다 늦어야 해요");
      }
    }
  }

  @Transactional
  public void deleteSchedule(String uid, Long roomId, Long scheduleId) {
    requireMembership(uid, roomId);
    Schedule schedule = resolveSchedule(roomId, scheduleId);
    scheduleRepository.delete(schedule);
  }

  private Schedule resolveSchedule(Long roomId, Long scheduleId) {
    Schedule schedule =
        scheduleRepository.findById(scheduleId).orElseThrow(ScheduleNotFoundException::new);
    if (!schedule.getRoom().getId().equals(roomId)) {
      throw new ScheduleNotFoundException();
    }
    return schedule;
  }

  private void requireMembership(String uid, Long roomId) {
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, uid))) {
      throw new NotRoomMemberException();
    }
  }
}
