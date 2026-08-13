package com.nomara.modi.server.domain.todo.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.activity.dto.ActivityResponse;
import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.category.entity.Category;
import com.nomara.modi.server.domain.category.repository.CategoryRepository;
import com.nomara.modi.server.domain.character.entity.UserActivityKind;
import com.nomara.modi.server.domain.character.repository.UserActivityRepository;
import com.nomara.modi.server.domain.notification.entity.NotificationSetting;
import com.nomara.modi.server.domain.notification.repository.NotificationSettingRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.dto.AssigneeBrief;
import com.nomara.modi.server.domain.todo.dto.CreateTodoRequest;
import com.nomara.modi.server.domain.todo.dto.TodoBriefResponse;
import com.nomara.modi.server.domain.todo.dto.TodoResponse;
import com.nomara.modi.server.domain.todo.dto.UpdateTodoRequest;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.entity.TodoAssignee;
import com.nomara.modi.server.domain.todo.repository.TodoAssigneeRepository;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
import com.nomara.modi.server.support.FakePushSenderConfig;
import com.nomara.modi.server.support.RecordingPushSender;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.transaction.annotation.Transactional;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** 홈 오늘투두 체크박스 즉시 토글(specs/0005-홈-대시보드.md)을 실제 Postgres+Redis(Testcontainers)로 검증한다. */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(FakePushSenderConfig.class)
class TodoServiceTest {

  @Container @ServiceConnection
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

