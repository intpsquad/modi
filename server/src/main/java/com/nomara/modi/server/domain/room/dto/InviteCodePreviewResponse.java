package com.nomara.modi.server.domain.room.dto;

import com.nomara.modi.server.domain.room.entity.RoomStatus;
import java.time.LocalDate;

/**
 * S-11 참여 확인 모달의 "멤버 N명 · 기간" 표기용 {@code memberCount}/{@code startDate}/{@code endDate}(2026-08-07,
 * ) — 이전엔 이 세 값이 없어 FE가 표기하지 못했다({@code specs/0004-방-생성-참여.md}).
 */
public record InviteCodePreviewResponse(
    Long roomId,
    String name,
    String goal,
    RoomStatus status,
    int memberCount,
    LocalDate startDate,
    LocalDate endDate) {}
