package com.nomara.modi.server.domain.character.service;

import com.nomara.modi.server.domain.character.entity.CharacterId;
import java.util.EnumMap;
import java.util.Map;

/** 협업 캐릭터 이름·카피(specs/0016-협업-캐릭터.md 1장 명단 그대로) — 판정과 분리해 한곳에 모아둔다. */
final class CharacterCatalog {

  private record Entry(String name, String copy) {}

  private static final Map<CharacterId, Entry> ENTRIES = new EnumMap<>(CharacterId.class);

  static {
    ENTRIES.put(CharacterId.PROCRASTINATOR, new Entry("미루기 장인", "내일의 나를 믿는 타입"));
    ENTRIES.put(CharacterId.GHOST, new Entry("잠수 요정", "사라졌다 스윽 나타나는"));
    ENTRIES.put(CharacterId.LURKER, new Entry("눈팅 요정", "다 보고는 있어요"));
    ENTRIES.put(CharacterId.TURTLE, new Entry("마이 페이스", "급할 거 없잖아?"));
    ENTRIES.put(CharacterId.STEADY, new Entry("꾸준 적립가", "하루도 안 빼먹는"));
    ENTRIES.put(CharacterId.SPRINTER, new Entry("막판 스퍼트", "데드라인이 원동력"));
    ENTRIES.put(CharacterId.EARLYBIRD, new Entry("미리미리단", "제일 먼저 끝내고 여유"));
    ENTRIES.put(CharacterId.THE_J, new Entry("이 구역 J", "계획의 신, 완벽한 J"));
    ENTRIES.put(CharacterId.CHEERLEADER, new Entry("응원 요정", "팀 분위기 담당"));
    ENTRIES.put(CharacterId.WARMING_UP, new Entry("정체불명", "곧 정체가 드러나요"));
  }

  private CharacterCatalog() {}

  static String name(CharacterId id) {
    return ENTRIES.get(id).name();
  }

  static String copy(CharacterId id) {
    return ENTRIES.get(id).copy();
  }
}
