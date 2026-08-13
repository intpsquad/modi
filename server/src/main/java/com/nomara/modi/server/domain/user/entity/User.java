package com.nomara.modi.server.domain.user.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

/** id = Firebase Auth UID. */
@Entity
@Table(name = "users")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class User {

  @Id
  @Column(length = 128)
  private String id;

  @Column(nullable = false)
  private String nickname;

  private String profileImage;

  private String fcmToken;

  /**
   * {@code @CreationTimestamp}를 안 쓰고 생성자에서 직접 채운다. {@code id}가 {@code @GeneratedValue} 없는 자연키
   * (Firebase UID)라 {@code JpaRepository.save()}가 매번 {@code merge()}로 처리되는데(Spring Data가 non-null
   * id를 "이미 존재"로 판단), {@code @CreationTimestamp}의 INSERT 시점 값 생성은 실제 flush(커밋 또는 다음 쿼리)까지 지연돼 같은
   * 트랜잭션 안에서 방금 만든 유저의 {@code createdAt}을 바로 읽으면 null이었다(2026-08-07 {@code
   * UserProfileResponse.createdAt} 추가 중 발견). 생성자에서 즉시 채우면 이 타이밍 문제 자체가 없어진다.
   */
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  /** 최초 가입 시점에만 기록 — 재로그인으로 덮어쓰지 않는다. 과거 유저는 카카오만 백필돼 있고 나머지는 null. */
  @Enumerated(EnumType.STRING)
  @Column(length = 20)
  private LoginProvider loginProvider;

  /**
   * V29(2026-08-12). loginProvider와 달리 **매 로그인마다 값이 오면 갱신**한다(계정 이메일이 바뀔 수 있어서) — 단 정보성 조회용 컬럼일 뿐,
   * 중복가입 판정·계정 병합에는 쓰지 않는다(specs/0007-온보딩.md, specs/OPEN.md 참고). Kakao는 Custom Token 경로라 Firebase
   * ID 토큰에 이메일이 안 실려 Kakao API 응답에서 직접 받아야 하고, 그마저 카카오 콘솔의 "이메일" 동의항목이 켜져 있어야 온다 — 둘 다 아니면 계속 null.
   */
  private String email;

  public User(String id, String nickname, String profileImage) {
    this(id, nickname, profileImage, null);
  }

  public User(String id, String nickname, String profileImage, LoginProvider loginProvider) {
    this.id = id;
    this.nickname = nickname;
    this.profileImage = profileImage;
    this.loginProvider = loginProvider;
    this.createdAt = Instant.now();
  }

  public void changeNickname(String nickname) {
    this.nickname = nickname;
  }

  public void changeProfileImage(String profileImage) {
    this.profileImage = profileImage;
  }

  public void updateFcmToken(String fcmToken) {
    this.fcmToken = fcmToken;
  }

  public void changeEmail(String email) {
    this.email = email;
  }
}
