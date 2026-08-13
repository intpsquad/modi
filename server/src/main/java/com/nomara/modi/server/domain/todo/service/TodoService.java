package com.nomara.modi.server.domain.todo.service;

import com.nomara.modi.server.domain.activity.entity.ActivityType;
import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.category.entity.Category;
import com.nomara.modi.server.domain.category.repository.CategoryRepository;
import com.nomara.modi.server.domain.character.entity.UserActivityKind;
import com.nomara.modi.server.domain.character.service.UserActivityRecorder;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.exception.RoomMemberNotFoundException;
import com.nomara.modi.server.domain.room.exception.RoomNotFoundException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.dto.AssigneeBrief;
import com.nomara.modi.server.domain.todo.dto.CreateTodoRequest;
import com.nomara.modi.server.domain.todo.dto.TodoBriefResponse;
import com.nomara.modi.server.domain.todo.dto.TodoResponse;
import com.nomara.modi.server.domain.todo.dto.UpdateTodoRequest;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.entity.TodoAssignee;
import com.nomara.modi.server.domain.todo.entity.TodoAssigneeId;
import com.nomara.modi.server.domain.todo.exception.NotTodoAssigneeException;
import com.nomara.modi.server.domain.todo.exception.TodoNotFoundException;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.BadRequestException;
import com.nomara.modi.server.global.notification.PushNotifier;
import com.nomara.modi.server.global.notification.PushType;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** specs/0006-투두-탭.md — 카테고리별/독립 투두 CRUD + 담당자 다대다. design.md §7 즉시 실행 원칙(완료 토글)도 포함. */
@Service
public class TodoService {

  private final TodoRepository todoRepository;
  private final TodoAssigneeRepository todoAssigneeRepository;
  private final CategoryRepository categoryRepository;
  private final RoomRepository roomRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final UserRepository userRepository;
  private final PushNotifier pushNotifier;
  private final ActivityService activityService;
  private final UserActivityRecorder userActivityRecorder;

  public TodoService(
      TodoRepository todoRepository,
      TodoAssigneeRepository todoAssigneeRepository,
      CategoryRepository categoryRepository,
      RoomRepository roomRepository,
      RoomMemberRepository roomMemberRepository,
      UserRepository userRepository,
      PushNotifier pushNotifier,
      ActivityService activityService,
      UserActivityRecorder userActivityRecorder) {
    this.todoRepository = todoRepository;
    this.todoAssigneeRepository = todoAssigneeRepository;
    this.categoryRepository = categoryRepository;
    this.activityService = activityService;
    this.userActivityRecorder = userActivityRecorder;
    this.roomRepository = roomRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.userRepository = userRepository;
    this.pushNotifier = pushNotifier;
  }

  @Transactional(readOnly = true)
  public List<TodoResponse> listTodos(String uid, Long roomId) {
    requireMembership(uid, roomId);
    List<Todo> todos = todoRepository.findByRoomIdOrderByPositionAscIdAsc(roomId);
    return toResponses(todos);
  }

  /** S-18 전체화면 상세 — specs/0006-투두-탭.md(2026-08-06 사용자 확정, 인라인 편집기 대체). */
  @Transactional(readOnly = true)
  public TodoResponse getTodo(String uid, Long roomId, Long todoId) {
    requireMembership(uid, roomId);
    Todo todo = resolveTodo(roomId, todoId);
    // 협업 캐릭터 활동성 신호(specs/0016) — 투두 상세 조회 로그.
    userActivityRecorder.record(uid, UserActivityKind.TODO_VIEW, todo.getRoom(), todoId);
    return toResponses(List.of(todo)).get(0);
  }

