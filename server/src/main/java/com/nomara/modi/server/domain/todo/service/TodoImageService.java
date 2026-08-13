package com.nomara.modi.server.domain.todo.service;

import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.todo.dto.TodoImageResponse;
import com.nomara.modi.server.domain.todo.dto.TodoImageUploadUrlResponse;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.entity.TodoAssignee;
import com.nomara.modi.server.domain.todo.exception.TodoNotFoundException;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.global.exception.ServiceUnavailableException;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.time.Duration;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 투두 사진 첨부 업로드 URL 발급 + 모아보기 "이미지" 탭 피드/핀(2026-08-09, docs/backend/todo-image-archive-handoff.md).
 * 사진 자체(첨부·해제)는 {@link TodoService}가 투두 생성/수정 경로에서 처리한다 — 이 서비스는 업로드 준비와 조회·핀만 맡는다.
 */
@Service
public class TodoImageService {

  private static final Duration UPLOAD_URL_EXPIRY = Duration.ofMinutes(5);

  private final TodoRepository todoRepository;
  private final TodoAssigneeRepository todoAssigneeRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final Optional<ObjectStorage> objectStorage;

  public TodoImageService(
      TodoRepository todoRepository,
      TodoAssigneeRepository todoAssigneeRepository,
      RoomMemberRepository roomMemberRepository,
      Optional<ObjectStorage> objectStorage) {
    this.todoRepository = todoRepository;
    this.todoAssigneeRepository = todoAssigneeRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.objectStorage = objectStorage;
  }

  /**
   * 투두가 생성되기 전에 사진부터 고르는 앱 흐름에 맞춰(사용자 확정, 2026-08-09) 투두 id 없이 발급한다 — 그래서 오브젝트 키에 방 id까지만 넣고 무작위
   * UUID로 충돌을 피한다({@code UserService.createProfilePhotoUploadUrl}과 달리 고정 키를 못 쓴다). 업로드만 하고 투두 생성을
   * 취소하면 고아 오브젝트가 남는데, 방 커버 이미지와 같은 트레이드오프라 별도 청소는 두지 않는다.
   */
  @Transactional(readOnly = true)
  public TodoImageUploadUrlResponse createUploadUrl(String uid, Long roomId) {
    requireMembership(uid, roomId);
    ObjectStorage storage =
        objectStorage.orElseThrow(() -> new ServiceUnavailableException("이미지 업로드가 지금은 지원되지 않아요"));
    String objectKey = "todos/" + roomId + "/" + UUID.randomUUID();
    return new TodoImageUploadUrlResponse(
        storage.createPresignedUploadUrl(objectKey, UPLOAD_URL_EXPIRY),
        storage.publicUrl(objectKey));
  }

  @Transactional(readOnly = true)
  public List<TodoImageResponse> listImages(String uid, Long roomId) {
    requireMembership(uid, roomId);
    List<Todo> todos = todoRepository.findImageTodosByRoomId(roomId);
    if (todos.isEmpty()) {
      return List.of();
    }
    Map<Long, User> representativeByTodoId = representativeAssignees(todos);
    return todos.stream()
        .map(todo -> TodoImageResponse.of(todo, representativeByTodoId.get(todo.getId())))
        .toList();
  }

  @Transactional
  public TodoImageResponse setPinned(String uid, Long roomId, Long todoId, boolean pinned) {
    requireMembership(uid, roomId);
    Todo todo = resolveImageTodo(roomId, todoId);
    todo.setImagePinned(pinned);
    Map<Long, User> representativeByTodoId = representativeAssignees(List.of(todo));
    return TodoImageResponse.of(todo, representativeByTodoId.get(todo.getId()));
  }

  /**
   * 담당자가 여럿이면 {@code userId} 오름차순 첫 번째를 대표로 뽑는다 — {@code todo_assignees}에 배정 순서를 기록하는 컬럼이 없어(복합
   * PK뿐) "첫 담당자"를 재현 가능하게 고를 다른 근거가 없다(제안 계약의 "첫 담당자 권장", 서버 판단으로 확정).
   */
  private Map<Long, User> representativeAssignees(List<Todo> todos) {
    List<Long> todoIds = todos.stream().map(Todo::getId).toList();
    Map<Long, User> representativeByTodoId = new HashMap<>();
    for (TodoAssignee ta : todoAssigneeRepository.findByTodoIdIn(todoIds)) {
      representativeByTodoId.merge(
          ta.getTodo().getId(),
          ta.getUser(),
          (current, candidate) ->
              current.getId().compareTo(candidate.getId()) <= 0 ? current : candidate);
    }
    return representativeByTodoId;
  }

  private Todo resolveImageTodo(Long roomId, Long todoId) {
    Todo todo = todoRepository.findById(todoId).orElseThrow(TodoNotFoundException::new);
    if (!todo.getRoom().getId().equals(roomId) || todo.getImageUrl() == null) {
      throw new TodoNotFoundException();
    }
    return todo;
  }

  private void requireMembership(String uid, Long roomId) {
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, uid))) {
      throw new NotRoomMemberException();
    }
  }
}
