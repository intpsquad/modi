package com.nomara.modi.server.domain.archive.dto;

/** 메모 편집(S-25-B, 2026-08-06). {@code null}/빈 값이면 메모를 지운다 — {@code @NotBlank}를 일부러 안 붙인다. */
public record UpdateItemMemoRequest(String memo) {}
