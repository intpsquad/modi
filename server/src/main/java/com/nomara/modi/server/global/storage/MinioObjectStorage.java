package com.nomara.modi.server.global.storage;

import io.minio.GetPresignedObjectUrlArgs;
import io.minio.MinioClient;
import io.minio.PutObjectArgs;
import io.minio.http.Method;
import java.io.ByteArrayInputStream;
import java.time.Duration;

public class MinioObjectStorage implements ObjectStorage {

  private final MinioClient minioClient;
  private final String publicBaseUrl;
  private final String bucket;

  /**
   * @param publicBaseUrl <b>기기가 이미지를 받아갈 주소</b>. 서버가 MinIO 에 접속하는 주소({@code minio.endpoint})와 <b>다를
   *     수 있다.</b>
   *     <p>원래는 접속 주소 하나를 양쪽에 썼는데, 로컬에서 그 둘이 갈린다 — 서버(호스트)는 {@code localhost:9000} 으로 붙지만 안드로이드
   *     에뮬레이터에서 {@code localhost} 는 <b>에뮬레이터 자신</b>이라 못 닿는다({@code API_BASE_URL} 이 {@code
   *     10.0.2.2:8080} 인 것과 같은 이유). 그래서 이미지가 조용히 안 뜬다 — 업로드도 DB 저장도 성공해서 로그에 아무것도 안 남는다(에서 실제로
   *     겪었다).
   *     <p>운영에서는 {@code MINIO_ENDPOINT} 가 곧 공개 주소라 안 나눠도 되고, 기본값이 그렇게 동작한다.
   */
  public MinioObjectStorage(MinioClient minioClient, String publicBaseUrl, String bucket) {
    this.minioClient = minioClient;
    this.publicBaseUrl = publicBaseUrl;
    this.bucket = bucket;
  }

  @Override
  public String createPresignedUploadUrl(String objectKey, Duration expiry) {
    try {
      return minioClient.getPresignedObjectUrl(
          GetPresignedObjectUrlArgs.builder()
              .method(Method.PUT)
              .bucket(bucket)
              .object(objectKey)
              .expiry((int) expiry.toSeconds())
              .build());
    } catch (Exception e) {
      throw new IllegalStateException("presigned URL 발급 실패: " + objectKey, e);
    }
  }

  @Override
  public void put(String objectKey, byte[] content, String contentType) {
    try {
      minioClient.putObject(
          PutObjectArgs.builder().bucket(bucket).object(objectKey).contentType(contentType).stream(
                  new ByteArrayInputStream(content), content.length, -1)
              .build());
    } catch (Exception e) {
      throw new IllegalStateException("오브젝트 업로드 실패: " + objectKey, e);
    }
  }

  @Override
  public String publicUrl(String objectKey) {
    String base =
        publicBaseUrl.endsWith("/")
            ? publicBaseUrl.substring(0, publicBaseUrl.length() - 1)
            : publicBaseUrl;
    return base + "/" + bucket + "/" + objectKey;
  }
}
