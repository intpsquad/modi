package com.nomara.modi.server.domain.character.dto;

import com.nomara.modi.server.domain.character.entity.CharacterId;

/**
 * 협업 캐릭터(specs/0016-협업-캐릭터.md) 응답 — 핸드오프 문서 4.3 계약 그대로다. 취향 태그(taste tag)는 이번 스코프 제외라 필드가
 * 없다(`specs/OPEN.md` 근거).
 */
public record CharacterResponse(
    CharacterId characterId,
    String name,
    String copy,
    String why,
    CharacterId evolveTo,
    Double evolveProgress,
    String evolveHint,
    Confidence confidence,
    ActivityStatsResponse activityStats) {

  public enum Confidence {
    LOW,
    HIGH
  }
}
