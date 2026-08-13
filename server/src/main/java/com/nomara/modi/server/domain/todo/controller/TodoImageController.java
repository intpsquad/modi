package com.nomara.modi.server.domain.todo.controller;

import com.nomara.modi.server.domain.todo.dto.SetTodoImagePinnedRequest;
import com.nomara.modi.server.domain.todo.dto.TodoImageResponse;
import com.nomara.modi.server.domain.todo.dto.TodoImageUploadUrlResponse;
import com.nomara.modi.server.domain.todo.service.TodoImageService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * 투두 사진 첨부 업로드 준비 + 모아보기 "이미지" 탭(2026-08-09, docs/backend/todo-image-archive-handoff.md). 사진 자체는 투두
 * 생성/수정({@code TodoController})이 저장한다 — 여기는 업로드 URL 발급과 방 전체 이미지 피드/핀만 다룬다.
 */
@RestController
public class TodoImageController {

  private final TodoImageService todoImageService;

  public TodoImageController(TodoImageService todoImageService) {
    this.todoImageService = todoImageService;
  }

  /** MinIO presigned PUT 업로드 URL 발급 — 투두를 만들기 전에 부른다(앱이 사진을 먼저 고르는 흐름). */
  @PostMapping("/rooms/{roomId}/todos/image/upload-url")
  public TodoImageUploadUrlResponse createUploadUrl(
      HttpServletRequest request, @PathVariable Long roomId) {
    return todoImageService.createUploadUrl(uid(request), roomId);
  }

  @GetMapping("/rooms/{roomId}/archive/todo-images")
  public List<TodoImageResponse> list(HttpServletRequest request, @PathVariable Long roomId) {
    return todoImageService.listImages(uid(request), roomId);
  }

  @PatchMapping("/rooms/{roomId}/archive/todo-images/{todoId}/pin")
  public TodoImageResponse setPinned(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long todoId,
      @Valid @RequestBody SetTodoImagePinnedRequest body) {
    return todoImageService.setPinned(uid(request), roomId, todoId, body.pinned());
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
