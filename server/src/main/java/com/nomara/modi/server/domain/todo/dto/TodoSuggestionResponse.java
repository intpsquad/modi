package com.nomara.modi.server.domain.todo.dto;

import java.util.List;

/** S-16-B 추천 응답. 후보가 하나도 없으면 빈 목록 — 에러가 아니다(앱은 빈 상태 문구를 띄운다). */
public record TodoSuggestionResponse(List<TodoSuggestionCandidate> candidates) {}
