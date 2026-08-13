package com.nomara.modi.server.domain.activity.dto;

import java.time.Instant;

/**
 * 홈 활동 피드 항목(docs/backend/home-activity-feed.md). 문구는 프론트가 조립하므로 서버는 구조화된 값만 준다.
 *
 * <p>{@code targetName}은 타입에 따라 뜻이 다르다 — 대상이 사람이면(POKE) 그 사람의 닉네임, 대상이 자료면(ARCHIVE_ADDED) 폴더/자료 이름.
 * {@code secondaryCount}는 {@code WEEKLY_SUMMARY} 전용(지난주 대비 증감) — 그 타입 말고는 항상 {@code null}이다.
 */
public record ActivityResponse(
    String type,
    String actorNickname,
    String actorUserId,
    Integer count,
    String targetName,
    Integer secondaryCount,
    Instant createdAt) {}
