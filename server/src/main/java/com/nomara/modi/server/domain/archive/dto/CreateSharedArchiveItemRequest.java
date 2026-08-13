package com.nomara.modi.server.domain.archive.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * S-25-D 외부 공유 등록(네이티브) — url/text 중 정확히 하나만 채워져야 한다(서비스에서 XOR 검증). S-25-C의 {@code
 * CreateArchiveItemRequest}와 달리 title을 사용자가 직접 입력/수정하므로 필수다.
 */
public record CreateSharedArchiveItemRequest(@NotBlank String title, String url, String text) {}
