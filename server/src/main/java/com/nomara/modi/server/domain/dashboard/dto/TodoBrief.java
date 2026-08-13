package com.nomara.modi.server.domain.dashboard.dto;

/** 내 담당 미완료 투두만 담는다(specs/0005-홈-대시보드.md 오늘투두 규칙 — 방 전체 보충 없음). */
public record TodoBrief(Long id, String title, boolean completed) {}
