package com.nomara.modi.server.domain.schedule.exception;

import com.nomara.modi.server.global.exception.NotFoundException;

public class ScheduleNotFoundException extends NotFoundException {

  public ScheduleNotFoundException() {
    super("일정을 찾을 수 없어요");
  }
}
