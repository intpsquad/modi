package com.nomara.modi.server.domain.todo.dto;

/**
 * AI 투두 추천 후보 (S-16-B). 앱은 이 중 원하는 것만 골라 기존 {@code POST /rooms/{roomId}/todos}로 생성한다 — 후보 채택 전용
 * 엔드포인트는 없다. 채택 시 담당자는 미지정으로 남는다(specs/full_spec.md S-16-B).
 *
 * @param category 기존 카테고리명이거나 AI가 새로 제안한 이름. 앱이 이름으로 매칭하고, 없으면 새로 만든다.
 * @param sourceItemId 후보의 근거가 된 아카이브 자료 id. 방에 자료가 하나도 없으면 null일 수 있다.
 */
public record TodoSuggestionCandidate(String title, String category, Long sourceItemId) {}
