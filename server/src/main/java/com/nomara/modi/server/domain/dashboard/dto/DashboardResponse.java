package com.nomara.modi.server.domain.dashboard.dto;

import com.nomara.modi.server.domain.activity.dto.ActivityResponse;
import com.nomara.modi.server.domain.room.dto.MemberProgress;
import java.util.List;

/** specs/0005-홈-대시보드.md — 홈 대시보드(S-04) 응답. */
public record DashboardResponse(
    RoomInfo room,
    List<MemberProgress> members,
    List<ScheduleBrief> weekSchedules,
    List<TodoBrief> todayTodos,
    List<ArchiveBrief> recentArchives,
    /**
     * 아카이브 미리보기 — 핀 우선→최신순, 최대 4개. {@code recentArchives}는 순수 최신순으로 그대로 두고 이 필드를 별도로
     * 추가했다(specs/0005-홈-대시보드.md 2026-08-06 확정).
     */
    List<ArchiveBrief> previewArchives,
    /**
     * 핀 고정 자료만(백엔드 요청, 2026-08-07) — 순수 {@code pinned=true} 필터, 최신순, 최대 4개. 핀이 없으면 빈 배열(패딩 없음) —
     * {@code previewArchives}(핀 우선 + 비핀으로 채움)와 의미가 다르다.
     */
    List<ArchiveBrief> pinnedArchives,
    long todoDone,
    long todoTotal,
    /** 홈 활동 피드(docs/backend/home-activity-feed.md) — 최신·중요순, 최근 20건. */
    List<ActivityResponse> activities) {}
