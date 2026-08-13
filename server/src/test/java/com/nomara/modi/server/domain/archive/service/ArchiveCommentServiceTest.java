package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.archive.dto.ArchiveCommentResponse;
import com.nomara.modi.server.domain.archive.dto.CreateArchiveCommentRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateArchiveCommentRequest;
import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.exception.ArchiveCommentNotFoundException;
import com.nomara.modi.server.domain.archive.exception.ArchiveItemNotFoundException;
import com.nomara.modi.server.domain.archive.exception.NotCommentAuthorException;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
import com.nomara.modi.server.global.exception.BadRequestException;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 자료 상세 댓글(specs/0010-아카이브-탭.md, docs/backend/archive-comments-handoff.md)을 실제
 * Postgres(Testcontainers)로 검증한다.
 */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ArchiveCommentServiceTest {

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

  @Autowired private ArchiveCommentService archiveCommentService;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private ArchiveFolderRepository archiveFolderRepository;
  @Autowired private ArchiveItemRepository archiveItemRepository;

  private static int counter = 0;

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter), null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10)));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  private ArchiveItem item(Room room, User createdBy) {
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    return archiveItemRepository.save(
        new ArchiveItem(folder, room, "자료", null, "본문", null, null, createdBy));
  }

  @Test
  void listReturnsEmptyWhenNoComments() {
    Room room = room();
    User member = user("uid-comment-empty");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveItem item = item(room, member);

    List<ArchiveCommentResponse> comments =
        archiveCommentService.listComments(member.getId(), room.getId(), item.getId());

    assertThat(comments).isEmpty();
  }

  @Test
  void createdCommentAppearsInListWithAuthorAndBodyInWriteOrder() {
    Room room = room();
    User author = user("uid-comment-author");
    roomMemberRepository.save(new RoomMember(room, author));
    ArchiveItem item = item(room, author);

    archiveCommentService.createComment(
        author.getId(), room.getId(), item.getId(), new CreateArchiveCommentRequest("첫 댓글"));
    archiveCommentService.createComment(
        author.getId(), room.getId(), item.getId(), new CreateArchiveCommentRequest("두번째 댓글"));

    List<ArchiveCommentResponse> comments =
        archiveCommentService.listComments(author.getId(), room.getId(), item.getId());

    assertThat(comments).hasSize(2);
    assertThat(comments.get(0).body()).isEqualTo("첫 댓글");
    assertThat(comments.get(1).body()).isEqualTo("두번째 댓글");
    assertThat(comments.get(0).author().userId()).isEqualTo(author.getId());
    assertThat(comments.get(0).author().nickname()).isEqualTo(author.getNickname());
  }

  @Test
  void blankBodyIsRejected() {
    Room room = room();
    User member = user("uid-comment-blank");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveItem item = item(room, member);

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveCommentService.createComment(
                    member.getId(),
                    room.getId(),
                    item.getId(),
                    new CreateArchiveCommentRequest("   ")),
            ApiException.class);

    assertThat(ex).isInstanceOf(BadRequestException.class);
  }

  @Test
  void tooLongBodyIsRejected() {
    Room room = room();
    User member = user("uid-comment-toolong");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveItem item = item(room, member);
    String tooLong = "a".repeat(ArchiveTextLimits.MAX_COMMENT_BODY + 1);

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveCommentService.createComment(
                    member.getId(),
                    room.getId(),
                    item.getId(),
                    new CreateArchiveCommentRequest(tooLong)),
            ApiException.class);

    assertThat(ex).isInstanceOf(BadRequestException.class);
  }

  @Test
  void bodyAtMaxLengthIsAccepted() {
    Room room = room();
    User member = user("uid-comment-maxlength");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveItem item = item(room, member);
    String maxLength = "a".repeat(ArchiveTextLimits.MAX_COMMENT_BODY);

    ArchiveCommentResponse response =
        archiveCommentService.createComment(
            member.getId(), room.getId(), item.getId(), new CreateArchiveCommentRequest(maxLength));

    assertThat(response.body()).hasSize(ArchiveTextLimits.MAX_COMMENT_BODY);
  }

  @Test
  void nonMemberCannotListOrCreateComments() {
    Room room = room();
    User owner = user("uid-comment-owner");
    User outsider = user("uid-comment-outsider");
    roomMemberRepository.save(new RoomMember(room, owner));
    ArchiveItem item = item(room, owner);

    ApiException listEx =
        catchThrowableOfType(
            () -> archiveCommentService.listComments(outsider.getId(), room.getId(), item.getId()),
            ApiException.class);
    ApiException createEx =
        catchThrowableOfType(
            () ->
                archiveCommentService.createComment(
                    outsider.getId(),
                    room.getId(),
                    item.getId(),
                    new CreateArchiveCommentRequest("댓글")),
            ApiException.class);

    assertThat(listEx).isInstanceOf(NotRoomMemberException.class);
    assertThat(createEx).isInstanceOf(NotRoomMemberException.class);
  }

  @Test
  void itemFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-comment-cross-room");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    ArchiveItem itemOfRoomB = item(roomB, member);

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveCommentService.listComments(
                    member.getId(), roomA.getId(), itemOfRoomB.getId()),
            ApiException.class);

    assertThat(ex).isInstanceOf(ArchiveItemNotFoundException.class);
  }

  /** 탈퇴한 작성자의 댓글은 남고 author만 null이 된다(archive_items.created_by와 같은 근거). */
  @Test
  void commentFromDeletedAuthorIsReturnedWithNullAuthor() {
    Room room = room();
    User author = user("uid-comment-deleted-author");
    roomMemberRepository.save(new RoomMember(room, author));
    ArchiveItem item = item(room, author);
    archiveCommentService.createComment(
        author.getId(), room.getId(), item.getId(), new CreateArchiveCommentRequest("탈퇴 전 댓글"));

    // 탈퇴 전 모든 방을 먼저 나간다(V9__account_deletion_cascades.sql 주석 — room_members는 일부러
    // ON DELETE 정책이 없어, 멤버십이 남은 유저를 지우면 FK 위반으로 실패한다).
    roomMemberRepository.deleteById(new RoomMemberId(room.getId(), author.getId()));
    userRepository.deleteById(author.getId());

    User stillMember = user("uid-comment-still-member");
    roomMemberRepository.save(new RoomMember(room, stillMember));
    List<ArchiveCommentResponse> comments =
        archiveCommentService.listComments(stillMember.getId(), room.getId(), item.getId());

    assertThat(comments).hasSize(1);
    assertThat(comments.get(0).body()).isEqualTo("탈퇴 전 댓글");
    assertThat(comments.get(0).author()).isNull();
  }

  /** 2026-08-09 사용자 확정 — 작성자 본인만 댓글을 수정할 수 있다. */
  @Test
  void authorCanUpdateOwnComment() {
    Room room = room();
    User author = user("uid-comment-edit-author");
    roomMemberRepository.save(new RoomMember(room, author));
    ArchiveItem item = item(room, author);
    ArchiveCommentResponse created =
        archiveCommentService.createComment(
            author.getId(), room.getId(), item.getId(), new CreateArchiveCommentRequest("원본"));

    ArchiveCommentResponse updated =
        archiveCommentService.updateComment(
            author.getId(),
            room.getId(),
            item.getId(),
            created.id(),
            new UpdateArchiveCommentRequest("수정됨"));

    assertThat(updated.body()).isEqualTo("수정됨");
    List<ArchiveCommentResponse> comments =
        archiveCommentService.listComments(author.getId(), room.getId(), item.getId());
    assertThat(comments.get(0).body()).isEqualTo("수정됨");
  }

  @Test
  void nonAuthorCannotUpdateOrDeleteComment() {
    Room room = room();
    User author = user("uid-comment-owner-edit");
    User other = user("uid-comment-other-edit");
    roomMemberRepository.save(new RoomMember(room, author));
    roomMemberRepository.save(new RoomMember(room, other));
    ArchiveItem item = item(room, author);
    ArchiveCommentResponse created =
        archiveCommentService.createComment(
            author.getId(), room.getId(), item.getId(), new CreateArchiveCommentRequest("원본"));

    ApiException updateEx =
        catchThrowableOfType(
            () ->
                archiveCommentService.updateComment(
                    other.getId(),
                    room.getId(),
                    item.getId(),
                    created.id(),
                    new UpdateArchiveCommentRequest("남이 고침")),
            ApiException.class);
    ApiException deleteEx =
        catchThrowableOfType(
            () ->
                archiveCommentService.deleteComment(
                    other.getId(), room.getId(), item.getId(), created.id()),
            ApiException.class);

    assertThat(updateEx).isInstanceOf(NotCommentAuthorException.class);
    assertThat(deleteEx).isInstanceOf(NotCommentAuthorException.class);
  }

  @Test
  void updateRejectsBlankOrTooLongBody() {
    Room room = room();
    User author = user("uid-comment-edit-validate");
    roomMemberRepository.save(new RoomMember(room, author));
    ArchiveItem item = item(room, author);
    ArchiveCommentResponse created =
        archiveCommentService.createComment(
            author.getId(), room.getId(), item.getId(), new CreateArchiveCommentRequest("원본"));
    String tooLong = "a".repeat(ArchiveTextLimits.MAX_COMMENT_BODY + 1);

    ApiException blankEx =
        catchThrowableOfType(
            () ->
                archiveCommentService.updateComment(
                    author.getId(),
                    room.getId(),
                    item.getId(),
                    created.id(),
                    new UpdateArchiveCommentRequest("   ")),
            ApiException.class);
    ApiException tooLongEx =
        catchThrowableOfType(
            () ->
                archiveCommentService.updateComment(
                    author.getId(),
                    room.getId(),
                    item.getId(),
                    created.id(),
                    new UpdateArchiveCommentRequest(tooLong)),
            ApiException.class);

    assertThat(blankEx).isInstanceOf(BadRequestException.class);
    assertThat(tooLongEx).isInstanceOf(BadRequestException.class);
  }

  @Test
  void updateOrDeleteOnCommentFromAnotherItemIsNotFound() {
    Room room = room();
    User author = user("uid-comment-cross-item");
    roomMemberRepository.save(new RoomMember(room, author));
    ArchiveItem itemA = item(room, author);
    ArchiveItem itemB = item(room, author);
    ArchiveCommentResponse commentOnA =
        archiveCommentService.createComment(
            author.getId(), room.getId(), itemA.getId(), new CreateArchiveCommentRequest("A의 댓글"));

    ApiException updateEx =
        catchThrowableOfType(
            () ->
                archiveCommentService.updateComment(
                    author.getId(),
                    room.getId(),
                    itemB.getId(),
                    commentOnA.id(),
                    new UpdateArchiveCommentRequest("잘못된 접근")),
            ApiException.class);
    ApiException deleteEx =
        catchThrowableOfType(
            () ->
                archiveCommentService.deleteComment(
                    author.getId(), room.getId(), itemB.getId(), commentOnA.id()),
            ApiException.class);

    assertThat(updateEx).isInstanceOf(ArchiveCommentNotFoundException.class);
    assertThat(deleteEx).isInstanceOf(ArchiveCommentNotFoundException.class);
  }

  /** 탈퇴한 작성자(author null)의 댓글은 본인 확인이 불가능해 아무도 수정·삭제할 수 없다. */
  @Test
  void commentFromDeletedAuthorCannotBeEditedByAnyone() {
    Room room = room();
    User author = user("uid-comment-edit-deleted-author");
    roomMemberRepository.save(new RoomMember(room, author));
    ArchiveItem item = item(room, author);
    ArchiveCommentResponse created =
        archiveCommentService.createComment(
            author.getId(), room.getId(), item.getId(), new CreateArchiveCommentRequest("탈퇴 전 댓글"));
    roomMemberRepository.deleteById(new RoomMemberId(room.getId(), author.getId()));
    userRepository.deleteById(author.getId());
    User stillMember = user("uid-comment-edit-still-member");
    roomMemberRepository.save(new RoomMember(room, stillMember));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveCommentService.updateComment(
                    stillMember.getId(),
                    room.getId(),
                    item.getId(),
                    created.id(),
                    new UpdateArchiveCommentRequest("시도")),
            ApiException.class);

    assertThat(ex).isInstanceOf(NotCommentAuthorException.class);
  }

  @Test
  void deleteRemovesCommentAndDecrementsCount() {
    Room room = room();
    User author = user("uid-comment-delete");
    roomMemberRepository.save(new RoomMember(room, author));
    ArchiveItem item = item(room, author);
    ArchiveCommentResponse created =
        archiveCommentService.createComment(
            author.getId(), room.getId(), item.getId(), new CreateArchiveCommentRequest("지울 댓글"));

    archiveCommentService.deleteComment(author.getId(), room.getId(), item.getId(), created.id());

    List<ArchiveCommentResponse> comments =
        archiveCommentService.listComments(author.getId(), room.getId(), item.getId());
    assertThat(comments).isEmpty();
  }
}
