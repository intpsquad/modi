package com.nomara.modi.server.domain.todo.controller;

import com.nomara.modi.server.domain.todo.dto.CreateTodoRequest;
import com.nomara.modi.server.domain.todo.dto.ReorderTodosRequest;
import com.nomara.modi.server.domain.todo.dto.TodoBriefResponse;
import com.nomara.modi.server.domain.todo.dto.TodoCompleteRequest;
import com.nomara.modi.server.domain.todo.dto.TodoResponse;
import com.nomara.modi.server.domain.todo.dto.TodoSuggestionResponse;
import com.nomara.modi.server.domain.todo.dto.UpdateTodoRequest;
import com.nomara.modi.server.domain.todo.service.TodoService;
import com.nomara.modi.server.domain.todo.service.TodoSuggestionService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** specs/0006-투두-탭.md 기준 투두 CRUD + 완료 토글(specs/0005-홈-대시보드.md와 공유) 엔드포인트. */
@RestController
public class TodoController {

  private final TodoService todoService;
  private final TodoSuggestionService todoSuggestionService;

  public TodoController(TodoService todoService, TodoSuggestionService todoSuggestionService) {
    this.todoService = todoService;
    this.todoSuggestionService = todoSuggestionService;
  }

  @GetMapping("/rooms/{roomId}/todos")
  public List<TodoResponse> list(HttpServletRequest request, @PathVariable Long roomId) {
    return todoService.listTodos(uid(request), roomId);
  }

  /** S-18 전체화면 상세 — specs/0006-투두-탭.md. 2026-08-07 인라인 작성기 롤백 후에도 전체화면 수정은 유지돼 이 조회를 계속 쓴다. */
  @GetMapping("/rooms/{roomId}/todos/{todoId}")
  public TodoResponse get(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable Long todoId) {
    return todoService.getTodo(uid(request), roomId, todoId);
  }

  /** specs/0011-멤버-투두-콕찌르기.md(S-30-M) — 조회 전용, 체크 토글은 여기서 하지 않는다. */
  @GetMapping("/rooms/{roomId}/members/{userId}/todos")
  public List<TodoResponse> listMemberTodos(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable String userId) {
    return todoService.listMemberTodos(uid(request), roomId, userId);
  }

  @PostMapping("/rooms/{roomId}/todos")
  @ResponseStatus(HttpStatus.CREATED)
  public TodoResponse create(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @Valid @RequestBody CreateTodoRequest body) {
    return todoService.createTodo(uid(request), roomId, body);
  }

  /**
   * S-16-B AI 투두 추천 — 후보만 돌려준다. 채택은 앱이 {@code POST /rooms/{roomId}/todos}로 직접 하며 담당자는 미지정으로
   * 남는다(specs/full_spec.md S-16-B). 경로는 specs/0001-architecture.md 지정값.
   */
  @PostMapping("/rooms/{roomId}/todos/ai-suggest")
  public TodoSuggestionResponse aiSuggest(HttpServletRequest request, @PathVariable Long roomId) {
    return todoSuggestionService.suggest(uid(request), roomId);
  }

  @PutMapping("/rooms/{roomId}/todos/{todoId}")
  public TodoResponse update(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long todoId,
      @Valid @RequestBody UpdateTodoRequest body) {
    return todoService.updateTodo(uid(request), roomId, todoId, body);
  }

  /** 드래그 순서변경(사용자 요청, 2026-08-04) — "내 투두"만 옮길 수 있다(TodoService.reorderMyTodos 참고). */
  @PatchMapping("/rooms/{roomId}/todos/order")
  public List<TodoResponse> reorder(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @RequestBody ReorderTodosRequest body) {
    return todoService.reorderMyTodos(uid(request), roomId, body.categoryId(), body.todoIds());
  }

  @PatchMapping("/rooms/{roomId}/todos/{todoId}")
  public TodoBriefResponse setCompleted(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long todoId,
      @Valid @RequestBody TodoCompleteRequest body) {
    return todoService.setCompleted(uid(request), roomId, todoId, body.completed());
  }

  @DeleteMapping("/rooms/{roomId}/todos/{todoId}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void delete(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable Long todoId) {
    todoService.deleteTodo(uid(request), roomId, todoId);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
