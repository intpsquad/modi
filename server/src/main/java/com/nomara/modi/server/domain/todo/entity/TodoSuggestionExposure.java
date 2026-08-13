package com.nomara.modi.server.domain.todo.entity;

import com.nomara.modi.server.domain.room.entity.Room;
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
 * AI 추천 후보를 한 번 노출했다는 기록. 다음 추천에서 같은 후보가 다시 나오지 않게 하는 것이 유일한 용도다.
 *
 * <p><b>⚠️ "사용자가 거절한 후보"가 아니다</b> — 앱에 거절 버튼이 없고 스펙이 요구하는 것은 "중복 후보 재노출 안 함"뿐이다(full_spec.md:130).
 * 채택하지 않고 시트를 닫은 후보도 전부 여기 들어간다. 거절로 읽으면 {@code rejected} 같은 플래그를 만들게 되는데 그것을 채울 사용자 입력 자체가 없다.
 *
 * <p>방 단위다. 방 멤버는 동일 권한이므로(루트 CLAUDE.md) 누가 추천을 눌렀는지는 남기지 않는다 — 한 사람이 본 후보를 다른 멤버에게 다시 보여줄 이유가 없다.
 *
 * <p>제목만 담는다. AI 서버 계약이 {@code excluded_todos: list[str]}이라 읽는 것이 제목뿐이다.
 */
@Entity
@Table(name = "todo_suggestion_exposures")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class TodoSuggestionExposure {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "room_id", nullable = false)
  private Room room;

  @Column(nullable = false)
  private String title;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public TodoSuggestionExposure(Room room, String title) {
    this.room = room;
    this.title = title;
  }
}
