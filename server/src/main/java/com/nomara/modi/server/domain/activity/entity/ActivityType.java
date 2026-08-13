package com.nomara.modi.server.domain.activity.entity;

/**
 * 홈 활동 피드(docs/backend/home-activity-feed.md) 이벤트 타입. {@code MILESTONE_PROGRESS}·{@code DDAY}는 프론트가
 * 대시보드 값(진행률·D-day)으로 이미 파생하므로 여기 없다 — 서버가 같은 문구를 또 내려주면 중복이다.
 *
 * <p>적재형(도메인 액션이 일어나는 순간 {@code activities} 테이블에 실제로 insert됨): {@link #TODO_COMPLETED}~{@link
 * #TODO_COMPLETED_SHARED}.
 *
 * <p>파생형(저장하지 않고 {@code ActivityService.getRecentActivities} 조회 시점에 계산해 합류함): {@link
 * #SCHEDULE_SOON}~{@link #NUDGE_UNASSIGNED}. "현재 상태"에 대한 질문이라 append할 단일 트리거가
 * 없다(MILESTONE_PROGRESS/DDAY와 같은 성격).
 */
public enum ActivityType {
  TODO_COMPLETED,
  TODO_ALL_DONE,
  TODO_ADDED,
  SCHEDULE_ADDED,
  ARCHIVE_ADDED,
  ARCHIVE_LIKE_MILESTONE,
  POKE,
  POKE_ACCUMULATED,
  MEMBER_JOINED,

  /**
   * 담당자 2명 이상인 투두를 완료했을 때(docs/backend/live-banner-copy-handoff.md §2) — "팀 성취" 문구용. 개인 완료 ({@link
   * #TODO_COMPLETED})와 성격이 달라 actor+일자로 묶지 않고 건별로 기록한다({@code ActivityService.groupAndMap}이 이 타입은
   * 손대지 않고 그대로 통과시킨다). {@code targetName}에 대표 닉네임(담당자 중 최단), {@code count}에 담당자 총원을 싣는다 — 새 DTO 필드
   * 없이 기존 필드를 재사용한다({@code POKE}가 {@code targetName}을 사람 닉네임으로 쓰는 것과 같은 패턴).
   */
  TODO_COMPLETED_SHARED,

  SCHEDULE_SOON,
  WEEKLY_SUMMARY,
  NUDGE_NONE_TODAY,
  NUDGE_QUIET_MEMBER,

  /**
   * 방에 담당자 없는(미지정) 미완료 투두가 있을 때 지정을 유도(docs/backend/live-banner-copy-handoff.md §4). {@code
   * count}=미지정 투두 수, 0이면 미노출.
   */
  NUDGE_UNASSIGNED
}
