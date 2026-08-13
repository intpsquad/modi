package com.nomara.modi.server.domain.character.entity;

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
 * 접속·조회 로그 한 건(specs/0016-협업-캐릭터.md) — 협업 캐릭터 판정의 "활동성" 신호로 쓴다.
 *
 * <p>append-only라 수정 메서드가 없다({@code Activity}와 같은 패턴). 개인 행동 로그라 사용자가 탈퇴하면 CASCADE로 함께 지워진다(V21 주석
 * 참고, {@code activities.actor_user_id}의 SET NULL과 다른 이유는 그쪽이 방 전체가 보는 공유 콘텐츠라서다).
 */
@Entity
@Table(name = "user_activity")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class UserActivity {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "user_id", nullable = false)
  private User user;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "room_id")
  private Room room;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, length = 30)
  private UserActivityKind kind;

  /** 조회 대상 id(예: 자료 id, 투두 id) — 종류에 따라 의미가 다르고, 없을 수 있다. */
  private Long targetId;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public UserActivity(User user, Room room, UserActivityKind kind, Long targetId) {
    this.user = user;
    this.room = room;
    this.kind = kind;
    this.targetId = targetId;
  }
}
