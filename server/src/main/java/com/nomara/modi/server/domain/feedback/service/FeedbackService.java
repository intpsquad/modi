package com.nomara.modi.server.domain.feedback.service;

import com.nomara.modi.server.domain.auth.client.EmailAttachment;
import com.nomara.modi.server.domain.feedback.dto.FeedbackResponse;
import com.nomara.modi.server.domain.feedback.entity.Feedback;
import com.nomara.modi.server.domain.feedback.entity.FeedbackType;
import com.nomara.modi.server.domain.feedback.repository.FeedbackRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.BadRequestException;
import com.nomara.modi.server.global.exception.ServiceUnavailableException;
import com.nomara.modi.server.global.storage.ImageType;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.io.IOException;
import java.util.Optional;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

/** 인앱 피드백 제출(#70, specs/0012-설정.md). */
@Service
public class FeedbackService {

  private static final Logger log = LoggerFactory.getLogger(FeedbackService.class);

  /** 방 대표 이미지와 같은 상한 — 두 곳이 다르면 "왜 여기선 되는데 저기선 안 되나"가 된다. */
  private static final long MAX_IMAGE_SIZE_BYTES = 5L * 1024 * 1024;

  private static final int MAX_CONTENT_LENGTH = 2000;

  private final FeedbackRepository feedbackRepository;
  private final UserRepository userRepository;
  private final FeedbackNotifier notifier;
  private final Optional<ObjectStorage> objectStorage;

  public FeedbackService(
      FeedbackRepository feedbackRepository,
      UserRepository userRepository,
      FeedbackNotifier notifier,
      Optional<ObjectStorage> objectStorage) {
    this.feedbackRepository = feedbackRepository;
    this.userRepository = userRepository;
    this.notifier = notifier;
    this.objectStorage = objectStorage;
  }

  /**
   * <b>{@code @Transactional}을 일부러 붙이지 않았다.</b> 쓰기는 {@code save} 한 번뿐이라 그것만으로 원자적이고, 트랜잭션으로 감싸면 아래
   * 알림 메일의 SMTP I/O가 DB 커넥션을 쥔 채 흘러간다.
   */
  public FeedbackResponse submit(
      String uid,
      FeedbackType type,
      String rawContent,
      String rawReplyEmail,
      String appVersion,
      String deviceInfo,
      MultipartFile image) {
    String content = requireContent(rawContent);
    // 알림 메일에 첨부하려면 바이트가 필요하다 — 스크린샷은 비공개라 링크를 대신 보낼 수 없다.
    byte[] imageBytes = readImageIfPresent(image);
    StoredImage stored = storeImageIfPresent(imageBytes);

    // 쓰기 API를 한 번도 안 태운 유저는 User 행이 아직 없을 수 있다(UserService.withdrawAppData의
    // 같은 주석 참고). 그때 제출을 실패시키는 건 과하다 — user_id는 nullable이므로 익명으로 남긴다.
    User user = userRepository.findById(uid).orElse(null);

    Feedback saved =
        feedbackRepository.save(
            new Feedback(
                user,
                type,
                content,
                blankToNull(rawReplyEmail),
                blankToNull(appVersion),
                blankToNull(deviceInfo),
                stored == null ? null : stored.objectKey()));

    // 🔴 저장이 먼저, 알림은 나중, 실패는 삼킨다. EmailVerificationService는 **반대 순서**로
    // 발송을 먼저 하는데(발송이 실패했는데 인증코드가 커밋되면 사용자가 재시도조차 못 한다),
    // 피드백은 반대다 — 제출을 잃는 것이 최악이고 메일은 팀에게 알리는 부가물일 뿐이다.
    try {
      notifier.notifySubmitted(saved, stored == null ? null : stored.toAttachment());
    } catch (Exception e) {
      log.warn("피드백 알림 메일 실패: id={}", saved.getId(), e);
    }
    return FeedbackResponse.of(saved);
  }

  private String requireContent(String rawContent) {
    String content = rawContent == null ? "" : rawContent.trim();
    if (content.isEmpty()) {
      throw new BadRequestException("문의 내용을 입력해 주세요");
    }
    if (content.length() > MAX_CONTENT_LENGTH) {
      throw new BadRequestException("문의 내용은 " + MAX_CONTENT_LENGTH + "자를 넘을 수 없어요");
    }
    return content;
  }

  private byte[] readImageIfPresent(MultipartFile image) {
    if (image == null || image.isEmpty()) {
      return null;
    }
    if (image.getSize() > MAX_IMAGE_SIZE_BYTES) {
      throw new BadRequestException("이미지 용량은 5MB를 넘을 수 없어요");
    }
    try {
      return image.getBytes();
    } catch (IOException e) {
      throw new BadRequestException("이미지 파일을 읽을 수 없어요");
    }
  }

  /**
   * 스크린샷은 <b>비공개</b>로 저장한다 — {@code MinioConfig}의 버킷 정책은 {@code rooms/cover/*}만 공개로 열어두고 {@code
   * feedback/*}은 기본값(비공개)이다. 사용자 화면 캡처에는 개인정보가 담길 수 있어 URL을 아는 사람이 볼 수 있게 두지 않는다. 그래서 공개 URL이 아니라
   * 오브젝트 키를 남기고, 팀에게는 메일 첨부로 보낸다.
   *
   * <p>스토리지 미설정 환경에서 이미지가 붙어 오면 {@code 503}이다 — 이미지를 조용히 버리고 저장을 성공시키면 사용자는 스크린샷이 전달됐다고 믿는다(방 대표
   * 이미지와 같은 판단).
   */
  private StoredImage storeImageIfPresent(byte[] content) {
    if (content == null) {
      return null;
    }
    ObjectStorage storage =
        objectStorage.orElseThrow(() -> new ServiceUnavailableException("이미지 업로드가 지금은 지원되지 않아요"));
    ImageType imageType =
        ImageType.sniff(content).orElseThrow(() -> new BadRequestException("지원하지 않는 이미지 형식이에요"));
    String objectKey = "feedback/" + UUID.randomUUID() + "." + imageType.extension();
    storage.put(objectKey, content, imageType.contentType());
    return new StoredImage(objectKey, content, imageType);
  }

  /** 저장한 스크린샷 — 키는 DB에, 바이트는 알림 메일 첨부에 쓴다. */
  private record StoredImage(String objectKey, byte[] content, ImageType imageType) {
    EmailAttachment toAttachment() {
      // 파일명은 오브젝트 키의 마지막 조각 — 팀이 메일과 스토리지를 대조할 수 있다.
      String filename = objectKey.substring(objectKey.lastIndexOf('/') + 1);
      return new EmailAttachment(filename, content, imageType.contentType());
    }
  }

  private static String blankToNull(String value) {
    if (value == null) {
      return null;
    }
    String trimmed = value.trim();
    return trimmed.isEmpty() ? null : trimmed;
  }
}
