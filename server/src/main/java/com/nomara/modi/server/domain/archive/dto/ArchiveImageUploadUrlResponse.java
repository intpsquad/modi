package com.nomara.modi.server.domain.archive.dto;

/**
 * 폴더 직접 업로드 이미지 자료(V28)의 presigned PUT 2단계 업로드 — {@link
 * com.nomara.modi.server.domain.todo.dto.TodoImageUploadUrlResponse}와 같은 모양.
 */
public record ArchiveImageUploadUrlResponse(String uploadUrl, String publicUrl) {}
