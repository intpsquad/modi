package com.nomara.modi.server.global.storage;

import java.time.Duration;

/**
 * S3 호환 오브젝트 스토리지 추상화(현재 구현: MinIO). 업로드는 presigned PUT으로 클라이언트가 직접 하고, 조회는 버킷을 공개 읽기로 열어둬 만료 없는 고정
 * URL을 쓴다(아바타처럼 자주·오래 노출되는 이미지에 presigned GET은 부적합).
 */
public interface ObjectStorage {

  String createPresignedUploadUrl(String objectKey, Duration expiry);

  /** 서버가 바이트를 직접 받아 올리는 업로드(예: 방 대표 이미지 multipart) — presigned PUT과 별도 경로. */
  void put(String objectKey, byte[] content, String contentType);

  String publicUrl(String objectKey);
}
