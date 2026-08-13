package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.activity.dto.ActivityResponse;
import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.archive.client.AiEmbeddingClient;
import com.nomara.modi.server.domain.archive.dto.ArchiveFolderItemsResponse;
import com.nomara.modi.server.domain.archive.dto.ArchiveItemDetailResponse;
import com.nomara.modi.server.domain.archive.dto.ArchiveItemResponse;
import com.nomara.modi.server.domain.archive.dto.CreateArchiveItemRequest;
import com.nomara.modi.server.domain.archive.dto.CreateSharedArchiveItemRequest;
import com.nomara.modi.server.domain.archive.dto.MoveItemFolderRequest;
import com.nomara.modi.server.domain.archive.dto.SetItemLikedRequest;
import com.nomara.modi.server.domain.archive.dto.SetItemPinnedRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateItemMemoRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateItemTagsRequest;
import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveItemComment;
import com.nomara.modi.server.domain.archive.entity.ArchiveItemTag;
import com.nomara.modi.server.domain.archive.entity.ArchiveLike;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemCommentRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemTagRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveLikeRepository;
import com.nomara.modi.server.domain.character.entity.UserActivityKind;
import com.nomara.modi.server.domain.character.repository.UserActivityRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.concurrent.Executor;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.core.task.SyncTaskExecutor;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** 아카이브 폴더 내 항목 목록(specs/0010-아카이브-탭.md, S-25-A)을 실제 Postgres+Redis(Testcontainers)로 검증한다. */
@Testcontainers
@SpringBootTest(
    webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = "spring.main.allow-bean-definition-overriding=true")
class ArchiveItemServiceTest {

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

  /**
   * 🔴 <b>크롤링·AI 를 같은 스레드에서 끝낸다</b>(2026-08-06). 인앱 등록(S-25-C)이 비동기로 바뀌면서, 등록 직후 요약·임베딩·태그를 단언하는 이
   * 클래스의 테스트들이 <b>경합</b>하게 됐다 — 가짜 AI 가 빨라서 대개 통과하지만 그건 운이고, CI 가 느린 날 빨개진다.
   *
   * <p>여기서 재는 것은 "어느 스레드에서 도는가"가 아니라 <b>저장된 결과</b>다(특히 {@code float[]} ↔ {@code real[]} 왕복). 동기로 돌려
   * 결정적으로 만든다. 비동기 자체의 동작은 {@code ArchiveCrawlRetryFlowTest} 가 따로 본다.
   */
  @TestConfiguration
  static class SyncExecutorConfig {

    @Bean(name = "archiveCrawlExecutor")
    Executor archiveCrawlExecutor() {
      return new SyncTaskExecutor();
    }
  }

  /**
   * 임베딩 클라이언트만 가짜로 채운다. 태깅·요약은 <b>일부러 비워 둔 채로</b> 둔다 — 이 클래스의 다른 테스트들이 "AI가 없어도 등록은 된다"를 그 부재로 검증하고
   * 있기 때문이다.
   *
   * <p>임베딩만 채우는 이유는 <b>{@code float[]} ↔ {@code real[]} 왕복이 여기서만 증명되기</b> 때문이다. {@code
   * SchemaValidationTest}는 컬럼 타입이 맞는지만 보고 값을 쓰고 읽지는 않는다.
   *
   * <p>{@code EMBED_FAILS} 문구가 든 텍스트에 예외를 던져 "임베딩이 실패해도 자료는 남는다"까지 같은 컨텍스트에서 검증한다.
   */
  @TestConfiguration
  static class FakeEmbeddingClientConfig {

    static final String FAIL_MARKER = "EMBED_FAILS";

    @Bean
    AiEmbeddingClient aiEmbeddingClient() {
      return text -> {
        if (text.contains(FAIL_MARKER)) {
          throw new IllegalStateException("gateway down");
        }
        float[] vector = new float[EMBEDDING_DIMENSIONS];
        for (int i = 0; i < vector.length; i++) {
          vector[i] = i / 1000f;
        }
        return vector;
      };
    }
  }

  /** {@code text-embedding-3-small}의 실제 차원(2026-08-01 게이트웨이 실측). 왕복 검증을 실물과 같은 크기로 한다. */
  private static final int EMBEDDING_DIMENSIONS = 1536;

  @Autowired private TestRestTemplate restTemplate;
  @Autowired private ArchiveItemService archiveItemService;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;
  @Autowired private ArchiveFolderRepository archiveFolderRepository;
  @Autowired private ArchiveItemRepository archiveItemRepository;
  @Autowired private ArchiveItemTagRepository archiveItemTagRepository;
  @Autowired private ArchiveLikeRepository archiveLikeRepository;
  @Autowired private ArchiveItemCommentRepository archiveItemCommentRepository;
  @Autowired private ActivityService activityService;
  @Autowired private UserActivityRepository userActivityRepository;

