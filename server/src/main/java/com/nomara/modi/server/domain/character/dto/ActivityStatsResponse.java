package com.nomara.modi.server.domain.character.dto;

/**
 * 협업 캐릭터(specs/0016-협업-캐릭터.md) 판정 근거가 된 원 수치 — 프로필 화면 보조 지표용.
 *
 * <p>{@code dueDateCompletedCount}가 0이면 {@code deadlineKeptRate}는 "0%"가 아니라 <b>잴 데이터가 없다</b>는
 * 뜻이다(마감일 있는 완료 투두가 하나도 없음) — 프론트는 이 카운트로 마감 준수 지표 표시 여부를 게이팅해야 한다(2026-08-09, 마감일 없는 투두만 있어도 "마감
 * 준수 0%"로 보이던 오표시 수정).
 */
public record ActivityStatsResponse(
    long completed,
    int streak,
    double deadlineKeptRate,
    long helpGiven,
    long shared,
    long dueDateCompletedCount) {}