  @Container
  @ServiceConnection(name = "redis")
  static GenericContainer<?> redis =
      new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.enabled", () -> "true");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
  }

  @Autowired private TestRestTemplate restTemplate;
  @Autowired private TodoService todoService;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private TodoRepository todoRepository;
  @Autowired private TodoAssigneeRepository todoAssigneeRepository;
  @Autowired private CategoryRepository categoryRepository;
  @Autowired private NotificationSettingRepository notificationSettingRepository;
  @Autowired private RecordingPushSender pushSender;
  @Autowired private ActivityService activityService;
  @Autowired private UserActivityRepository userActivityRepository;

  private static int counter = 0;

  @BeforeEach
  void clearPushes() {
    pushSender.clear();
  }

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter), null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10)));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  @Test
  void toggleWithoutAuthReturnsUnauthorized() {
    var response =
        restTemplate.exchange(
            "/rooms/1/todos/1", org.springframework.http.HttpMethod.PATCH, null, String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void completingTodoSetsCompletedTrueAndTimestamp() {
    Room room = room();
    User member = user("uid-todo-member");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));

    TodoBriefResponse response =
        todoService.setCompleted(member.getId(), room.getId(), todo.getId(), true);

    assertThat(response.completed()).isTrue();
    assertThat(response.completedAt()).isNotNull();
    assertThat(todoRepository.findById(todo.getId()).orElseThrow().isCompleted()).isTrue();
  }

  /** 홈 활동 피드(2026-08-06, docs/backend/home-activity-feed.md) TODO_COMPLETED + TODO_ALL_DONE. */
  @Test
  void completingTheOnlyAssignedTodoRecordsCompletedAndAllDoneActivity() {
    Room room = room();
    User member = user("uid-todo-activity");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, member));

    todoService.setCompleted(member.getId(), room.getId(), todo.getId(), true);

    List<ActivityResponse> activities = activityService.getRecentActivities(room);
    assertThat(activities)
        .anySatisfy(
            a -> {
              assertThat(a.type()).isEqualTo("TODO_COMPLETED");
              assertThat(a.actorUserId()).isEqualTo(member.getId());
            });
    assertThat(activities).anySatisfy(a -> assertThat(a.type()).isEqualTo("TODO_ALL_DONE"));
  }

  /** 담당자가 더 남아 있으면(100% 미달) TODO_ALL_DONE은 안 남는다. */
  @Test
  void completingOneOfManyAssignedTodosDoesNotRecordAllDone() {
    Room room = room();
    User member = user("uid-todo-activity-partial");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo done = todoRepository.save(new Todo(room, null, "할일1", null));
    Todo pending = todoRepository.save(new Todo(room, null, "할일2", null));
    todoAssigneeRepository.save(new TodoAssignee(done, member));
    todoAssigneeRepository.save(new TodoAssignee(pending, member));

    todoService.setCompleted(member.getId(), room.getId(), done.getId(), true);

    assertThat(activityService.getRecentActivities(room))
        .noneMatch(a -> a.type().equals("TODO_ALL_DONE"));
  }

  @Test
  void reopeningTodoClearsCompletedAtAgain() {
    Room room = room();
    User member = user("uid-todo-reopen");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));
    todoService.setCompleted(member.getId(), room.getId(), todo.getId(), true);

    TodoBriefResponse response =
        todoService.setCompleted(member.getId(), room.getId(), todo.getId(), false);

    assertThat(response.completed()).isFalse();
    assertThat(response.completedAt()).isNull();
  }

  @Test
  void assigneeCanCompleteOwnTodo() {
    Room room = room();
    User assignee = user("uid-todo-assignee-own");
    roomMemberRepository.save(new RoomMember(room, assignee));
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, assignee));

    TodoBriefResponse response =
        todoService.setCompleted(assignee.getId(), room.getId(), todo.getId(), true);

    assertThat(response.completed()).isTrue();
  }

  @Test
  void nonAssigneeCannotCompleteAssignedTodo() {
    Room room = room();
    User assignee = user("uid-todo-assignee-only");
    User outsider = user("uid-todo-non-assignee");
    roomMemberRepository.save(new RoomMember(room, assignee));
    roomMemberRepository.save(new RoomMember(room, outsider));
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, assignee));

    ApiException ex =
        catchThrowableOfType(
            () -> todoService.setCompleted(outsider.getId(), room.getId(), todo.getId(), true),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void anyOfMultipleAssigneesCanCompleteTodo() {
    Room room = room();
    User assigneeA = user("uid-todo-multi-a");
    User assigneeB = user("uid-todo-multi-b");
    roomMemberRepository.save(new RoomMember(room, assigneeA));
    roomMemberRepository.save(new RoomMember(room, assigneeB));
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, assigneeA));
    todoAssigneeRepository.save(new TodoAssignee(todo, assigneeB));

    TodoBriefResponse response =
        todoService.setCompleted(assigneeB.getId(), room.getId(), todo.getId(), true);

    assertThat(response.completed()).isTrue();
  }

  @Test
  void completingSoloAssignedTodoStillRecordsPlainTodoCompleted() {
    Room room = room();
    User assignee = user("uid-todo-solo-actor");
    roomMemberRepository.save(new RoomMember(room, assignee));
    Todo todo = todoRepository.save(new Todo(room, null, "단독 할일", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, assignee));

    todoService.setCompleted(assignee.getId(), room.getId(), todo.getId(), true);

    List<ActivityResponse> completed =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("TODO_COMPLETED"))
            .toList();
    assertThat(completed).hasSize(1);
    assertThat(completed.get(0).actorUserId()).isEqualTo(assignee.getId());
    assertThat(activityService.getRecentActivities(room))
        .noneMatch(a -> a.type().equals("TODO_COMPLETED_SHARED"));
  }

  /**
   * 공동 완료 문구(docs/backend/live-banner-copy-handoff.md §2) + 완료자 오귀속 회귀 커버 — 비대표 담당자(닉네임이 더 긴 쪽)가
   * 완료해도 {@code activities.actor_user_id}는 실제 완료자여야 한다.
   */
  @Test
  void completingSharedTodoRecordsSharedEventWithRepresentativeAndActualCompleterAsActor() {
    Room room = room();
    User shortNick = userRepository.save(new User("uid-todo-shared-short", "민", null));
    User longNick = userRepository.save(new User("uid-todo-shared-long", "김지훈길다", null));
    roomMemberRepository.save(new RoomMember(room, shortNick));
    roomMemberRepository.save(new RoomMember(room, longNick));
    Todo todo = todoRepository.save(new Todo(room, null, "공동 할일", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, shortNick));
    todoAssigneeRepository.save(new TodoAssignee(todo, longNick));

    todoService.setCompleted(longNick.getId(), room.getId(), todo.getId(), true);

    List<ActivityResponse> shared =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("TODO_COMPLETED_SHARED"))
            .toList();
    assertThat(shared).hasSize(1);
    assertThat(shared.get(0).targetName()).isEqualTo(shortNick.getNickname());
    assertThat(shared.get(0).count()).isEqualTo(2);
    assertThat(shared.get(0).actorUserId()).isEqualTo(longNick.getId());
    assertThat(activityService.getRecentActivities(room))
        .noneMatch(a -> a.type().equals("TODO_COMPLETED"));
  }

  @Test
  void anyRoomMemberCanCompleteUnassignedTodo() {
    Room room = room();
    User member = user("uid-todo-unassigned-member");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo todo = todoRepository.save(new Todo(room, null, "미지정 할일", null));

    TodoBriefResponse response =
        todoService.setCompleted(member.getId(), room.getId(), todo.getId(), true);

    assertThat(response.completed()).isTrue();
    List<ActivityResponse> completed =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("TODO_COMPLETED"))
            .toList();
    assertThat(completed).hasSize(1);
    assertThat(activityService.getRecentActivities(room))
        .noneMatch(a -> a.type().equals("TODO_COMPLETED_SHARED"));
  }

  @Test
  void nonMemberCannotToggleTodo() {
    Room room = room();
    User member = user("uid-todo-owner");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));

    ApiException ex =
        catchThrowableOfType(
            () -> todoService.setCompleted("uid-todo-outsider", room.getId(), todo.getId(), true),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void todoFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-todo-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    Todo todoInRoomB = todoRepository.save(new Todo(roomB, null, "다른방 할일", null));

    ApiException ex =
        catchThrowableOfType(
            () ->
                todoService.setCompleted(member.getId(), roomA.getId(), todoInRoomB.getId(), true),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void listWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.getForEntity("/rooms/1/todos", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void createWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.postForEntity("/rooms/1/todos", null, String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void listTodosReturnsAssigneesGroupedPerTodo() {
    Room room = room();
    User a = user("uid-list-a");
    User b = user("uid-list-b");
    roomMemberRepository.save(new RoomMember(room, a));
    roomMemberRepository.save(new RoomMember(room, b));
    Todo assigned = todoRepository.save(new Todo(room, null, "담당있음", null));
    todoAssigneeRepository.save(new TodoAssignee(assigned, a));
    todoAssigneeRepository.save(new TodoAssignee(assigned, b));
    todoRepository.save(new Todo(room, null, "미지정", null));

    List<TodoResponse> responses = todoService.listTodos(a.getId(), room.getId());

    assertThat(responses).hasSize(2);
    assertThat(responses).extracting(TodoResponse::createdAt).doesNotContainNull();
    TodoResponse assignedResponse =
        responses.stream().filter(r -> r.title().equals("담당있음")).findFirst().orElseThrow();
    assertThat(assignedResponse.assignees())
        .extracting(AssigneeBrief::userId)
        .containsExactlyInAnyOrder(a.getId(), b.getId());
    TodoResponse unassignedResponse =
        responses.stream().filter(r -> r.title().equals("미지정")).findFirst().orElseThrow();
    assertThat(unassignedResponse.assignees()).isEmpty();
  }

  @Test
  void nonMemberCannotListTodos() {
    Room room = room();
    User member = user("uid-list-owner");
    roomMemberRepository.save(new RoomMember(room, member));

    ApiException ex =
        catchThrowableOfType(
            () -> todoService.listTodos("uid-list-outsider", room.getId()), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  /** S-18 전체화면 상세 — 담당자·마감일까지 채워 돌려준다(2026-08-07 롤백 후에도 전체화면 수정은 유지). */
  @Test
  void getTodoReturnsFullDetailWithAssignees() {
    Room room = room();
    User member = user("uid-get-todo");
    roomMemberRepository.save(new RoomMember(room, member));
    TodoResponse created =
        todoService.createTodo(
            member.getId(),
            room.getId(),
            new CreateTodoRequest(
                "회의 자료 정리", "회의 전에 공유해요", null, List.of(member.getId()), LocalDate.of(2026, 8, 8)));

    TodoResponse detail = todoService.getTodo(member.getId(), room.getId(), created.id());

    assertThat(detail.title()).isEqualTo("회의 자료 정리");
    assertThat(detail.detail()).isEqualTo("회의 전에 공유해요");
    assertThat(detail.assignees())
        .extracting(AssigneeBrief::userId)
        .containsExactly(member.getId());
    assertThat(detail.dueDate()).isEqualTo(LocalDate.of(2026, 8, 8));
  }

  /** 협업 캐릭터(specs/0016) 활동성 신호 — 투두 상세 조회 시 TODO_VIEW 로그가 남는다. */
  @Test
  void getTodoRecordsTodoViewActivity() {
    Room room = room();
    User member = user("uid-get-todo-view-log");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));

    todoService.getTodo(member.getId(), room.getId(), todo.getId());

    assertThat(
            userActivityRepository.countByUserIdAndKindAndCreatedAtAfter(
                member.getId(), UserActivityKind.TODO_VIEW, Instant.now().minusSeconds(60)))
        .isEqualTo(1);
  }

  @Test
  void getTodoFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-get-todo-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    Todo todoInRoomB = todoRepository.save(new Todo(roomB, null, "다른방 할일", null));

    ApiException ex =
        catchThrowableOfType(
            () -> todoService.getTodo(member.getId(), roomA.getId(), todoInRoomB.getId()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void nonMemberCannotGetTodo() {
    Room room = room();
    User member = user("uid-get-todo-owner");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));

    ApiException ex =
        catchThrowableOfType(
            () -> todoService.getTodo("uid-get-todo-outsider", room.getId(), todo.getId()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void listMemberTodosReturnsOnlyThatMembersAssignedTodosRegardlessOfCompletion() {
    Room room = room();
    User a = user("uid-member-a");
    User b = user("uid-member-b");
    roomMemberRepository.save(new RoomMember(room, a));
    roomMemberRepository.save(new RoomMember(room, b));
    Todo aDone = todoRepository.save(new Todo(room, null, "A 완료", null));
    aDone.complete();
    todoRepository.save(aDone);
    todoAssigneeRepository.save(new TodoAssignee(aDone, a));
    Todo aTodo = todoRepository.save(new Todo(room, null, "A 진행중", null));
    todoAssigneeRepository.save(new TodoAssignee(aTodo, a));
    Todo bOnly = todoRepository.save(new Todo(room, null, "B 담당", null));
    todoAssigneeRepository.save(new TodoAssignee(bOnly, b));

    List<TodoResponse> responses = todoService.listMemberTodos(b.getId(), room.getId(), a.getId());

    assertThat(responses)
        .extracting(TodoResponse::title)
        .containsExactlyInAnyOrder("A 완료", "A 진행중");
  }

  @Test
  void listMemberTodosExcludesTodosFromAnotherRoom() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-member-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    Todo todoInRoomA = todoRepository.save(new Todo(roomA, null, "A방 할일", null));
    todoAssigneeRepository.save(new TodoAssignee(todoInRoomA, member));
    Todo todoInRoomB = todoRepository.save(new Todo(roomB, null, "B방 할일", null));
    todoAssigneeRepository.save(new TodoAssignee(todoInRoomB, member));

    List<TodoResponse> responses =
        todoService.listMemberTodos(member.getId(), roomA.getId(), member.getId());

    assertThat(responses).extracting(TodoResponse::title).containsExactly("A방 할일");
  }

  @Test
  void listMemberTodosForNonMemberTargetReturnsNotFound() {
    Room room = room();
    User member = user("uid-member-viewer");
    roomMemberRepository.save(new RoomMember(room, member));

    ApiException ex =
        catchThrowableOfType(
            () -> todoService.listMemberTodos(member.getId(), room.getId(), "uid-not-a-member"),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void nonMemberCannotListMemberTodos() {
    Room room = room();
    User member = user("uid-member-target");
    roomMemberRepository.save(new RoomMember(room, member));

    ApiException ex =
        catchThrowableOfType(
            () -> todoService.listMemberTodos("uid-member-outsider", room.getId(), member.getId()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void createTodoWithCategoryAndAssigneesSucceeds() {
    Room room = room();
    User member = user("uid-create-a");
    roomMemberRepository.save(new RoomMember(room, member));
    Category category = categoryRepository.save(new Category(room, "카테고리"));

    TodoResponse response =
        todoService.createTodo(
            member.getId(),
            room.getId(),
            new CreateTodoRequest("제목", "상세", category.getId(), List.of(member.getId())));

    assertThat(response.title()).isEqualTo("제목");
    assertThat(response.categoryId()).isEqualTo(category.getId());
    assertThat(response.assignees())
        .extracting(AssigneeBrief::userId)
        .containsExactly(member.getId());
    assertThat(response.completed()).isFalse();
  }

  /** full_spec.md:205, specs/0015-알림-트리거.md — 배정된 담당자에게 알림, 자기 자신을 배정해도 본인에겐 안 간다. */
  @Test
  void createTodoNotifiesAssignedUsersExceptTheCreator() {
    Room room = room();
    User creator = user("uid-create-notify-creator");
    User other = user("uid-create-notify-other");
    roomMemberRepository.save(new RoomMember(room, creator));
    roomMemberRepository.save(new RoomMember(room, other));
    creator.updateFcmToken("token-todo-creator");
    userRepository.save(creator);
    other.updateFcmToken("token-todo-other");
    userRepository.save(other);

    todoService.createTodo(
        creator.getId(),
        room.getId(),
        new CreateTodoRequest("제목", null, null, List.of(creator.getId(), other.getId())));

    assertThat(pushSender.sentToTokens()).containsExactly("token-todo-other");
    assertThat(pushSender.sent().getFirst().title()).isEqualTo("새 투두가 도착했어요 📮");
    assertThat(pushSender.sent().getFirst().body()).isEqualTo(room.getName() + " · 제목");
  }

  @Test
  @Transactional
  void createTodoSkipsNotificationWhenAssignedTodoAddedDisabled() {
    Room room = room();
    User creator = user("uid-create-notifyoff-creator");
    User other = user("uid-create-notifyoff-other");
    roomMemberRepository.save(new RoomMember(room, creator));
    roomMemberRepository.save(new RoomMember(room, other));
    other.updateFcmToken("token-todo-notifyoff-other");
    userRepository.save(other);
    NotificationSetting settings = new NotificationSetting(other);
    settings.updateSettings(true, true, true, true, true, true, false, true);
    notificationSettingRepository.save(settings);

    todoService.createTodo(
        creator.getId(),
        room.getId(),
        new CreateTodoRequest("제목", null, null, List.of(other.getId())));

    assertThat(pushSender.sentToTokens()).isEmpty();
  }

  @Test
  void createTodoWithoutAssigneesIsUnassigned() {
    Room room = room();
    User member = user("uid-create-b");
    roomMemberRepository.save(new RoomMember(room, member));

    TodoResponse response =
        todoService.createTodo(
            member.getId(), room.getId(), new CreateTodoRequest("독립 투두", null, null, null));

    assertThat(response.categoryId()).isNull();
    assertThat(response.assignees()).isEmpty();
  }

  /** 홈 활동 피드(2026-08-06) TODO_ADDED — 작성자가 그대로 actor로 남는지. */
  @Test
  void creatingTodoRecordsTodoAddedActivityWithCreatorAsActor() {
    Room room = room();
    User member = user("uid-create-activity");
    roomMemberRepository.save(new RoomMember(room, member));

    todoService.createTodo(
        member.getId(), room.getId(), new CreateTodoRequest("새 투두", null, null, null));

    assertThat(activityService.getRecentActivities(room))
        .anySatisfy(
            a -> {
              assertThat(a.type()).isEqualTo("TODO_ADDED");
              assertThat(a.actorUserId()).isEqualTo(member.getId());
            });
  }

  @Test
  void createTodoWithCategoryFromAnotherRoomThrowsBadRequest() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-create-c");
    roomMemberRepository.save(new RoomMember(roomA, member));
    Category categoryOfRoomB = categoryRepository.save(new Category(roomB, "남의 카테고리"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                todoService.createTodo(
                    member.getId(),
                    roomA.getId(),
                    new CreateTodoRequest("제목", null, categoryOfRoomB.getId(), null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void createTodoWithNonMemberAssigneeThrowsBadRequest() {
    Room room = room();
    User member = user("uid-create-d");
    roomMemberRepository.save(new RoomMember(room, member));
    User outsider = user("uid-create-outsider");

    ApiException ex =
        catchThrowableOfType(
            () ->
                todoService.createTodo(
                    member.getId(),
                    room.getId(),
                    new CreateTodoRequest("제목", null, null, List.of(outsider.getId()))),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void nonMemberCannotCreateTodo() {
    Room room = room();
    User member = user("uid-create-owner");
    roomMemberRepository.save(new RoomMember(room, member));

    ApiException ex =
        catchThrowableOfType(
            () ->
                todoService.createTodo(
                    "uid-create-outsider2",
                    room.getId(),
                    new CreateTodoRequest("제목", null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void updateTodoReplacesFieldsAndAssignees() {
    Room room = room();
    User a = user("uid-update-a");
    User b = user("uid-update-b");
    roomMemberRepository.save(new RoomMember(room, a));
    roomMemberRepository.save(new RoomMember(room, b));
    Todo todo = todoRepository.save(new Todo(room, null, "원래 제목", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, a));

    TodoResponse response =
        todoService.updateTodo(
            a.getId(),
            room.getId(),
            todo.getId(),
            new UpdateTodoRequest("새 제목", "새 상세", null, List.of(b.getId())));

    assertThat(response.title()).isEqualTo("새 제목");
    assertThat(response.detail()).isEqualTo("새 상세");
    assertThat(response.assignees()).extracting(AssigneeBrief::userId).containsExactly(b.getId());
  }

  /**
   * 2026-08-07 인라인 작성기 롤백 이후 남은 유일한 메타데이터가 마감일이다 — 협업 캐릭터가 마감 준수율 계산에 쓰므로 존치했다(specs/0006-투두-탭.md,
   * CharacterService).
   */
  @Test
  void createAndUpdateTodoPersistDueDate() {
    Room room = room();
    User member = user("uid-due-date");
    roomMemberRepository.save(new RoomMember(room, member));

    TodoResponse created =
        todoService.createTodo(
            member.getId(),
            room.getId(),
            new CreateTodoRequest(
                "회의 자료 정리", "회의 전에 공유해요", null, List.of(member.getId()), LocalDate.of(2026, 8, 8)));

    assertThat(created.dueDate()).isEqualTo(LocalDate.of(2026, 8, 8));

    TodoResponse updated =
        todoService.updateTodo(
            member.getId(),
            room.getId(),
            created.id(),
            new UpdateTodoRequest(
                "회의 자료 확정", null, null, List.of(member.getId()), LocalDate.of(2026, 8, 9)));

    assertThat(updated.dueDate()).isEqualTo(LocalDate.of(2026, 8, 9));

    TodoResponse listed = todoService.listTodos(member.getId(), room.getId()).getFirst();
    assertThat(listed.dueDate()).isEqualTo(LocalDate.of(2026, 8, 9));
  }

  /** PUT은 전체 교체다 — 마감일을 빼고 보내면 지워진다. 폼이 "없음"을 고른 경우와 같은 요청이라 구분할 수 없기 때문이다. */
  @Test
  void updateTodoWithoutDueDateClearsIt() {
    Room room = room();
    User member = user("uid-due-date-clear");
    roomMemberRepository.save(new RoomMember(room, member));
    TodoResponse created =
        todoService.createTodo(
            member.getId(),
            room.getId(),
            new CreateTodoRequest(
                "마감 있는 투두", null, null, List.of(member.getId()), LocalDate.of(2026, 8, 8)));
    assertThat(created.dueDate()).isEqualTo(LocalDate.of(2026, 8, 8));

    TodoResponse updated =
        todoService.updateTodo(
            member.getId(),
            room.getId(),
            created.id(),
            new UpdateTodoRequest("마감 지운 투두", "새 메모", null, List.of(member.getId())));

    assertThat(updated.title()).isEqualTo("마감 지운 투두");
    assertThat(updated.dueDate()).isNull();
  }

  /** 2026-08-09, docs/backend/todo-image-archive-handoff.md — 투두 사진 첨부(1장). */
  @Test
  void createAndUpdateTodoPersistImageUrl() {
    Room room = room();
    User member = user("uid-image");
    roomMemberRepository.save(new RoomMember(room, member));

    TodoResponse created =
        todoService.createTodo(
            member.getId(),
            room.getId(),
            new CreateTodoRequest(
                "사진 있는 투두",
                null,
                null,
                List.of(member.getId()),
                null,
                "https://minio.local/todos/1/a.jpg"));

    assertThat(created.imageUrl()).isEqualTo("https://minio.local/todos/1/a.jpg");

    TodoResponse updated =
        todoService.updateTodo(
            member.getId(),
            room.getId(),
            created.id(),
            new UpdateTodoRequest(
                "사진 바뀐 투두",
                null,
                null,
                List.of(member.getId()),
                null,
                "https://minio.local/todos/1/b.jpg"));

    assertThat(updated.imageUrl()).isEqualTo("https://minio.local/todos/1/b.jpg");
  }

  /** PUT은 전체 교체다 — dueDate와 같은 규칙으로, 사진을 빼고 보내면 첨부가 해제된다. */
  @Test
  void updateTodoWithoutImageUrlClearsIt() {
    Room room = room();
    User member = user("uid-image-clear");
    roomMemberRepository.save(new RoomMember(room, member));
    TodoResponse created =
        todoService.createTodo(
            member.getId(),
            room.getId(),
            new CreateTodoRequest(
                "사진 있는 투두",
                null,
                null,
                List.of(member.getId()),
                null,
                "https://minio.local/todos/1/a.jpg"));
    assertThat(created.imageUrl()).isNotNull();

    TodoResponse updated =
        todoService.updateTodo(
            member.getId(),
            room.getId(),
            created.id(),
            new UpdateTodoRequest("사진 지운 투두", null, null, List.of(member.getId())));

    assertThat(updated.imageUrl()).isNull();
  }

  /** 2026-08-09, docs/backend/todo-form-handoff.md — 중요 표시. PUT은 전체 교체라 생략하면 false로 덮인다. */
  @Test
  void createAndUpdateTodoPersistImportant() {
    Room room = room();
    User member = user("uid-important");
    roomMemberRepository.save(new RoomMember(room, member));

    TodoResponse created =
        todoService.createTodo(
            member.getId(),
            room.getId(),
            new CreateTodoRequest("중요한 투두", null, null, List.of(member.getId()), null, null, true));

    assertThat(created.important()).isTrue();

    TodoResponse updated =
        todoService.updateTodo(
            member.getId(),
            room.getId(),
            created.id(),
            new UpdateTodoRequest("안 중요해진 투두", null, null, List.of(member.getId())));

    assertThat(updated.important()).isFalse();
  }

  /**
   * specs/0015-알림-트리거.md — 담당자를 전부 지우고 재생성하는 구조라도, 알림은 "신규로 추가된" 담당자에게만 간다. 기존부터 담당자였던 사람은 수정으로
   * 재알림받지 않는다.
   */
  @Test
  void updateTodoNotifiesOnlyNewlyAddedAssignees() {
    Room room = room();
    User actor = user("uid-update-notify-actor");
    User kept = user("uid-update-notify-kept");
    User added = user("uid-update-notify-added");
    roomMemberRepository.save(new RoomMember(room, actor));
    roomMemberRepository.save(new RoomMember(room, kept));
    roomMemberRepository.save(new RoomMember(room, added));
    kept.updateFcmToken("token-update-kept");
    userRepository.save(kept);
    added.updateFcmToken("token-update-added");
    userRepository.save(added);
    Todo todo = todoRepository.save(new Todo(room, null, "원래 제목", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, kept));

    todoService.updateTodo(
        actor.getId(),
        room.getId(),
        todo.getId(),
        new UpdateTodoRequest("새 제목", null, null, List.of(kept.getId(), added.getId())));

    assertThat(pushSender.sentToTokens()).containsExactly("token-update-added");
    assertThat(pushSender.sent().getFirst().title()).isEqualTo("새 투두가 도착했어요 📮");
    assertThat(pushSender.sent().getFirst().body()).isEqualTo(room.getName() + " · 새 제목");
  }

  @Test
  void updateTodoOnAnotherRoomTodoThrowsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-update-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    Todo todoInRoomB = todoRepository.save(new Todo(roomB, null, "다른방 할일", null));

    ApiException ex =
        catchThrowableOfType(
            () ->
                todoService.updateTodo(
                    member.getId(),
                    roomA.getId(),
                    todoInRoomB.getId(),
                    new UpdateTodoRequest("제목", null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void deleteTodoRemovesTodoAndAssigneeRowsViaCascade() {
    Room room = room();
    User member = user("uid-delete-a");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo todo = todoRepository.save(new Todo(room, null, "삭제될 투두", null));
    todoAssigneeRepository.save(new TodoAssignee(todo, member));

    todoService.deleteTodo(member.getId(), room.getId(), todo.getId());

    assertThat(todoRepository.findById(todo.getId())).isEmpty();
    assertThat(todoAssigneeRepository.findByTodoIdIn(List.of(todo.getId()))).isEmpty();
  }

  @Test
  void nonMemberCannotDeleteTodo() {
    Room room = room();
    User member = user("uid-delete-owner");
    roomMemberRepository.save(new RoomMember(room, member));
    Todo todo = todoRepository.save(new Todo(room, null, "할일", null));

    ApiException ex =
        catchThrowableOfType(
            () -> todoService.deleteTodo("uid-delete-outsider", room.getId(), todo.getId()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void createTodoAssignsIncrementingPositionWithinCategory() {
    Room room = room();
    User member = user("uid-order-a");
    roomMemberRepository.save(new RoomMember(room, member));
    Category category = categoryRepository.save(new Category(room, "카테고리"));

    TodoResponse first =
        todoService.createTodo(
            member.getId(),
            room.getId(),
            new CreateTodoRequest("첫번째", null, category.getId(), null));
    TodoResponse second =
        todoService.createTodo(
            member.getId(),
            room.getId(),
            new CreateTodoRequest("두번째", null, category.getId(), null));

    assertThat(todoRepository.findById(first.id()).orElseThrow().getPosition()).isZero();
    assertThat(todoRepository.findById(second.id()).orElseThrow().getPosition()).isEqualTo(1);
  }

  @Test
  void reorderMyTodosLeavesOtherAssigneesPositionsUntouched() {
    Room room = room();
    User me = user("uid-order-me");
    User other = user("uid-order-other");
    roomMemberRepository.save(new RoomMember(room, me));
    roomMemberRepository.save(new RoomMember(room, other));
    Category category = categoryRepository.save(new Category(room, "카테고리"));

    // [내A, 남B, 내C, 남D] 순서로 만든다.
    TodoResponse a =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("A", null, category.getId(), null));
    todoAssigneeRepository.save(
        new TodoAssignee(todoRepository.findById(a.id()).orElseThrow(), me));
    TodoResponse b =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("B", null, category.getId(), null));
    todoAssigneeRepository.save(
        new TodoAssignee(todoRepository.findById(b.id()).orElseThrow(), other));
    TodoResponse c =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("C", null, category.getId(), null));
    todoAssigneeRepository.save(
        new TodoAssignee(todoRepository.findById(c.id()).orElseThrow(), me));
    TodoResponse d =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("D", null, category.getId(), null));
    todoAssigneeRepository.save(
        new TodoAssignee(todoRepository.findById(d.id()).orElseThrow(), other));

    int originalPositionOfB = todoRepository.findById(b.id()).orElseThrow().getPosition();
    int originalPositionOfD = todoRepository.findById(d.id()).orElseThrow().getPosition();

    // C를 A보다 위로 — [내C, 내A]로 재배치 요청.
    todoService.reorderMyTodos(me.getId(), room.getId(), category.getId(), List.of(c.id(), a.id()));

    List<Todo> finalOrder =
        todoRepository.findByRoomIdAndCategoryId(room.getId(), category.getId());
    assertThat(finalOrder).extracting(Todo::getId).containsExactly(c.id(), b.id(), a.id(), d.id());
    assertThat(todoRepository.findById(b.id()).orElseThrow().getPosition())
        .isEqualTo(originalPositionOfB);
    assertThat(todoRepository.findById(d.id()).orElseThrow().getPosition())
        .isEqualTo(originalPositionOfD);
  }

  @Test
  void reorderWithForeignTodoIsRejectedAsBadRequest() {
    Room room = room();
    User me = user("uid-order-foreign-me");
    User other = user("uid-order-foreign-other");
    roomMemberRepository.save(new RoomMember(room, me));
    roomMemberRepository.save(new RoomMember(room, other));
    Category category = categoryRepository.save(new Category(room, "카테고리"));
    TodoResponse mine =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("내것", null, category.getId(), null));
    todoAssigneeRepository.save(
        new TodoAssignee(todoRepository.findById(mine.id()).orElseThrow(), me));
    TodoResponse theirs =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("남의것", null, category.getId(), null));
    todoAssigneeRepository.save(
        new TodoAssignee(todoRepository.findById(theirs.id()).orElseThrow(), other));

    ApiException ex =
        catchThrowableOfType(
            () ->
                todoService.reorderMyTodos(
                    me.getId(), room.getId(), category.getId(), List.of(mine.id(), theirs.id())),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void unassignedTodoCannotBeIncludedInAnyonesReorder() {
    // 미지정(담당자 없음) 투두는 누구의 것도 아니라서 이 기능의 대상이 아니다 — FR-39와 다르게,
    // 여기서는 "미지정이면 누구나" 예외를 두지 않는다("내 투두만" 화면이 미지정을 안 보여주기 때문).
    Room room = room();
    User me = user("uid-order-unassigned-me");
    roomMemberRepository.save(new RoomMember(room, me));
    Category category = categoryRepository.save(new Category(room, "카테고리"));
    TodoResponse first =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("미지정1", null, category.getId(), null));
    TodoResponse second =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("미지정2", null, category.getId(), null));

    ApiException ex =
        catchThrowableOfType(
            () ->
                todoService.reorderMyTodos(
                    me.getId(), room.getId(), category.getId(), List.of(second.id(), first.id())),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void reorderingAssignedTodosSucceedsEvenWhenUnassignedTodosShareTheSameGroup() {
    // 2026-08-04 리뷰로 발견된 버그의 회귀 테스트 — 그룹에 미지정 투두가 섞여 있어도, 내가
    // 실제로 담당한 투두들만 정확히 골라 보내면 정상적으로 재배치돼야 한다(프론트의 "내 투두만"
    // 화면은 미지정을 안 보여주므로 항상 이 부분집합만 보낸다).
    Room room = room();
    User me = user("uid-order-mixed-me");
    roomMemberRepository.save(new RoomMember(room, me));
    Category category = categoryRepository.save(new Category(room, "카테고리"));
    TodoResponse mineA =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("내것A", null, category.getId(), null));
    todoAssigneeRepository.save(
        new TodoAssignee(todoRepository.findById(mineA.id()).orElseThrow(), me));
    todoService.createTodo(
        me.getId(), room.getId(), new CreateTodoRequest("미지정", null, category.getId(), null));
    TodoResponse mineC =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("내것C", null, category.getId(), null));
    todoAssigneeRepository.save(
        new TodoAssignee(todoRepository.findById(mineC.id()).orElseThrow(), me));

    List<TodoResponse> reordered =
        todoService.reorderMyTodos(
            me.getId(), room.getId(), category.getId(), List.of(mineC.id(), mineA.id()));

    assertThat(reordered).extracting(TodoResponse::id).containsExactly(mineC.id(), mineA.id());
  }

  @Test
  void nonMemberCannotReorderTodos() {
    Room room = room();
    User member = user("uid-order-nonmember-owner");
    roomMemberRepository.save(new RoomMember(room, member));
    Category category = categoryRepository.save(new Category(room, "카테고리"));
    TodoResponse todo =
        todoService.createTodo(
            member.getId(),
            room.getId(),
            new CreateTodoRequest("할일", null, category.getId(), null));

    ApiException ex =
        catchThrowableOfType(
            () ->
                todoService.reorderMyTodos(
                    "uid-order-outsider", room.getId(), category.getId(), List.of(todo.id())),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void movingTodoToNewCategoryResetsPositionToEndOfNewCategory() {
    Room room = room();
    User member = user("uid-order-move");
    roomMemberRepository.save(new RoomMember(room, member));
    Category categoryA = categoryRepository.save(new Category(room, "A"));
    Category categoryB = categoryRepository.save(new Category(room, "B"));
    todoService.createTodo(
        member.getId(),
        room.getId(),
        new CreateTodoRequest("B의 기존 항목", null, categoryB.getId(), null));
    TodoResponse moving =
        todoService.createTodo(
            member.getId(),
            room.getId(),
            new CreateTodoRequest("이동할 투두", null, categoryA.getId(), null));

    todoService.updateTodo(
        member.getId(),
        room.getId(),
        moving.id(),
        new UpdateTodoRequest("이동할 투두", null, categoryB.getId(), null));

    assertThat(todoRepository.findById(moving.id()).orElseThrow().getPosition()).isEqualTo(1);
  }

  @Test
  void reorderWorksForUncategorizedTodosToo() {
    Room room = room();
    User me = user("uid-order-uncategorized");
    roomMemberRepository.save(new RoomMember(room, me));
    TodoResponse first =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("기타1", null, null, null));
    todoAssigneeRepository.save(
        new TodoAssignee(todoRepository.findById(first.id()).orElseThrow(), me));
    TodoResponse second =
        todoService.createTodo(
            me.getId(), room.getId(), new CreateTodoRequest("기타2", null, null, null));
    todoAssigneeRepository.save(
        new TodoAssignee(todoRepository.findById(second.id()).orElseThrow(), me));

    List<TodoResponse> reordered =
        todoService.reorderMyTodos(
            me.getId(), room.getId(), null, List.of(second.id(), first.id()));

    assertThat(reordered).extracting(TodoResponse::id).containsExactly(second.id(), first.id());
  }
}
