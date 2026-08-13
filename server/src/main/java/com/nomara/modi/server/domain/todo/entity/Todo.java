package com.nomara.modi.server.domain.todo.entity;

import com.nomara.modi.server.domain.category.entity.Category;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.user.entity.User;
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
import java.time.LocalDate;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

/**
 * category null = 기타 투두.
 *
 * <p>2026-08-07 롤백: 미리 알림형 메타데이터 중 위치·중요표시·사진 필드는 제거했다. {@code due_date}만 남긴 이유는 협업 캐릭터가 마감 준수율을
 * 계산하는 데 쓰기 때문이다(CharacterService, specs/0006-투두-탭.md). 걷어낸 컬럼 중 {@code location}/{@code flagged}와
 * {@code todo_tags} 테이블은 V16에 그대로 남아 있으나 여전히 매핑하지 않는다 — Flyway 과거 파일은 되돌리지 않는다는 규칙과 기존 데이터 보존 때문이다.
 *
 * <p><b>{@code image_url}은 2026-08-09 다시 매핑한다</b> — 투두 사진 첨부 → 모아보기 "이미지" 탭 기획
 * (docs/backend/todo-image-archive-handoff.md). {@code image_pinned}·{@code image_attached_at}는 V25
 * 신규. 투두 1개당 사진은 최대 1장(앱도 1장만 지원)이라 별도 테이블 없이 컬럼으로 둔다.
 *
 * <p><b>{@code important}도 2026-08-09 복원하지만 {@code flagged}(V16)를 재활용한 것이 아니라 새 컬럼 ({@code
 * V26})이다</b> — {@code flagged}는 옛 인라인 작성기 전용 의미로 죽어 있어 재활용할 근거가 없다.
 */
@Entity
@Table(name = "todos")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class Todo {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "room_id", nullable = false)
  private Room room;

  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "category_id")
  private Category category;

  @Column(nullable = false)
  private String title;

  @Column(columnDefinition = "TEXT")
  private String detail;

  private LocalDate dueDate;

  @Column(nullable = false)
  private boolean completed;

  private Instant completedAt;

  @Column(nullable = false)
  private int position;

  @Column(length = 1024)
  private String imageUrl;

  @Column(nullable = false)
  private boolean imagePinned;

  /** 사진을 (재)첨부한 시각 — 모아보기 "이미지" 탭 정렬 기준(핀 우선 → 이 값 최신순). 사진이 없으면 null. */
  private Instant imageAttachedAt;

  @Column(nullable = false)
  private boolean important;

  /**
   * 작성자(2026-08-06, 홈 활동 피드 TODO_ADDED 이벤트용). 투두는 방 전체가 보는 공유 콘텐츠라 작성자가 탈퇴해도 투두는 남고 작성자만 {@code
   * null}이 된다({@code archive_items.created_by}와 같은 근거, {@code
   * V19__add_created_by_to_todos_and_schedules.sql}). 기존 생성자를 그대로 두고 오버로드를 추가한 이유는 이 필드를 안 쓰는 기존
   * 호출부(테스트 다수)가 32곳이라, 시그니처를 바꾸면 전부 고쳐야 하기 때문이다.
   */
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "created_by")
  private User createdBy;

  @CreationTimestamp
  @Column(nullable = false, updatable = false)
  private Instant createdAt;

  public Todo(Room room, Category category, String title, String detail) {
    this.room = room;
    this.category = category;
    this.title = title;
    this.detail = detail;
    this.completed = false;
  }

  public Todo(Room room, Category category, String title, String detail, User createdBy) {
    this(room, category, title, detail);
    this.createdBy = createdBy;
  }

  public void complete() {
    this.completed = true;
    this.completedAt = Instant.now();
  }

  public void reopen() {
    this.completed = false;
    this.completedAt = null;
  }

  public void rename(String title) {
    this.title = title;
  }

  public void updateDetail(String detail) {
    this.detail = detail;
  }

  public void updateDueDate(LocalDate dueDate) {
    this.dueDate = dueDate;
  }

  public void moveToCategory(Category category) {
    this.category = category;
  }

  public void moveTo(int position) {
    this.position = position;
  }

  /** 사진 첨부/재첨부 — 재첨부 시 첨부 시각을 갱신해 "이미지" 탭에서 다시 최신으로 올라온다. 핀 상태는 유지한다. */
  public void attachImage(String imageUrl) {
    this.imageUrl = imageUrl;
    this.imageAttachedAt = Instant.now();
  }

  /** 사진 해제 — 수정 요청에 {@code imageUrl}이 없으면 호출된다({@code dueDate}와 같은 전체 교체 규칙). */
  public void detachImage() {
    this.imageUrl = null;
    this.imageAttachedAt = null;
    this.imagePinned = false;
  }

  public void setImagePinned(boolean imagePinned) {
    this.imagePinned = imagePinned;
  }

  public void setImportant(boolean important) {
    this.important = important;
  }
}