  private static int counter = 0;

  private Room room() {
    return roomRepository.save(
        new Room(
            "방-" + (++counter), null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10)));
  }

  private User user(String uid) {
    return userRepository.save(new User(uid, uid, null));
  }

  @Test
  void listWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.getForEntity("/rooms/1/archive/folders/1/items", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void listReturnsItemsNewestFirstWithFolderName() {
    Room room = room();
    User member = user("uid-item-a");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "링크 모음"));
    archiveItemRepository.save(
        new ArchiveItem(folder, room, "먼저 등록", null, "본문1", null, null, member));
    archiveItemRepository.save(
        new ArchiveItem(folder, room, "나중 등록", null, "본문2", null, null, member));

    ArchiveFolderItemsResponse response =
        archiveItemService.listItems(member.getId(), room.getId(), folder.getId());

    assertThat(response.folderName()).isEqualTo("링크 모음");
    assertThat(response.items())
        .extracting(ArchiveItemResponse::title)
        .containsExactly("나중 등록", "먼저 등록");
  }

  /** 핀 고정 항목은 최신순보다 앞선다. */
  @Test
  void listReturnsPinnedItemBeforeNewerUnpinnedItem() {
    Room room = room();
    User member = user("uid-item-pin-order");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem older =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "먼저 등록(핀)", null, "본문1", null, null, member));
    archiveItemRepository.save(
        new ArchiveItem(folder, room, "나중 등록(비핀)", null, "본문2", null, null, member));
    archiveItemService.setPinned(
        member.getId(), room.getId(), older.getId(), new SetItemPinnedRequest(true));

    ArchiveFolderItemsResponse response =
        archiveItemService.listItems(member.getId(), room.getId(), folder.getId());

    assertThat(response.items())
        .extracting(ArchiveItemResponse::title)
        .containsExactly("먼저 등록(핀)", "나중 등록(비핀)");
  }

  @Test
  void listReturnsAccurateTagsAndLikeCountPerItem() {
    Room room = room();
    User member = user("uid-item-b");
    User liker = user("uid-item-b-liker");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem tagged =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "태그+좋아요 있음", null, "본문", null, null, member));
    ArchiveItem bare =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "아무것도 없음", null, "본문", null, null, member));
    archiveItemTagRepository.save(new ArchiveItemTag(tagged, "여행"));
    archiveItemTagRepository.save(new ArchiveItemTag(tagged, "맛집"));
    archiveLikeRepository.save(new ArchiveLike(tagged, member));
    archiveLikeRepository.save(new ArchiveLike(tagged, liker));

    ArchiveFolderItemsResponse response =
        archiveItemService.listItems(member.getId(), room.getId(), folder.getId());

    ArchiveItemResponse taggedResponse =
        response.items().stream()
            .filter(i -> i.id().equals(tagged.getId()))
            .findFirst()
            .orElseThrow();
    ArchiveItemResponse bareResponse =
        response.items().stream()
            .filter(i -> i.id().equals(bare.getId()))
            .findFirst()
            .orElseThrow();

    assertThat(taggedResponse.tags()).containsExactlyInAnyOrder("여행", "맛집");
    assertThat(taggedResponse.likeCount()).isEqualTo(2L);
    assertThat(bareResponse.tags()).isEmpty();
    assertThat(bareResponse.likeCount()).isEqualTo(0L);
  }

  @Test
  void emptyFolderReturnsEmptyListWithFolderName() {
    Room room = room();
    User member = user("uid-item-c");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "빈 폴더"));

    ArchiveFolderItemsResponse response =
        archiveItemService.listItems(member.getId(), room.getId(), folder.getId());

    assertThat(response.folderName()).isEqualTo("빈 폴더");
    assertThat(response.items()).isEmpty();
  }

  @Test
  void nonMemberCannotListItems() {
    Room room = room();
    User member = user("uid-item-owner");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ApiException ex =
        catchThrowableOfType(
            () -> archiveItemService.listItems("uid-item-outsider", room.getId(), folder.getId()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void listingItemsOfFolderFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-item-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    ArchiveFolder folderOfRoomB = archiveFolderRepository.save(new ArchiveFolder(roomB, "남의 폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.listItems(member.getId(), roomA.getId(), folderOfRoomB.getId()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void getDetailReturnsTagsLikeCountAndLikedByMe() {
    Room room = room();
    User member = user("uid-detail-a");
    User liker = user("uid-detail-a-liker");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(
                folder, room, "상세 항목", "https://example.com", "본문", "출처", null, member));
    archiveItemTagRepository.save(new ArchiveItemTag(item, "여행"));
    archiveLikeRepository.save(new ArchiveLike(item, liker));

    ArchiveItemDetailResponse detail =
        archiveItemService.getDetail(member.getId(), room.getId(), item.getId());

    assertThat(detail.folderId()).isEqualTo(folder.getId());
    assertThat(detail.title()).isEqualTo("상세 항목");
    assertThat(detail.tags()).containsExactly("여행");
    assertThat(detail.likeCount()).isEqualTo(1L);
    assertThat(detail.likedByMe()).isFalse();
    assertThat(detail.commentCount()).isEqualTo(0L);
  }

  /** 댓글 수(2026-08-08, docs/backend/archive-comments-handoff.md) — 목록을 따로 안 불러도 상세에 바로 실린다. */
  @Test
  void getDetailReflectsCommentCount() {
    Room room = room();
    User member = user("uid-detail-comment-count");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "댓글 있는 항목", null, "본문", null, null, member));
    archiveItemCommentRepository.save(new ArchiveItemComment(item, member, "첫 댓글"));
    archiveItemCommentRepository.save(new ArchiveItemComment(item, member, "두번째 댓글"));

    ArchiveItemDetailResponse detail =
        archiveItemService.getDetail(member.getId(), room.getId(), item.getId());

    assertThat(detail.commentCount()).isEqualTo(2L);
  }

  /**
   * S-25-B 리디자인(2026-08-08) — 상세 화면 앱바가 폴더 이름을, 사진 우하단 아바타가 등록자를 그린다. 라우트가 {@code
   * /archive/item/:id}라 앱이 둘 다 넘겨받지 못하므로 상세 응답이 실어 줘야 한다.
   */
  @Test
  void getDetailCarriesFolderNameAndCreator() {
    Room room = room();
    User member = user("uid-detail-creator");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "여행 링크 모음"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "항목", "https://example.com", "본문", null, null, member));

    ArchiveItemDetailResponse detail =
        archiveItemService.getDetail(member.getId(), room.getId(), item.getId());

    assertThat(detail.folderName()).isEqualTo("여행 링크 모음");
    assertThat(detail.createdBy()).isNotNull();
    assertThat(detail.createdBy().userId()).isEqualTo(member.getId());
    assertThat(detail.createdBy().nickname()).isEqualTo(member.getNickname());
  }

  /**
   * 🔴 등록자가 없는 자료도 <b>정상 조회된다.</b> 탈퇴하면 자료는 방에 남고 작성자만 {@code null}이 되고({@code
   * V9__account_deletion_cascades.sql}), {@code created_by} 컬럼이 생기기 전({@code V19}) 등록분은 애초에 비어 있다.
   *
   * <p>이 테스트가 지키는 것은 {@code createdBy}가 {@code null}이라는 사실보다 <b>항목 자체가 사라지지 않는다</b>는 쪽이다 — {@code
   * ArchiveItemRepository.findForDetailById}의 fetch 를 {@code left join}에서 inner 로 바꾸면 여기서 404가 난다.
   */
  @Test
  void getDetailWorksForItemWithoutCreator() {
    Room room = room();
    User member = user("uid-detail-no-creator");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "작성자 없는 항목", null, "본문", null, null, null));

    ArchiveItemDetailResponse detail =
        archiveItemService.getDetail(member.getId(), room.getId(), item.getId());

    assertThat(detail.title()).isEqualTo("작성자 없는 항목");
    assertThat(detail.createdBy()).isNull();
    assertThat(detail.folderName()).isEqualTo("폴더");
  }

  /** 협업 캐릭터(specs/0016) 활동성 신호 — 자료 상세 조회 시 ARCHIVE_ITEM_VIEW 로그가 남는다. */
  @Test
  void getDetailRecordsArchiveItemViewActivity() {
    Room room = room();
    User member = user("uid-detail-view-log");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "항목", null, "본문", null, null, member));

    archiveItemService.getDetail(member.getId(), room.getId(), item.getId());

    assertThat(
            userActivityRepository.countByUserIdAndKindAndCreatedAtAfter(
                member.getId(), UserActivityKind.ARCHIVE_ITEM_VIEW, Instant.now().minusSeconds(60)))
        .isEqualTo(1);
  }

  @Test
  void settingPinnedTogglesPinState() {
    Room room = room();
    User member = user("uid-detail-pin");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "항목", null, "본문", null, null, member));

    ArchiveItemDetailResponse pinned =
        archiveItemService.setPinned(
            member.getId(), room.getId(), item.getId(), new SetItemPinnedRequest(true));
    assertThat(pinned.pinned()).isTrue();

    ArchiveItemDetailResponse unpinned =
        archiveItemService.setPinned(
            member.getId(), room.getId(), item.getId(), new SetItemPinnedRequest(false));
    assertThat(unpinned.pinned()).isFalse();
  }

  @Test
  void settingLikedIsIdempotentInBothDirections() {
    Room room = room();
    User member = user("uid-detail-like");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "항목", null, "본문", null, null, member));

    archiveItemService.setLiked(
        member.getId(), room.getId(), item.getId(), new SetItemLikedRequest(true));
    ArchiveItemDetailResponse likedTwice =
        archiveItemService.setLiked(
            member.getId(), room.getId(), item.getId(), new SetItemLikedRequest(true));
    assertThat(likedTwice.likeCount()).isEqualTo(1L);
    assertThat(likedTwice.likedByMe()).isTrue();

    ArchiveItemDetailResponse unliked =
        archiveItemService.setLiked(
            member.getId(), room.getId(), item.getId(), new SetItemLikedRequest(false));
    assertThat(unliked.likeCount()).isEqualTo(0L);
    assertThat(unliked.likedByMe()).isFalse();
  }

  @Test
  void movingToFolderInSameRoomSucceedsButOtherRoomFolderIsRejected() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-detail-move");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    ArchiveFolder origin = archiveFolderRepository.save(new ArchiveFolder(roomA, "원래 폴더"));
    ArchiveFolder destination = archiveFolderRepository.save(new ArchiveFolder(roomA, "이동할 폴더"));
    ArchiveFolder folderOfRoomB = archiveFolderRepository.save(new ArchiveFolder(roomB, "남의 폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(origin, roomA, "항목", null, "본문", null, null, member));

    ArchiveItemDetailResponse moved =
        archiveItemService.moveToFolder(
            member.getId(),
            roomA.getId(),
            item.getId(),
            new MoveItemFolderRequest(destination.getId()));
    assertThat(moved.folderId()).isEqualTo(destination.getId());

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.moveToFolder(
                    member.getId(),
                    roomA.getId(),
                    item.getId(),
                    new MoveItemFolderRequest(folderOfRoomB.getId())),
            ApiException.class);
    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void updatingTagsReplacesAllAndDedupes() {
    Room room = room();
    User member = user("uid-detail-tags");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "항목", null, "본문", null, null, member));
    archiveItemTagRepository.save(new ArchiveItemTag(item, "옛날태그"));

    ArchiveItemDetailResponse updated =
        archiveItemService.updateTags(
            member.getId(),
            room.getId(),
            item.getId(),
            new UpdateItemTagsRequest(List.of("여행", "맛집", "여행")));

    assertThat(updated.tags()).containsExactlyInAnyOrder("여행", "맛집");
  }

  /** 홈 활동 피드(2026-08-06, docs/backend/home-activity-feed.md) ARCHIVE_ADDED. */
  @Test
  void creatingTextItemRecordsArchiveAddedActivityWithFolderNameAsTarget() {
    Room room = room();
    User member = user("uid-archive-activity");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "여행 폴더"));

    archiveItemService.createItem(
        member.getId(),
        room.getId(),
        folder.getId(),
        new CreateArchiveItemRequest(null, "본문", null, null, null));

    assertThat(activityService.getRecentActivities(room))
        .anySatisfy(
            a -> {
              assertThat(a.type()).isEqualTo("ARCHIVE_ADDED");
              assertThat(a.actorUserId()).isEqualTo(member.getId());
              assertThat(a.targetName()).isEqualTo("여행 폴더");
            });
  }

  /** 폴더 미지정 등록(백엔드 요청, 2026-08-07) — "기본" 폴더가 없으면 새로 만들어 넣는다. */
  @Test
  void createItemInDefaultFolderCreatesDefaultFolderWhenMissing() {
    Room room = room();
    User member = user("uid-default-folder-new");
    roomMemberRepository.save(new RoomMember(room, member));

    ArchiveItemDetailResponse response =
        archiveItemService.createItemInDefaultFolder(
            member.getId(),
            room.getId(),
            new CreateArchiveItemRequest(null, "본문", null, null, null));

    ArchiveFolder folder = archiveFolderRepository.findById(response.folderId()).orElseThrow();
    assertThat(folder.getName()).isEqualTo(ArchiveFolder.DEFAULT_FOLDER_NAME);
  }

  /** 이미 "기본" 폴더가 있으면 재사용하고 새로 만들지 않는다. */
  @Test
  void createItemInDefaultFolderReusesExistingDefaultFolder() {
    Room room = room();
    User member = user("uid-default-folder-reuse");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder existingDefault =
        archiveFolderRepository.save(new ArchiveFolder(room, ArchiveFolder.DEFAULT_FOLDER_NAME));

    ArchiveItemDetailResponse response =
        archiveItemService.createItemInDefaultFolder(
            member.getId(),
            room.getId(),
            new CreateArchiveItemRequest(null, "본문", null, null, null));

    assertThat(response.folderId()).isEqualTo(existingDefault.getId());
    assertThat(archiveFolderRepository.findByRoomIdOrderByCreatedAtAsc(room.getId())).hasSize(1);
  }

  /** "기본"이 아닌 다른 폴더만 있어도 "기본"을 새로 만들어 넣는다(다른 폴더는 그대로 둔다). */
  @Test
  void createItemInDefaultFolderCreatesDefaultEvenWhenOtherFoldersExist() {
    Room room = room();
    User member = user("uid-default-folder-alongside");
    roomMemberRepository.save(new RoomMember(room, member));
    archiveFolderRepository.save(new ArchiveFolder(room, "여행"));

    ArchiveItemDetailResponse response =
        archiveItemService.createItemInDefaultFolder(
            member.getId(),
            room.getId(),
            new CreateArchiveItemRequest(null, "본문", null, null, null));

    ArchiveFolder folder = archiveFolderRepository.findById(response.folderId()).orElseThrow();
    assertThat(folder.getName()).isEqualTo(ArchiveFolder.DEFAULT_FOLDER_NAME);
    assertThat(archiveFolderRepository.findByRoomIdOrderByCreatedAtAsc(room.getId()))
        .extracting(ArchiveFolder::getName)
        .containsExactlyInAnyOrder("여행", ArchiveFolder.DEFAULT_FOLDER_NAME);
  }

  /** ARCHIVE_LIKE_MILESTONE — 5의 배수에서만 기록되고 actor는 자료 작성자다. */
  @Test
  void archiveLikeMilestoneRecordsAtFiveWithAuthorAsActor() {
    Room room = room();
    User author = user("uid-archive-like-author");
    roomMemberRepository.save(new RoomMember(room, author));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "인기 자료", null, "본문", null, null, author));

    for (int i = 0; i < 5; i++) {
      User liker = user("uid-archive-like-liker-" + i);
      roomMemberRepository.save(new RoomMember(room, liker));
      archiveItemService.setLiked(
          liker.getId(), room.getId(), item.getId(), new SetItemLikedRequest(true));
    }

    List<ActivityResponse> milestones =
        activityService.getRecentActivities(room).stream()
            .filter(a -> a.type().equals("ARCHIVE_LIKE_MILESTONE"))
            .toList();
    assertThat(milestones).hasSize(1);
    assertThat(milestones.get(0).actorUserId()).isEqualTo(author.getId());
    assertThat(milestones.get(0).count()).isEqualTo(5);
    assertThat(milestones.get(0).targetName()).isEqualTo("인기 자료");
  }

  @Test
  void creatingItemWithMemoIncludesItInDetail() {
    Room room = room();
    User member = user("uid-create-memo");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItemDetailResponse created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest(null, "메모가 붙는 텍스트 등록", "다음에 다시 읽어볼 것", null, null));

    assertThat(created.memo()).isEqualTo("다음에 다시 읽어볼 것");
  }

  @Test
  void creatingItemWithMemoTooLongIsRejected() {
    Room room = room();
    User member = user("uid-create-memo-toolong");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    String tooLongMemo = "메".repeat(501);

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createItem(
                    member.getId(),
                    room.getId(),
                    folder.getId(),
                    new CreateArchiveItemRequest(null, "본문", tooLongMemo, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void updatingMemoStoresTheValue() {
    Room room = room();
    User member = user("uid-detail-memo");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "항목", null, "본문", null, null, member));

    ArchiveItemDetailResponse updated =
        archiveItemService.updateMemo(
            member.getId(), room.getId(), item.getId(), new UpdateItemMemoRequest("새 메모"));

    assertThat(updated.memo()).isEqualTo("새 메모");
  }

  @Test
  void updatingMemoWithBlankClearsIt() {
    Room room = room();
    User member = user("uid-detail-memo-clear");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "항목", null, "본문", null, null, member));
    item.editMemo("지워질 메모");
    archiveItemRepository.save(item);

    ArchiveItemDetailResponse updated =
        archiveItemService.updateMemo(
            member.getId(), room.getId(), item.getId(), new UpdateItemMemoRequest("   "));

    assertThat(updated.memo()).isNull();
  }

  @Test
  void updatingMemoTooLongIsRejected() {
    Room room = room();
    User member = user("uid-detail-memo-toolong");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "항목", null, "본문", null, null, member));
    String tooLongMemo = "메".repeat(501);

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.updateMemo(
                    member.getId(),
                    room.getId(),
                    item.getId(),
                    new UpdateItemMemoRequest(tooLongMemo)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void nonMemberCannotUpdateMemo() {
    Room room = room();
    User member = user("uid-detail-memo-owner");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "항목", null, "본문", null, null, member));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.updateMemo(
                    "uid-detail-memo-outsider",
                    room.getId(),
                    item.getId(),
                    new UpdateItemMemoRequest("메모")),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void deletingItemCascadesToItsTagsAndLikes() {
    Room room = room();
    User member = user("uid-detail-delete");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "삭제될 항목", null, "본문", null, null, member));
    archiveItemTagRepository.save(new ArchiveItemTag(item, "태그"));
    archiveLikeRepository.save(new ArchiveLike(item, member));

    archiveItemService.deleteItem(member.getId(), room.getId(), item.getId());

    assertThat(archiveItemRepository.findById(item.getId())).isEmpty();
    assertThat(archiveItemTagRepository.findByItemId(item.getId())).isEmpty();
    assertThat(archiveLikeRepository.countByItemId(item.getId())).isZero();
  }

  @Test
  void gettingDetailOfItemFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-detail-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    ArchiveFolder folderOfRoomB = archiveFolderRepository.save(new ArchiveFolder(roomB, "남의 폴더"));
    ArchiveItem itemOfRoomB =
        archiveItemRepository.save(
            new ArchiveItem(folderOfRoomB, roomB, "남의 항목", null, "본문", null, null, member));

    ApiException ex =
        catchThrowableOfType(
            () -> archiveItemService.getDetail(member.getId(), roomA.getId(), itemOfRoomB.getId()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void nonMemberCannotPinItem() {
    Room room = room();
    User member = user("uid-detail-owner");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "항목", null, "본문", null, null, member));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.setPinned(
                    "uid-detail-outsider",
                    room.getId(),
                    item.getId(),
                    new SetItemPinnedRequest(true)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void creatingItemFromTextSucceedsWithGeneratedTitleAndNoTagsWhenAiUnavailable() {
    Room room = room();
    User member = user("uid-create-text");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItemDetailResponse created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest(null, "테스트용 순수 텍스트 등록 본문입니다", null, null, null));

    assertThat(created.title()).isEqualTo("테스트용 순수 텍스트 등록 본문입니다");
    assertThat(created.bodyText()).isEqualTo("테스트용 순수 텍스트 등록 본문입니다");
    assertThat(created.url()).isNull();
    assertThat(created.folderId()).isEqualTo(folder.getId());
    // 테스트 환경엔 OPENAI_API_KEY가 없어 AiTaggingClient 빈 자체가 없다 — AI 실패 시 폴백(태그 없이 등록
    // 진행, specs/OPEN.md 확정)이 모킹 없이 그대로 검증된다.
    assertThat(created.tags()).isEmpty();
    assertThat(archiveItemRepository.findById(created.id())).isPresent();
    // AiSummaryClient도 같은 이유로 없다 — 요약 없이 등록이 끝나야 한다.
    assertThat(archiveItemRepository.findById(created.id()).orElseThrow().getSummary()).isNull();
  }

  @Test
  void creatingItemStoresTheEmbeddingVector() {
    // real[] 컬럼에 값이 실제로 쓰이고 float[] 로 되읽히는지 — 이 왕복을 증명하는 테스트는 이것뿐이다
    // (SchemaValidationTest 는 컬럼 타입만 본다). 요약이 없으므로 본문이 임베딩 입력이 된다.
    Room room = room();
    User member = user("uid-embed-store");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItemDetailResponse created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest(null, "강릉 여행 코스를 정리한 글이다", null, null, null));

    float[] stored = archiveItemRepository.findById(created.id()).orElseThrow().getEmbedding();
    assertThat(stored).hasSize(EMBEDDING_DIMENSIONS);
    assertThat(stored[1]).isEqualTo(0.001f);
    assertThat(stored[EMBEDDING_DIMENSIONS - 1]).isEqualTo(1.535f);
  }

  @Test
  void itemAndBodySurviveWhenTheEmbeddingCallFails() {
    // 임베딩은 파생 데이터다 — 실패하면 NULL 로 남을 뿐 사용자의 자료를 잃으면 안 된다.
    // (그 자료는 나중에 유사도 축에서만 빠지고 최근성·핀 축으로 후보에 남는다 — ai/docs/DECISIONS.md)
    Room room = room();
    User member = user("uid-embed-fail");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItemDetailResponse created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest(
                null, FakeEmbeddingClientConfig.FAIL_MARKER + " 가 포함된 본문", null, null, null));

    ArchiveItem stored = archiveItemRepository.findById(created.id()).orElseThrow();
    assertThat(stored.getEmbedding()).isNull();
    assertThat(stored.getBodyText()).contains(FakeEmbeddingClientConfig.FAIL_MARKER);
    assertThat(stored.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
  }

  @Test
  void creatingItemGeneratesTruncatedTitleForLongText() {
    Room room = room();
    User member = user("uid-create-long-text");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    String longText = "가".repeat(80);

    ArchiveItemDetailResponse created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest(null, longText, null, null, null));

    assertThat(created.title()).hasSize(51).endsWith("…");
    assertThat(created.bodyText()).isEqualTo(longText);
  }

  @Test
  void creatingItemWithNeitherUrlNorTextIsRejected() {
    Room room = room();
    User member = user("uid-create-neither");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createItem(
                    member.getId(),
                    room.getId(),
                    folder.getId(),
                    new CreateArchiveItemRequest(null, null, null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void creatingItemWithBothUrlAndTextIsRejected() {
    Room room = room();
    User member = user("uid-create-both");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createItem(
                    member.getId(),
                    room.getId(),
                    folder.getId(),
                    new CreateArchiveItemRequest("https://example.com", "본문", null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void creatingItemWithImageUrlSucceedsImmediatelyWithoutCrawlingOrAi() {
    // 폴더 직접 업로드 이미지(V28) — 크롤링·AI 태깅/요약/임베딩을 타지 않고 곧바로 DONE이어야 한다
    // (투두 첨부 이미지와 같은 원칙, docs/backend/todo-image-archive-handoff.md).
    Room room = room();
    User member = user("uid-create-image");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItemDetailResponse created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest(
                null, null, null, "https://cdn.example.com/photo.jpg", "여행 사진"));

    assertThat(created.title()).isEqualTo("여행 사진");
    assertThat(created.imageUrl()).isEqualTo("https://cdn.example.com/photo.jpg");
    assertThat(created.url()).isNull();
    assertThat(created.bodyText()).isNull();
    assertThat(created.crawlStatus()).isEqualTo("DONE");
    ArchiveItem stored = archiveItemRepository.findById(created.id()).orElseThrow();
    assertThat(stored.getSummary()).isNull();
    assertThat(stored.getEmbedding()).isNull();
  }

  @Test
  void creatingItemWithImageUrlDefaultsTitleWhenBlank() {
    Room room = room();
    User member = user("uid-create-image-no-title");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItemDetailResponse created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest(
                null, null, null, "https://cdn.example.com/photo.jpg", null));

    assertThat(created.title()).isEqualTo("사진");
  }

  @Test
  void creatingItemWithUrlAndImageUrlBothIsRejected() {
    Room room = room();
    User member = user("uid-create-url-and-image");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createItem(
                    member.getId(),
                    room.getId(),
                    folder.getId(),
                    new CreateArchiveItemRequest(
                        "https://example.com",
                        null,
                        null,
                        "https://cdn.example.com/photo.jpg",
                        null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void nonMemberCannotCreateItem() {
    Room room = room();
    User member = user("uid-create-owner");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createItem(
                    "uid-create-outsider",
                    room.getId(),
                    folder.getId(),
                    new CreateArchiveItemRequest(null, "본문", null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void creatingItemInFolderFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-create-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    ArchiveFolder folderOfRoomB = archiveFolderRepository.save(new ArchiveFolder(roomB, "남의 폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createItem(
                    member.getId(),
                    roomA.getId(),
                    folderOfRoomB.getId(),
                    new CreateArchiveItemRequest(null, "본문", null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void creatingItemWithNonHttpSchemeIsRejectedWithoutCreatingAnything() {
    Room room = room();
    User member = user("uid-create-scheme");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createItem(
                    member.getId(),
                    room.getId(),
                    folder.getId(),
                    new CreateArchiveItemRequest("ftp://example.com/file", null, null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
    assertThat(archiveItemRepository.findByFolderIdOrderByCreatedAtDesc(folder.getId())).isEmpty();
  }

  @Test
  void creatingItemWithLoopbackUrlIsRejectedBySsrfGuard() {
    Room room = room();
    User member = user("uid-create-loopback");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createItem(
                    member.getId(),
                    room.getId(),
                    folder.getId(),
                    new CreateArchiveItemRequest(
                        "http://127.0.0.1:8080/rooms", null, null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
    assertThat(archiveItemRepository.findByFolderIdOrderByCreatedAtDesc(folder.getId())).isEmpty();
  }

  @Test
  void creatingItemWithIpv6UniqueLocalUrlIsRejectedBySsrfGuard() {
    // JDK의 InetAddress.isSiteLocalAddress()는 폐기된 IPv6 fec0::/10만 인식하고 실제로 쓰이는
    // RFC 4193 ULA(fc00::/7)는 별도 체크가 필요하다 — JsoupUrlCrawler.isIpv6UniqueLocal 회귀 테스트.
    Room room = room();
    User member = user("uid-create-ula");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createItem(
                    member.getId(),
                    room.getId(),
                    folder.getId(),
                    new CreateArchiveItemRequest("http://[fd00::1]/", null, null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
    assertThat(archiveItemRepository.findByFolderIdOrderByCreatedAtDesc(folder.getId())).isEmpty();
  }

  @Test
  void creatingItemWithOverlongTextIsRejected() {
    Room room = room();
    User member = user("uid-create-toolong");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    String tooLong = "a".repeat(50_001);

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createItem(
                    member.getId(),
                    room.getId(),
                    folder.getId(),
                    new CreateArchiveItemRequest(null, tooLong, null, null, null)),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void creatingSharedItemFromTextIsDoneImmediately() {
    Room room = room();
    User member = user("uid-shared-text");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItemDetailResponse created =
        archiveItemService.createSharedItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateSharedArchiveItemRequest("공유된 텍스트 제목", null, "공유된 텍스트 본문"));

    // 🔴 2026-08-06 개정: 텍스트는 **등록 즉시 DONE** 이다. 본문이 이 시점에 이미 완성이라
    // "분석 중" 배지를 띄울 이유가 없다 — 다 적어 놓은 메모가 처리 중인 것처럼 보였다(실사용 확인).
    // 태깅·임베딩은 여전히 비동기로 뒤에서 돈다(5초 타임아웃 사고를 되돌리지 않는다). 바뀐 것은 상태뿐.
    assertThat(created.crawlStatus()).isEqualTo("DONE");
    assertThat(created.title()).isEqualTo("공유된 텍스트 제목");
    assertThat(created.bodyText()).isEqualTo("공유된 텍스트 본문");
    assertThat(created.tags()).isEmpty(); // 파생 데이터는 응답에 실리지 않는다(나중에 붙는다)
  }

  @Test
  void creatingSharedItemFromUrlIsPendingWithNoBodyTextUntilAsyncCrawlCompletes() {
    Room room = room();
    User member = user("uid-shared-url");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ArchiveItemDetailResponse created =
        archiveItemService.createSharedItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateSharedArchiveItemRequest(
                "공유된 링크 제목", "https://en.wikipedia.org/wiki/Kotlin", null));

    // 등록 응답은 크롤링(비동기) 완료를 기다리지 않고 즉시 PENDING으로 돌아온다 — 실제 크롤링 완료
    // 여부는 별도 스레드에서 처리되므로 자동화 테스트에서는 타이밍을 기다리지 않고 이 상태만 검증한다.
    assertThat(created.crawlStatus()).isEqualTo("PENDING");
    assertThat(created.bodyText()).isNull();
    assertThat(created.title()).isEqualTo("공유된 링크 제목");
    assertThat(archiveItemRepository.findById(created.id())).isPresent();
  }

  @Test
  void creatingSharedItemWithoutTitleIsRejected() {
    Room room = room();
    User member = user("uid-shared-notitle");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createSharedItem(
                    member.getId(),
                    room.getId(),
                    folder.getId(),
                    new CreateSharedArchiveItemRequest("", null, "본문")),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void nonMemberCannotCreateSharedItem() {
    Room room = room();
    User member = user("uid-shared-owner");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createSharedItem(
                    "uid-shared-outsider",
                    room.getId(),
                    folder.getId(),
                    new CreateSharedArchiveItemRequest("제목", null, "본문")),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void creatingSharedItemInFolderFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-shared-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    ArchiveFolder folderOfRoomB = archiveFolderRepository.save(new ArchiveFolder(roomB, "남의 폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.createSharedItem(
                    member.getId(),
                    roomA.getId(),
                    folderOfRoomB.getId(),
                    new CreateSharedArchiveItemRequest("제목", null, "본문")),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }
}
