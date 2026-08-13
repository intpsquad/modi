package com.nomara.modi.server.global.config;

import com.nomara.modi.server.global.storage.MinioObjectStorage;
import com.nomara.modi.server.global.storage.ObjectStorage;
import io.minio.BucketExistsArgs;
import io.minio.MakeBucketArgs;
import io.minio.MinioClient;
import io.minio.SetBucketPolicyArgs;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * minio.endpoint(= MINIO_ENDPOINT 환경변수)가 설정된 경우에만 {@link ObjectStorage} 빈을 만든다. FirebaseConfig와 동일한
 * 패턴 — 크리덴셜 없는 테스트/CI 환경에서는 이 빈이 생성되지 않아 부팅이 깨지지 않는다(대신 업로드 URL 발급 API는 503).
 */
@Configuration
public class MinioConfig {

  @Bean
  @ConditionalOnProperty(name = "minio.endpoint")
  public ObjectStorage objectStorage(
      @Value("${minio.endpoint}") String endpoint,
      @Value("${minio.access-key}") String accessKey,
      @Value("${minio.secret-key}") String secretKey,
      @Value("${minio.bucket}") String bucket,
      // 기기가 이미지를 받아갈 주소. **기본값은 접속 주소와 같다** — 운영에서는 그게 맞다.
      // 로컬에서만 갈린다: 서버는 localhost:9000, 안드로이드 에뮬레이터는 10.0.2.2:9000.
      // 자세한 이유는 MinioObjectStorage 생성자 주석.
      @Value("${minio.public-base-url:${minio.endpoint}}") String publicBaseUrl)
      throws Exception {
    MinioClient minioClient =
        MinioClient.builder().endpoint(endpoint).credentials(accessKey, secretKey).build();

    if (!minioClient.bucketExists(BucketExistsArgs.builder().bucket(bucket).build())) {
      minioClient.makeBucket(MakeBucketArgs.builder().bucket(bucket).build());
    }
    // 아바타처럼 자주·오래 노출되는 이미지는 presigned GET을 계속 재발급하기 곤란해 공개 읽기로 연다.
    // 버킷 전체가 아니라 profile/ 접두사만 공개 범위로 좁힌다(리뷰 반영, 2026-07-29) — 나중에 이 버킷을
    // 방 커버이미지·아카이브 썸네일 등이 재사용할 때 그쪽 접두사까지 자동으로 공개되지 않도록.
    // (쓰기는 여전히 presigned PUT으로만 가능 — 이 정책은 읽기(s3:GetObject)만 허용).
    // rooms/cover/ 는 (방 대표 이미지)에서 같은 이유로 추가 — 앱이 Image.network로
    // 바로 로드해야 해서 여기도 공개 읽기가 필요하다(쓰기는 서버가 받은 바이트를 putObject로 직접 씀).
    // archive/ 는 (인스타 썸네일)에서 추가. **위 주석이 예고한 그 경우다** —
    // 접두사를 안 넣어 업로드는 되는데 앱에서 403이 났다(실기기 확인 전에 잡았다).
    minioClient.setBucketPolicy(
        SetBucketPolicyArgs.builder().bucket(bucket).config(publicReadPolicy(bucket)).build());

    return new MinioObjectStorage(minioClient, publicBaseUrl, bucket);
  }

  /**
   * 공개 읽기를 허용할 접두사 목록. <b>새 접두사에 이미지를 올릴 때 여기 추가하지 않으면 업로드는 성공하고 앱에서만 403이 난다</b> — 조용해서 놓치기 쉽다(에서
   * 실제로 놓쳤다). {@code MinioConfigTest} 가 목록을 고정한다.
   *
   * <p>{@code todos/} 는 2026-08-09 투두 사진 첨부(docs/backend/todo-image-archive-handoff.md)에서 추가 — 같은
   * 함정을 되풀이하지 않으려고 업로드 URL 발급 코드와 이 정책을 같은 커밋에 넣는다.
   */
  static String publicReadPolicy(String bucket) {
    return """
        {
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {"AWS": ["*"]},
              "Action": ["s3:GetObject"],
              "Resource": [
                "arn:aws:s3:::%s/profile/*",
                "arn:aws:s3:::%s/rooms/cover/*",
                "arn:aws:s3:::%s/archive/*",
                "arn:aws:s3:::%s/todos/*"
              ]
            }
          ]
        }
        """
        .formatted(bucket, bucket, bucket, bucket);
  }
}
