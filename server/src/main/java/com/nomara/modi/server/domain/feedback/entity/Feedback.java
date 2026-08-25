package com.nomara.modi.server.domain.feedback.entity;

import com.nomara.modi.server.domain.user.entity.User;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.Instant;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

/**
 * 인앱 피드백(문의하기, #70). 저장이 진실이고 팀 알림 메일은 부가물이다 — 메일 발송이 실패해도 이 행은 남는다({@code FeedbackService} 참고).
 */
@Entity
@Table(name = "feedback")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Feedback {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  /** 제보자. <b>nullable</b>이다 — 탈퇴하면 FK가 {@code SET NULL}로 비우고 제보 본문은 남긴다(V30 마이그레이션의 근거 참고). */
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "user_id")
  private User user;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, length = 20)
  private FeedbackType type;

  @Column(nullable = false, columnDefinition = "text")
  private String content;

  /** 선택 입력 — 비어 있으면 답변을 보낼 수 없다(앱이 그 사실을 폼에서 안내한다). */
  @Column(name = "reply_email", length = 255)
  private String replyEmail;

  @Column(name = "app_version", length = 50)
  private String appVersion;

  @Column(name = "device_info", length = 200)
  private String deviceInfo;

  /** 스크린샷 오브젝트 키. 공개 URL이 아니다 — 버킷에서 공개로 열지 않는다(V30 근거 참고). */
  @Column(name = "image_key", length = 255)
  private String imageKey;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public Feedback(
      User user,
      FeedbackType type,
      String content,
      String replyEmail,
      String appVersion,
      String deviceInfo,
      String imageKey) {
    this.user = user;
    this.type = type;
    this.content = content;
    this.replyEmail = replyEmail;
    this.appVersion = appVersion;
    this.deviceInfo = deviceInfo;
    this.imageKey = imageKey;
  }

  /** 탈퇴 시 개인정보만 지운다 — 제보 본문은 남는다. FK {@code SET NULL}은 {@code user_id}만 비우기 때문에 필요하다. */
  public void clearReplyEmail() {
    this.replyEmail = null;
  }
}
