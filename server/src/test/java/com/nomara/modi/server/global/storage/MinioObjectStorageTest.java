package com.nomara.modi.server.global.storage;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * 공개 URL 조립 — <b>MinIO 를 안 띄운다</b>. {@code MinioClient} 를 안 쓰는 메서드만 본다.
 *
 * <p><b>왜 접속 주소와 공개 주소를 나눴는가</b>: 원래 하나를 양쪽에 썼는데 로컬에서 갈린다 — 서버(호스트)는 {@code localhost:9000} 으로 붙지만
 * 안드로이드 에뮬레이터에서 {@code localhost} 는 <b>에뮬레이터 자신</b>이라 못 닿는다. 그래서 인스타 썸네일이 <b>조용히</b> 안 떴다: 다운로드도
 * 업로드도 DB 저장도 전부 성공해서 로그에 아무 흔적이 없었다.
 */
class MinioObjectStorageTest {

  private static MinioObjectStorage storage(String publicBaseUrl) {
    // MinioClient 는 publicUrl 경로에서 안 쓰인다 — null 로 둬야 "네트워크를 안 탄다"가 강제된다.
    return new MinioObjectStorage(null, publicBaseUrl, "modi");
  }

  @Test
  void thePublicUrlUsesThePublicBaseNotTheConnectEndpoint() {
    // 로컬 개발 조합: 서버는 localhost 로 붙고, 기기에는 10.0.2.2 를 준다.
    assertThat(storage("http://10.0.2.2:9000").publicUrl("archive/instagram/x.jpg"))
        .isEqualTo("http://10.0.2.2:9000/modi/archive/instagram/x.jpg");
  }

  @Test
  void aTrailingSlashDoesNotDoubleUp() {
    assertThat(storage("http://minio.example.com/").publicUrl("profile/abc"))
        .isEqualTo("http://minio.example.com/modi/profile/abc");
  }

  @Test
  void theBucketIsAlwaysInThePath() {
    // 버킷을 빠뜨리면 MinIO 가 404 를 준다 — 그것도 앱에서만 보인다.
    assertThat(storage("https://s3.example.com").publicUrl("rooms/cover/1.png"))
        .isEqualTo("https://s3.example.com/modi/rooms/cover/1.png");
  }
}
