package com.nomara.modi.server.domain.character.entity;

/**
 * 협업 캐릭터(specs/0016-협업-캐릭터.md) 판정용 접속·조회 로그 종류. 소셜 이벤트 피드인 {@code
 * com.nomara.modi.server.domain.activity.entity.ActivityType}과는 다른 개념이다 — 이쪽은 "누가 봤나"를 기록하는 개인 행동
 * 로그다(specs/OPEN.md 참고).
 *
 * <p>{@link #ROOM_VIEW}·{@link #ARCHIVE_ITEM_VIEW}·{@link #TODO_VIEW}는 기존 조회 엔드포인트에 얹어 앱 변경 없이 자동
 * 기록된다. {@link #APP_OPEN}만 대응하는 기존 엔드포인트가 없어 전용 엔드포인트({@code POST /me/activity/app-open})를 새로
 * 만들었지만, 이 커밋 시점엔 앱이 아직 호출하지 않는다.
 */
public enum UserActivityKind {
  APP_OPEN,
  ROOM_VIEW,
  ARCHIVE_ITEM_VIEW,
  TODO_VIEW
}
