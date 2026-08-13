package com.nomara.modi.server.domain.notification.entity;

import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.global.notification.PushType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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
 * 알림 내역 한 건(specs/0017-알림-내역.md, S-41) — 발송 트리거 7종({@link PushType})이 개별 채널 게이트를 통과하는 순간 {@code
 * PushNotifier}가 기록한다. FCM 발송 성공 여부와 무관하게 기록한다 — "발송 대상이었다"는 사실 기록이지 "기기에 도착했다"는 기록이 아니다.
 *
 * <p>{@code title}/{@code body}는 발송 시점에 실제로 쓰인 문자열을 그대로 스냅샷 저장한다 — 나중에 문구가 바뀌어도 과거 기록은 그때 실제로 보낸
 * 문구를 유지해야 하므로, 구조화된 필드로 재구성하지 않는다.
 *
 * <p>append-only라 수정 메서드가 없다({@code UserActivity}와 같은 패턴). 읽음 처리는 이 엔티티가 아니라 리포지토리의 벌크 UPDATE로 한다
 * (전체 읽음 처리 한 번에 여러 행을 바꾸는 것이 목적이라 단건 더티체킹보다 명확하다).
 */
@Entity
@Table(name = "notifications")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Notification {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "user_id", nullable = false)
  private User user;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "room_id")
  private Room room;

  @Column(nullable = false, length = 32)
  private String type;

  @Column(nullable = false)
  private String title;

  @Column(nullable = false)
  private String body;

  private Instant readAt;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public Notification(User user, Room room, PushType type, String title, String body) {
    this.user = user;
    this.room = room;
    this.type = type.name();
    this.title = title;
    this.body = body;
  }
}
