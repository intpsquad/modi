package com.nomara.modi.server.domain.todo.entity;

import com.nomara.modi.server.domain.user.entity.User;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.MapsId;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

/** 담당자 복수 지원. 미지정 = 행 없음(스펙 S-17 미지정 배너). AI 추천 생성분은 미지정으로 시작. */
@Entity
@Table(name = "todo_assignees")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class TodoAssignee {

  @EmbeddedId private TodoAssigneeId id;

  @ManyToOne(fetch = FetchType.LAZY)
  @MapsId("todoId")
  @JoinColumn(name = "todo_id")
  private Todo todo;

  @ManyToOne(fetch = FetchType.LAZY)
  @MapsId("userId")
  @JoinColumn(name = "user_id")
  private User user;

  public TodoAssignee(Todo todo, User user) {
    this.todo = todo;
    this.user = user;
    this.id = new TodoAssigneeId(todo.getId(), user.getId());
  }
}
