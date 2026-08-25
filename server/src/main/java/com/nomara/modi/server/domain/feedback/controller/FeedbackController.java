package com.nomara.modi.server.domain.feedback.controller;

import com.nomara.modi.server.domain.feedback.dto.FeedbackResponse;
import com.nomara.modi.server.domain.feedback.entity.FeedbackType;
import com.nomara.modi.server.domain.feedback.service.FeedbackService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 인앱 문의하기(#70, specs/0012-설정.md). 이전에는 앱이 {@code mailto:} 딥링크로 OS 메일 앱을 열었고 서버에 기록이 없었다.
 *
 * <p><b>2단계 업로드가 아니라 단일 multipart</b>다 — 방 대표 이미지({@code POST /rooms/cover-image})는 URL을 먼저 받아 저장
 * 필드에 넣는 구조지만, 피드백 스크린샷은 비공개라 클라이언트에 돌려줄 공개 URL이 없다.
 */
@RestController
public class FeedbackController {

  private final FeedbackService feedbackService;

  public FeedbackController(FeedbackService feedbackService) {
    this.feedbackService = feedbackService;
  }

  @PostMapping(value = "/feedback", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  @ResponseStatus(HttpStatus.CREATED)
  public FeedbackResponse submit(
      HttpServletRequest request,
      @RequestParam("type") FeedbackType type,
      @RequestParam("content") String content,
      @RequestParam(value = "replyEmail", required = false) String replyEmail,
      @RequestParam(value = "appVersion", required = false) String appVersion,
      @RequestParam(value = "deviceInfo", required = false) String deviceInfo,
      @RequestPart(value = "image", required = false) MultipartFile image) {
    return feedbackService.submit(
        uid(request), type, content, replyEmail, appVersion, deviceInfo, image);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
