package com.nomara.modi.server.domain.archive.dto;

/** 링크 편집(S-25-B, 2026-08-06) — 링크형 자료만 대상이다. 새 URL로 비동기 재분석을 다시 돈다. */
public record UpdateItemUrlRequest(String url) {}
