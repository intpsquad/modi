package com.nomara.modi.server.domain.archive.service;

import com.nomara.modi.server.domain.archive.dto.ArchiveCommentResponse;
import com.nomara.modi.server.domain.archive.dto.CreateArchiveCommentRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateArchiveCommentRequest;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveItemComment;
import com.nomara.modi.server.domain.archive.exception.ArchiveCommentNotFoundException;
import com.nomara.modi.server.domain.archive.exception.ArchiveItemNotFoundException;
import com.nomara.modi.server.domain.archive.exception.NotCommentAuthorException;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemCommentRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.BadRequestException;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * specs/0010-아카이브-탭.md — S-25-B 자료 상세 댓글(docs/backend/archive-comments-handoff.md). 2026-08-09부터
 * 작성자 본인의 수정·삭제도 지원한다.
 */
@Service
public class ArchiveCommentService {

  private final ArchiveItemRepository archiveItemRepository;
  private final ArchiveItemCommentRepository archiveItemCommentRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final UserRepository userRepository;

  public ArchiveCommentService(
      ArchiveItemRepository archiveItemRepository,
      ArchiveItemCommentRepository archiveItemCommentRepository,
      RoomMemberRepository roomMemberRepository,
      UserRepository userRepository) {
    this.archiveItemRepository = archiveItemRepository;
    this.archiveItemCommentRepository = archiveItemCommentRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.userRepository = userRepository;
  }

  @Transactional(readOnly = true)
  public List<ArchiveCommentResponse> listComments(String uid, Long roomId, Long itemId) {
    requireMembership(uid, roomId);
    ArchiveItem item = resolveItem(roomId, itemId);
    return archiveItemCommentRepository.findByItemIdOrderByCreatedAtAscIdAsc(item.getId()).stream()
        .map(ArchiveCommentResponse::of)
        .toList();
  }

  @Transactional
  public ArchiveCommentResponse createComment(
      String uid, Long roomId, Long itemId, CreateArchiveCommentRequest request) {
    requireMembership(uid, roomId);
    ArchiveItem item = resolveItem(roomId, itemId);
    String body = validateBody(request.body());
    User author = userRepository.findById(uid).orElseThrow();
    ArchiveItemComment saved =
        archiveItemCommentRepository.save(new ArchiveItemComment(item, author, body));
    return ArchiveCommentResponse.of(saved);
  }

  /** 본인이 작성한 댓글만 수정할 수 있다(2026-08-09 사용자 확정, docs/backend/archive-comments-handoff.md). */
  @Transactional
  public ArchiveCommentResponse updateComment(
      String uid, Long roomId, Long itemId, Long commentId, UpdateArchiveCommentRequest request) {
    requireMembership(uid, roomId);
    resolveItem(roomId, itemId);
    ArchiveItemComment comment = resolveComment(itemId, commentId);
    requireAuthor(uid, comment);
    comment.editBody(validateBody(request.body()));
    return ArchiveCommentResponse.of(comment);
  }

  /** 위와 동일한 권한 — 작성자 본인만. */
  @Transactional
  public void deleteComment(String uid, Long roomId, Long itemId, Long commentId) {
    requireMembership(uid, roomId);
    resolveItem(roomId, itemId);
    ArchiveItemComment comment = resolveComment(itemId, commentId);
    requireAuthor(uid, comment);
    archiveItemCommentRepository.delete(comment);
  }

  private String validateBody(String rawBody) {
    String body = blankToNull(rawBody);
    if (body == null) {
      throw new BadRequestException("댓글을 입력해 주세요");
    }
    if (body.length() > ArchiveTextLimits.MAX_COMMENT_BODY) {
      throw new BadRequestException("댓글이 너무 길어요");
    }
    return body;
  }

  private ArchiveItemComment resolveComment(Long itemId, Long commentId) {
    return archiveItemCommentRepository
        .findByIdAndItemId(commentId, itemId)
        .orElseThrow(ArchiveCommentNotFoundException::new);
  }

  /** 탈퇴한 작성자(author null)의 댓글은 본인 확인이 불가능하므로 아무도 수정·삭제할 수 없다. */
  private void requireAuthor(String uid, ArchiveItemComment comment) {
    User author = comment.getAuthor();
    if (author == null || !author.getId().equals(uid)) {
      throw new NotCommentAuthorException();
    }
  }

  private ArchiveItem resolveItem(Long roomId, Long itemId) {
    ArchiveItem item =
        archiveItemRepository.findById(itemId).orElseThrow(ArchiveItemNotFoundException::new);
    if (!item.getRoom().getId().equals(roomId)) {
      throw new ArchiveItemNotFoundException();
    }
    return item;
  }

  private void requireMembership(String uid, Long roomId) {
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, uid))) {
      throw new NotRoomMemberException();
    }
  }

  private String blankToNull(String value) {
    return (value == null || value.isBlank()) ? null : value;
  }
}
