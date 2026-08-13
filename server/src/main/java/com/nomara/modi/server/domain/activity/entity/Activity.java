package com.nomara.modi.server.domain.activity.entity;

import com.nomara.modi.server.domain.room.entity.Room;
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
 * 홈 활동 피드 이벤트 한 건(docs/backend/home-activity-feed.md). 적재형 이벤트만 이 테이블에 저장된다 — 파생형은 {@code
 * ActivityService}가 조회 시점에 계산해 응답에서만 합류하고 여기 남지 않는다.
 *
 * <p>append-only라 수정 메서드가 없다 — 잘못 남긴 행은 지우는 것 말고 고칠 방법이 없고, 그럴 일이 생기면 그때 판단한다.
 */
@Entity
@Table(name = "activities")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Activity {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "room_id", nullable = false)
  private Room room;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, length = 30)
  private ActivityType type;

  /** 탈퇴한 유저의 과거 활동도 행은 남고 여기만 {@code null}이 된다(V20 주석 참고). */
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "actor_user_id")
  private User actorUser;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "target_user_id")
  private User targetUser;

  private String targetName;

  private Integer count;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public Activity(
      Room room,
      ActivityType type,
      User actorUser,
      User targetUser,
      String targetName,
      Integer count) {
    this.room = room;
    this.type = type;
    this.actorUser = actorUser;
    this.targetUser = targetUser;
    this.targetName = targetName;
    this.count = count;
  }
}
