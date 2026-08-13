package com.nomara.modi.server.domain.archive.dto;

/**
 * url/text/imageUrl 중 정확히 하나만 채워져야 한다 — 서비스에서 검증(어노테이션으로 XOR 표현 불가). {@code memo}는 어느 쪽이든 선택
 * 입력이다(2026-08-06 도입). {@code title}은 이미지 등록 전용 선택 입력이다(V28, 2026-08-09 후속 확정) — 링크/텍스트는 지금처럼 서버가
 * 자동으로 제목을 만든다.
 */
public record CreateArchiveItemRequest(
    String url, String text, String memo, String imageUrl, String title) {}
