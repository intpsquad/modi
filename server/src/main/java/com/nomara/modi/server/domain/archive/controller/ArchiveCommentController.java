package com.nomara.modi.server.domain.archive.controller;

import com.nomara.modi.server.domain.archive.dto.ArchiveCommentResponse;
import com.nomara.modi.server.domain.archive.dto.CreateArchiveCommentRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateArchiveCommentRequest;
import com.nomara.modi.server.domain.archive.service.ArchiveCommentService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** specs/0010-아카이브-탭.md — S-25-B 자료 상세 댓글(docs/backend/archive-comments-handoff.md). */
@RestController
public class ArchiveCommentController {

  private final ArchiveCommentService archiveCommentService;

  public ArchiveCommentController(ArchiveCommentService archiveCommentService) {
    this.archiveCommentService = archiveCommentService;
  }

  @GetMapping("/rooms/{roomId}/archive/items/{itemId}/comments")
  public List<ArchiveCommentResponse> list(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable Long itemId) {
    return archiveCommentService.listComments(uid(request), roomId, itemId);
  }

  @PostMapping("/rooms/{roomId}/archive/items/{itemId}/comments")
  @ResponseStatus(HttpStatus.CREATED)
  public ArchiveCommentResponse create(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long itemId,
      @RequestBody CreateArchiveCommentRequest body) {
    return archiveCommentService.createComment(uid(request), roomId, itemId, body);
  }

  @PatchMapping("/rooms/{roomId}/archive/items/{itemId}/comments/{commentId}")
  public ArchiveCommentResponse update(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long itemId,
      @PathVariable Long commentId,
      @RequestBody UpdateArchiveCommentRequest body) {
    return archiveCommentService.updateComment(uid(request), roomId, itemId, commentId, body);
  }

  @DeleteMapping("/rooms/{roomId}/archive/items/{itemId}/comments/{commentId}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void delete(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long itemId,
      @PathVariable Long commentId) {
    archiveCommentService.deleteComment(uid(request), roomId, itemId, commentId);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