  /** specs/0011-멤버-투두-콕찌르기.md(S-30-M) — 조회 전용, 체크 토글 액션 없이 동일 {@link TodoResponse}를 재사용한다. */
  @Transactional(readOnly = true)
  public List<TodoResponse> listMemberTodos(String uid, Long roomId, String memberUserId) {
    requireMembership(uid, roomId);
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, memberUserId))) {
      throw new RoomMemberNotFoundException();
    }
    List<Todo> todos = todoAssigneeRepository.findTodosByRoomIdAndUserId(roomId, memberUserId);
    return toResponses(todos);
  }

  private List<TodoResponse> toResponses(List<Todo> todos) {
    if (todos.isEmpty()) {
      return List.of();
    }
    Map<Long, List<AssigneeBrief>> assigneesByTodoId = assigneesByTodoId(todos);
    return todos.stream()
        .map(todo -> TodoResponse.of(todo, assigneesByTodoId.getOrDefault(todo.getId(), List.of())))
        .toList();
  }

  private Map<Long, List<AssigneeBrief>> assigneesByTodoId(List<Todo> todos) {
    List<Long> todoIds = todos.stream().map(Todo::getId).toList();
    Map<Long, List<AssigneeBrief>> assigneesByTodoId = new HashMap<>();
    for (TodoAssignee ta : todoAssigneeRepository.findByTodoIdIn(todoIds)) {
      assigneesByTodoId
          .computeIfAbsent(ta.getTodo().getId(), key -> new ArrayList<>())
          .add(
              new AssigneeBrief(
                  ta.getUser().getId(),
                  ta.getUser().getNickname(),
                  ta.getUser().getProfileImage()));
    }
    return assigneesByTodoId;
  }

  @Transactional
  public TodoResponse createTodo(String uid, Long roomId, CreateTodoRequest request) {
    requireMembership(uid, roomId);
    Room room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
    Category category = resolveCategoryOrNull(roomId, request.categoryId());

    User creator = userRepository.getReferenceById(uid);
    Todo todo = new Todo(room, category, request.title(), request.detail(), creator);
    todo.updateDueDate(request.dueDate());
    applyImage(todo, request.imageUrl());
    todo.setImportant(request.important());
    todo.moveTo(nextPositionInCategory(roomId, request.categoryId()));
    todoRepository.save(todo);
    List<User> assignees = assignUsers(roomId, todo, request.assigneeUserIds());
    // 생성 시점엔 "기존 담당자"가 없으니 배정된 전원이 신규다 — 본인 배정만 알림에서 빠진다.
    notifyNewAssignees(room, todo, uid, assignees, Set.of());
    activityService.record(room, ActivityType.TODO_ADDED, creator, null, null, null);
    return TodoResponse.of(todo, toAssigneeBriefs(assignees));
  }

  @Transactional
  public TodoResponse updateTodo(String uid, Long roomId, Long todoId, UpdateTodoRequest request) {
    requireMembership(uid, roomId);
    Todo todo = resolveTodo(roomId, todoId);
    Category category = resolveCategoryOrNull(roomId, request.categoryId());

    Long previousCategoryId = todo.getCategory() != null ? todo.getCategory().getId() : null;
    todo.rename(request.title());
    todo.updateDetail(request.detail());
    todo.updateDueDate(request.dueDate());
    applyImage(todo, request.imageUrl());
    todo.setImportant(request.important());
    todo.moveToCategory(category);
    // 카테고리가 실제로 바뀔 때만 새 카테고리 목록 끝으로 position을 다시 매긴다 — 안 바뀌면 그대로 둔다.
    if (!Objects.equals(previousCategoryId, request.categoryId())) {
      todo.moveTo(nextPositionInCategory(roomId, request.categoryId()));
    }
    // 재배정 전에 기존 담당자를 스냅샷해둔다 — 그래야 재배정 후 "신규로 추가된" 담당자만 골라 알림을 보낼 수 있다
    // (담당자를 전부 지우고 새로 넣는 구조라 재배정 자체로는 신규/유지를 구분할 수 없다).
    Set<String> previousAssigneeIds =
        todoAssigneeRepository.findByTodoIdIn(List.of(todoId)).stream()
            .map(ta -> ta.getUser().getId())
            .collect(Collectors.toSet());
    todoAssigneeRepository.deleteByTodoId(todoId);
    List<User> assignees = assignUsers(roomId, todo, request.assigneeUserIds());
    notifyNewAssignees(todo.getRoom(), todo, uid, assignees, previousAssigneeIds);
    return TodoResponse.of(todo, toAssigneeBriefs(assignees));
  }

  /**
   * 드래그 순서변경(사용자 요청, 2026-08-04) — "내 투두"만 옮길 수 있다. "내 투두"는 **나에게 배정된 투두만** 뜻한다 — 담당자가 아예 없는("미지정")
   * 투두는 누구의 것도 아니라서 이 기능의 대상이 아니다. FR-39({@link #setCompleted})의 "미지정은 방 멤버 누구나" 예외를 여기서는 일부러 두지
   * 않는다 — 프론트의 "내 투두만" 화면 자체가 미지정 투두를 아예 보여주지 않아, 그 예외를 두면 화면에 안 보이는 항목을 서버가 "자격 있다"고 우기는 불일치가
   * 생긴다(2026-08-04 리뷰로 발견 — 처음엔 FR-39를 그대로 미러링했다가 이 불일치로 항상 400이 나는 버그가 있었다). 다른 사람 투두는 자리(position
   * 값)까지 그대로 둔다 — 자격 있는 항목들이 지금 차지한 position 슬롯에 새 순서를 그대로 끼워 넣을 뿐, 자격 없는 행은 쓰지 않는다.
   */
  @Transactional
  public List<TodoResponse> reorderMyTodos(
      String uid, Long roomId, Long categoryId, List<Long> todoIds) {
    requireMembership(uid, roomId);
    List<Todo> categoryTodos = todoRepository.findByRoomIdAndCategoryId(roomId, categoryId);

    List<Long> allIds = categoryTodos.stream().map(Todo::getId).toList();
    Set<Long> myTodoIds = new HashSet<>();
    for (TodoAssignee ta : todoAssigneeRepository.findByTodoIdIn(allIds)) {
      if (ta.getUser().getId().equals(uid)) {
        myTodoIds.add(ta.getTodo().getId());
      }
    }

    List<Todo> eligible =
        categoryTodos.stream().filter(t -> myTodoIds.contains(t.getId())).toList();
    Set<Long> eligibleIds = eligible.stream().map(Todo::getId).collect(Collectors.toSet());

    boolean sameSize = todoIds.size() == eligible.size();
    boolean noDuplicates = new HashSet<>(todoIds).size() == todoIds.size();
    boolean allEligible = eligibleIds.containsAll(todoIds);
    if (!sameSize || !noDuplicates || !allEligible) {
      throw new BadRequestException("순서 목록이 내가 옮길 수 있는 투두 구성과 일치하지 않아요");
    }

    // 자격 있는 항목들이 지금 차지한 position 값(오름차순)을 슬롯으로 재사용 — 자격 없는(남의/미지정) 투두는 안 건드린다.
    List<Integer> slots = eligible.stream().map(Todo::getPosition).sorted().toList();
    Map<Long, Todo> todoById = eligible.stream().collect(Collectors.toMap(Todo::getId, t -> t));
    Map<Long, Integer> targetPositionByTodoId = new HashMap<>();
    for (int i = 0; i < todoIds.size(); i++) {
      targetPositionByTodoId.put(todoIds.get(i), slots.get(i));
    }
    // id 오름차순으로 적용해, 담당자가 여럿인 투두를 두 사람이 동시에 반대 순서로 재배치할 때
    // 서로 다른 순서로 행을 잠가 교착(deadlock)하는 것을 방지한다(CategoryService.reorderCategories와 동일 패턴).
    eligible.stream()
        .sorted(Comparator.comparingLong(Todo::getId))
        .forEach(todo -> todo.moveTo(targetPositionByTodoId.get(todo.getId())));

    Map<Long, List<AssigneeBrief>> assigneesByTodoId = assigneesByTodoId(eligible);
    return todoIds.stream()
        .map(todoById::get)
        .map(todo -> TodoResponse.of(todo, assigneesByTodoId.getOrDefault(todo.getId(), List.of())))
        .toList();
  }

  /**
   * 사진 첨부 반영 — 전체 교체 방식이라({@code dueDate}와 같은 규칙) {@code imageUrl}이 비어 있으면 해제로 취급한다. 이미 첨부된 것과 같은
   * URL을 다시 보내도 재첨부로 처리해 "이미지" 탭 정렬 기준({@code imageAttachedAt})이 최신으로 갱신된다 — 호출부가 URL이 바뀌었는지 비교할
   * 이유를 없앤다.
   */
  private void applyImage(Todo todo, String imageUrl) {
    if (imageUrl == null || imageUrl.isBlank()) {
      todo.detachImage();
    } else {
      todo.attachImage(imageUrl);
    }
  }

  private int nextPositionInCategory(Long roomId, Long categoryId) {
    List<Todo> categoryTodos = todoRepository.findByRoomIdAndCategoryId(roomId, categoryId);
    return categoryTodos.isEmpty()
        ? 0
        : categoryTodos.get(categoryTodos.size() - 1).getPosition() + 1;
  }

  @Transactional
  public void deleteTodo(String uid, Long roomId, Long todoId) {
    requireMembership(uid, roomId);
    Todo todo = resolveTodo(roomId, todoId);
    // todo_assignees는 DB ON DELETE CASCADE로 자동 정리 — 별도 삭제 코드 불필요.
    todoRepository.delete(todo);
  }

  /**
   * specs/0006-투두-탭.md — 본인이 담당한 투두만 체크/해제 가능하다(FR-39). 담당자가 아예 없는 "미지정" 투두(AI추천 채택 시에만 발생)는 예외로 방
   * 멤버 누구나 체크 가능 — 미지정 처리 배너(S-17)가 담당자 지정을 유도하는 흐름과 별개로 완료 자체를 막을 이유는 없다는 판단(사용자 확정, 2026-07-29).
   */
  @Transactional
  public TodoBriefResponse setCompleted(String uid, Long roomId, Long todoId, boolean completed) {
    requireMembership(uid, roomId);
    Todo todo = resolveTodo(roomId, todoId);
    if (todoAssigneeRepository.existsByTodoId(todoId)
        && !todoAssigneeRepository.existsById(new TodoAssigneeId(todoId, uid))) {
      throw new NotTodoAssigneeException();
    }
    if (completed) {
      todo.complete();
      recordCompletionActivity(todo, uid);
    } else {
      todo.reopen();
    }
    return TodoBriefResponse.of(todo);
  }

  /**
   * 홈 활동 피드 TODO_COMPLETED + (담당 전체 완료 도달 시) TODO_ALL_DONE(2026-08-06,
   * docs/backend/home-activity-feed.md). 미지정 투두(담당자 없음)를 완료한 경우는 "담당 100%" 개념이 없어 TODO_ALL_DONE을 보지
   * 않는다.
   *
   * <p>담당자가 2명 이상(공동)이면 개인 완료 문구 대신 {@code TODO_COMPLETED_SHARED}를 남긴다(docs/backend/
   * live-banner-copy-handoff.md §2) — 단독(담당자 1명)·미지정(0명)은 현행 {@code TODO_COMPLETED} 그대로 유지.
   */
  private void recordCompletionActivity(Todo todo, String uid) {
    Room room = todo.getRoom();
    User actor = userRepository.getReferenceById(uid);
    List<User> assignees = todoAssigneeRepository.findAssigneeUsersByTodoId(todo.getId());
    if (assignees.size() >= 2) {
      User representative =
          assignees.stream()
              .min(
                  Comparator.comparingInt((User u) -> u.getNickname().length())
                      .thenComparing(User::getId))
              .orElseThrow();
      activityService.record(
          room,
          ActivityType.TODO_COMPLETED_SHARED,
          actor,
          null,
          representative.getNickname(),
          assignees.size());
    } else {
      activityService.record(room, ActivityType.TODO_COMPLETED, actor, null, null, 1);
    }
    if (!todoAssigneeRepository.existsById(new TodoAssigneeId(todo.getId(), uid))) {
      return;
    }
    List<Object[]> progress =
        todoAssigneeRepository.aggregateProgressByRoomIdAndUserId(room.getId(), uid);
    if (progress.isEmpty()) {
      return;
    }
    Object[] row = progress.get(0);
    long total = (Long) row[0];
    long done = row[1] == null ? 0 : (Long) row[1];
    if (total > 0 && total == done) {
      activityService.record(room, ActivityType.TODO_ALL_DONE, actor, null, null, null);
    }
  }

  private List<User> assignUsers(Long roomId, Todo todo, List<String> userIds) {
    if (userIds == null || userIds.isEmpty()) {
      return List.of();
    }
    List<User> result = new ArrayList<>();
    for (String userId : new LinkedHashSet<>(userIds)) {
      if (!roomMemberRepository.existsById(new RoomMemberId(roomId, userId))) {
        throw new BadRequestException("담당자는 방 멤버여야 해요");
      }
      User user =
          userRepository
              .findById(userId)
              .orElseThrow(() -> new BadRequestException("담당자를 찾을 수 없어요"));
      todoAssigneeRepository.save(new TodoAssignee(todo, user));
      result.add(user);
    }
    return result;
  }

  private List<AssigneeBrief> toAssigneeBriefs(List<User> users) {
    return users.stream()
        .map(u -> new AssigneeBrief(u.getId(), u.getNickname(), u.getProfileImage()))
        .toList();
  }

  /**
   * 신규로 추가된 담당자에게만 알림 — 요청자 본인(자기 자신을 담당자로 추가)과 이미 담당자였던 사람(수정으로 유지된 경우)은 제외한다(2026-08-05 확정,
   * specs/0015-알림-트리거.md). 생성 시에는 {@code previousAssigneeIds}가 비어 있어 배정된 전원이 "신규"로 취급된다.
   */
  private void notifyNewAssignees(
      Room room,
      Todo todo,
      String actorUid,
      List<User> assignees,
      Set<String> previousAssigneeIds) {
    List<User> newAssignees =
        assignees.stream()
            .filter(user -> !user.getId().equals(actorUid))
            .filter(user -> !previousAssigneeIds.contains(user.getId()))
            .toList();
    if (newAssignees.isEmpty()) {
      return;
    }
    pushNotifier.notifyEach(
        newAssignees,
        PushType.ASSIGNED_TODO_ADDED,
        room,
        "새 투두가 도착했어요 📮",
        room.getName() + " · " + todo.getTitle());
  }

  private Category resolveCategoryOrNull(Long roomId, Long categoryId) {
    if (categoryId == null) {
      return null;
    }
    Category category =
        categoryRepository
            .findById(categoryId)
            .orElseThrow(() -> new BadRequestException("존재하지 않는 카테고리예요"));
    if (!category.getRoom().getId().equals(roomId)) {
      throw new BadRequestException("다른 방의 카테고리예요");
    }
    return category;
  }

  private Todo resolveTodo(Long roomId, Long todoId) {
    Todo todo = todoRepository.findById(todoId).orElseThrow(TodoNotFoundException::new);
    if (!todo.getRoom().getId().equals(roomId)) {
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
