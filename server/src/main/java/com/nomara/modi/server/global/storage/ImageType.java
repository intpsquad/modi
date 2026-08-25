package com.nomara.modi.server.global.storage;

import java.util.Optional;

/**
 * 업로드된 바이트의 실제 이미지 형식. <b>파일명 확장자나 {@code Content-Type} 헤더를 믿지 않고 매직바이트로 판별한다</b> — FE가 multipart 파트에
 * 명시적 Content-Type 헤더를 붙이지 않기 때문이다(방 대표 이미지 업로드에서 확인).
 *
 * <p>원래 {@code RoomCoverImageService}의 private enum이었다. 피드백 스크린샷 업로드(#70)가 같은 판별을 필요로 해서 공용으로 뽑았다 —
 * 복붙하면 지원 형식이 두 곳에서 갈린다.
 */
public enum ImageType {
  JPEG("jpg", "image/jpeg"),
  PNG("png", "image/png"),
  WEBP("webp", "image/webp");

  private final String extension;
  private final String contentType;

  ImageType(String extension, String contentType) {
    this.extension = extension;
    this.contentType = contentType;
  }

  public String extension() {
    return extension;
  }

  public String contentType() {
    return contentType;
  }

  public static Optional<ImageType> sniff(byte[] bytes) {
    if (startsWith(bytes, 0xFF, 0xD8, 0xFF)) {
      return Optional.of(JPEG);
    }
    if (startsWith(bytes, 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)) {
      return Optional.of(PNG);
    }
    if (bytes.length >= 12
        && startsWith(bytes, 'R', 'I', 'F', 'F')
        && bytes[8] == 'W'
        && bytes[9] == 'E'
        && bytes[10] == 'B'
        && bytes[11] == 'P') {
      return Optional.of(WEBP);
    }
    return Optional.empty();
  }

  private static boolean startsWith(byte[] bytes, int... signature) {
    if (bytes.length < signature.length) {
      return false;
    }
    for (int i = 0; i < signature.length; i++) {
      if ((bytes[i] & 0xFF) != signature[i]) {
        return false;
      }
    }
    return true;
  }
}
