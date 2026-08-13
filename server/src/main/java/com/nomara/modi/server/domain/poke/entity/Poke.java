package com.nomara.modi.server.domain.poke.entity;

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

/** 콕찌르기. 알림 트리거. */
@Entity
@Table(name = "pokes")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Poke {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "room_id", nullable = false)
  private Room room;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "from_user", nullable = false)
  private User fromUser;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "to_user", nullable = false)
  private User toUser;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, length = 10)
  private PokeType type;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public Poke(Room room, User fromUser, User toUser, PokeType type) {
    this.room = room;
    this.fromUser = fromUser;
    this.toUser = toUser;
    this.type = type;
  }
}
