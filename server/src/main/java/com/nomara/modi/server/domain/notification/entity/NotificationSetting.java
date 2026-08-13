package com.nomara.modi.server.domain.notification.entity;

import com.nomara.modi.server.domain.user.entity.User;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.MapsId;
import jakarta.persistence.OneToOne;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.Table;
import jakarta.persistence.Transient;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;
import org.springframework.data.domain.Persistable;

/**
 * 유저별 알림 설정. 투두 마감 알림은 없고, 일정 전날/디데이 알림은 별도 채널로 관리한다.
 *
 * <p>{@code @MapsId}로 PK를 {@link User}와 공유하는 탓에 ID가 생성 즉시 채워져, {@link Persistable}을 구현하지 않으면 Spring
 * Data JPA가 신규 저장을 merge로 오판해 {@code StaleObjectStateException}을 던진다(실측 확인, 2026-07-29 —
 * PokeService가 알림 설정을 처음으로 신규 저장하면서 발견).
 */
@Entity
@Table(name = "notification_settings")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class NotificationSetting implements Persistable<String> {

  @Id
  @Column(name = "user_id", length = 128)
  private String userId;

  @OneToOne(fetch = FetchType.LAZY)
  @MapsId
  @JoinColumn(name = "user_id")
  private User user;

  @Column(nullable = false)
  private boolean allEnabled;

  @Column(nullable = false)
  private boolean pokeEnabled;

  @Column(nullable = false)
  private boolean scheduleDayBeforeEnabled;

  @Column(nullable = false)
  private boolean scheduleDdayEnabled;

  @Column(nullable = false)
  private boolean roomMemberJoinedEnabled;

  @Column(nullable = false)
  private boolean roomMemberLeftEnabled;

  @Column(nullable = false)
  private boolean assignedTodoAddedEnabled;

  /**
   * 자료 분석이 끝났을 때 알릴지(2026-08-06, {@code V17}).
   *
   * <p>등록이 비동기가 되면서 "언제 끝났는지"를 알 방법이 앱을 다시 여는 것뿐이 됐다. 기본값이 {@code true} 인 이유는 그것이다 — 이 알림이 없으면 완료
   * 시점을 알 수 없으므로, 받기 싫은 사람이 끄는 쪽이 맞다.
   */
  @Column(nullable = false)
  private boolean archiveAnalysisDoneEnabled;

  @Transient private boolean isNew = true;

  public NotificationSetting(User user) {
    this.user = user;
    this.userId = user.getId();
    this.allEnabled = true;
    this.pokeEnabled = true;
    this.scheduleDayBeforeEnabled = true;
    this.scheduleDdayEnabled = true;
    this.roomMemberJoinedEnabled = true;
    this.roomMemberLeftEnabled = true;
    this.assignedTodoAddedEnabled = true;
    this.archiveAnalysisDoneEnabled = true;
  }

  public void updateSettings(boolean allEnabled, boolean pokeEnabled) {
    updateSettings(allEnabled, pokeEnabled, true, true, true, true, true, true);
  }

  public void updateSettings(
      boolean allEnabled,
      boolean pokeEnabled,
      boolean scheduleDayBeforeEnabled,
      boolean scheduleDdayEnabled,
      boolean roomMemberJoinedEnabled,
      boolean roomMemberLeftEnabled,
      boolean assignedTodoAddedEnabled,
      boolean archiveAnalysisDoneEnabled) {
    this.allEnabled = allEnabled;
    this.pokeEnabled = pokeEnabled;
    this.scheduleDayBeforeEnabled = scheduleDayBeforeEnabled;
    this.scheduleDdayEnabled = scheduleDdayEnabled;
    this.roomMemberJoinedEnabled = roomMemberJoinedEnabled;
    this.roomMemberLeftEnabled = roomMemberLeftEnabled;
    this.assignedTodoAddedEnabled = assignedTodoAddedEnabled;
    this.archiveAnalysisDoneEnabled = archiveAnalysisDoneEnabled;
  }

  @Override
  public String getId() {
    return userId;
  }

  @Override
  public boolean isNew() {
    return isNew;
  }

  @PostLoad
  @PostPersist
  void markNotNew() {
    this.isNew = false;
  }
}
