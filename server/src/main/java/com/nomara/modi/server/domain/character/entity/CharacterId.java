package com.nomara.modi.server.domain.character.entity;

/**
 * 협업 캐릭터 식별자(specs/0016-협업-캐릭터.md 1장 명단 그대로). 저장되지 않는다 — {@code CharacterService}가 매 요청마다 기존
 * 신호(투두·자료·좋아요·접속 로그)로 즉석에서 판정한다.
 */
public enum CharacterId {
  // 느긋 계열(진화 전)
  PROCRASTINATOR,
  GHOST,
  LURKER,
  TURTLE,

  // 갓생 계열(진화 후 · 목표)
  STEADY,
  SPRINTER,
  EARLYBIRD,
  THE_J,

  // 보조·기타
  CHEERLEADER,
  WARMING_UP
}
