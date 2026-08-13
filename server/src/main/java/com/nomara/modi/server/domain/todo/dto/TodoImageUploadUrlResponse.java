package com.nomara.modi.server.domain.todo.dto;

/**
 * {@link com.nomara.modi.server.domain.user.dto.ProfilePhotoUploadUrlResponse}와 같은 모양 — MinIO
 * presigned PUT 2단계 업로드.
 */
public record TodoImageUploadUrlResponse(String uploadUrl, String publicUrl) {}
