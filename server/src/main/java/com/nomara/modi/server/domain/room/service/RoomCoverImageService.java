package com.nomara.modi.server.domain.room.service;

import com.nomara.modi.server.domain.room.dto.CoverImageResponse;
import com.nomara.modi.server.global.exception.BadRequestException;
import com.nomara.modi.server.global.exception.ServiceUnavailableException;
import com.nomara.modi.server.global.storage.ImageType;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.io.IOException;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

/**
 * — 방 대표 이미지 업로드(`docs/api/room-cover-image.md`). 방 생성 전에도 호출되므로 roomId에 묶이지 않는 범용 업로드다(프로필 사진처럼
 * 유저당 고정 키가 아니라 매 업로드마다 새 오브젝트).
 */
@Service
public class RoomCoverImageService {

  private static final long MAX_FILE_SIZE_BYTES = 5L * 1024 * 1024;

  private final Optional<ObjectStorage> objectStorage;

  public RoomCoverImageService(Optional<ObjectStorage> objectStorage) {
    this.objectStorage = objectStorage;
  }

  public CoverImageResponse upload(MultipartFile image) {
    ObjectStorage storage =
        objectStorage.orElseThrow(() -> new ServiceUnavailableException("이미지 업로드가 지금은 지원되지 않아요"));

    if (image.isEmpty()) {
      throw new BadRequestException("이미지 파일이 비어 있어요");
    }
    if (image.getSize() > MAX_FILE_SIZE_BYTES) {
      throw new BadRequestException("이미지 용량은 5MB를 넘을 수 없어요");
    }

    byte[] content;
    try {
      content = image.getBytes();
    } catch (IOException e) {
      throw new BadRequestException("이미지 파일을 읽을 수 없어요");
    }

    // FE가 명시적 Content-Type 파트 헤더를 붙이지 않으므로 getContentType()/파일명 확장자는 신뢰하지
    // 않고 매직바이트로 실제 이미지 형식을 판별한다.
    ImageType imageType =
        ImageType.sniff(content).orElseThrow(() -> new BadRequestException("지원하지 않는 이미지 형식이에요"));

    String objectKey = "rooms/cover/" + UUID.randomUUID() + "." + imageType.extension();
    storage.put(objectKey, content, imageType.contentType());
    return new CoverImageResponse(storage.publicUrl(objectKey));
  }
}
