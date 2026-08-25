package com.nomara.modi.server.domain.feedback.dto;

import com.nomara.modi.server.domain.feedback.entity.Feedback;
import java.time.Instant;

/** 제출 결과. 본문을 되돌려주지 않는다 — 앱은 방금 보낸 값을 이미 알고 있고, 조회 화면도 없다(쓰지 않을 데이터를 응답에 담지 않는다). */
public record FeedbackResponse(Long id, Instant createdAt) {

  public static FeedbackResponse of(Feedback feedback) {
    return new FeedbackResponse(feedback.getId(), feedback.getCreatedAt());
  }
}
