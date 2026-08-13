package com.nomara.modi.server.global.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * 버킷 공개 읽기 정책 — <b>MinIO 를 안 띄운다</b>. 정책 JSON 문자열만 본다.
 *
 * <p><b>왜 이 테스트가 있는가</b>: 새 접두사에 이미지를 올리면서 정책에 안 넣으면 <b>업로드는 성공하고 앱에서만 403</b> 이 난다. 서버 로그도 조용하다 —
 * 서버는 자기 크리덴셜로 쓰는 것이라 성공하고, 읽는 것은 앱이기 때문이다. (인스타 썸네일)에서 실제로 이 함정에 빠졌다: {@code archive/} 를 안 넣어 DB
 * 에는 우리 URL 이 잘 들어갔는데 이미지만 안 떴다.
 */
class MinioConfigTest {

  private final String policy = MinioConfig.publicReadPolicy("modi");

  @Test
  void everyPrefixWeUploadImagesToIsPubliclyReadable() {
    // 이 넷이 지금 우리가 이미지를 올리는 전부다. 새로 생기면 여기와 정책에 함께 추가한다.
    assertThat(policy)
        .contains("arn:aws:s3:::modi/profile/*") // UserService — 프로필 사진
        .contains("arn:aws:s3:::modi/rooms/cover/*") // RoomCoverImageService — 방 대표 이미지
        // InstagramUrlCrawler(썸네일) + ArchiveItemService(폴더 이미지 업로드, archive/images/)
        .contains("arn:aws:s3:::modi/archive/*")
        .contains("arn:aws:s3:::modi/todos/*"); // TodoImageService — 투두 사진 첨부
  }

  @Test
  void theBucketIsNotOpenedWholesale() {
    // 접두사를 좁게 유지하는 것이 원래 설계다(2026-07-29 리뷰) — 버킷 전체를 열면
    // 앞으로 올릴 비공개 오브젝트까지 자동으로 공개된다.
    assertThat(policy)
        .doesNotContain("arn:aws:s3:::modi/*\"")
        .doesNotContain("arn:aws:s3:::modi/*]");
  }

  @Test
  void onlyReadsAreAllowed() {
    // 쓰기는 presigned PUT(또는 서버의 putObject)으로만 — 정책이 쓰기를 열면 누구나 덮어쓸 수 있다.
    assertThat(policy).contains("s3:GetObject");
    assertThat(policy).doesNotContain("s3:PutObject").doesNotContain("s3:DeleteObject");
  }

  @Test
  void theBucketNameIsSubstitutedEverywhere() {
    // `.formatted()` 인자 개수를 틀리면 %s 가 그대로 남아 정책이 조용히 아무것도 안 연다.
    assertThat(policy).doesNotContain("%s");
  }
}
