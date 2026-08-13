package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import com.nomara.modi.server.domain.archive.dto.ArchiveFolderResponse;
import com.nomara.modi.server.domain.archive.dto.CreateArchiveFolderRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateArchiveFolderRequest;
import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
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
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/** 아카이브 폴더 CRUD(specs/0010-아카이브-탭.md, S-25)를 실제 Postgres+Redis(Testcontainers)로 검증한다. */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ArchiveFolderServiceTest {

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
  @Autowired private ArchiveFolderService archiveFolderService;
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

  @Test
  void listWithoutAuthReturnsUnauthorized() {
    var response = restTemplate.getForEntity("/rooms/1/archive/folders", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
  }

  @Test
  void createFolderThenListReturnsInCreationOrder() {
    Room room = room();
    User member = user("uid-arch-a");
    roomMemberRepository.save(new RoomMember(room, member));

    archiveFolderService.createFolder(
        member.getId(), room.getId(), new CreateArchiveFolderRequest("첫번째"));
    archiveFolderService.createFolder(
        member.getId(), room.getId(), new CreateArchiveFolderRequest("두번째"));

    List<ArchiveFolderResponse> folders =
        archiveFolderService.listFolders(member.getId(), room.getId());

    assertThat(folders).extracting(ArchiveFolderResponse::name).containsExactly("첫번째", "두번째");
  }

  @Test
  void listReturnsAccurateItemCountPerFolder() {
    Room room = room();
    User member = user("uid-arch-count");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder withItems = archiveFolderRepository.save(new ArchiveFolder(room, "자료 있는 폴더"));
    archiveFolderRepository.save(new ArchiveFolder(room, "빈 폴더"));
    archiveItemRepository.save(
        new ArchiveItem(withItems, room, "항목1", null, "본문1", null, null, member));
    archiveItemRepository.save(
        new ArchiveItem(withItems, room, "항목2", null, "본문2", null, null, member));

    List<ArchiveFolderResponse> folders =
        archiveFolderService.listFolders(member.getId(), room.getId());

    assertThat(folders)
        .extracting(ArchiveFolderResponse::name, ArchiveFolderResponse::itemCount)
        .containsExactlyInAnyOrder(
            org.assertj.core.groups.Tuple.tuple("자료 있는 폴더", 2L),
            org.assertj.core.groups.Tuple.tuple("빈 폴더", 0L));
  }

  @Test
  void listReturnsMostRecentThumbnailPerFolder() throws InterruptedException {
    Room room = room();
    User member = user("uid-arch-thumb-a");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    archiveItemRepository.save(
        new ArchiveItem(folder, room, "항목1", null, "본문1", null, "thumb-1.png", member));
    Thread.sleep(5);
    archiveItemRepository.save(
        new ArchiveItem(folder, room, "항목2", null, "본문2", null, "thumb-2.png", member));

    List<ArchiveFolderResponse> folders =
        archiveFolderService.listFolders(member.getId(), room.getId());

    assertThat(folders).extracting(ArchiveFolderResponse::thumbnail).containsExactly("thumb-2.png");
  }

  @Test
  void listSkipsMostRecentItemWithoutThumbnailAndFallsBackToOlderOne() throws InterruptedException {
    Room room = room();
    User member = user("uid-arch-thumb-b");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    archiveItemRepository.save(
        new ArchiveItem(folder, room, "이미지 항목", null, "본문1", null, "thumb-old.png", member));
    Thread.sleep(5);
    archiveItemRepository.save(
        new ArchiveItem(folder, room, "텍스트 메모", null, "썸네일 없는 최신 항목", null, null, member));

    List<ArchiveFolderResponse> folders =
        archiveFolderService.listFolders(member.getId(), room.getId());

    assertThat(folders)
        .extracting(ArchiveFolderResponse::thumbnail)
        .containsExactly("thumb-old.png");
  }

  @Test
  void listReturnsNullThumbnailWhenNoItemHasOne() {
    Room room = room();
    User member = user("uid-arch-thumb-c");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "썸네일 없는 폴더"));
    archiveItemRepository.save(
        new ArchiveItem(folder, room, "텍스트만", null, "본문", null, null, member));

    List<ArchiveFolderResponse> folders =
        archiveFolderService.listFolders(member.getId(), room.getId());

    assertThat(folders).extracting(ArchiveFolderResponse::thumbnail).containsExactly((String) null);
  }

  @Test
  void listReturnsNullThumbnailForEmptyFolder() {
    Room room = room();
    User member = user("uid-arch-thumb-d");
    roomMemberRepository.save(new RoomMember(room, member));
    archiveFolderRepository.save(new ArchiveFolder(room, "빈 폴더"));

    List<ArchiveFolderResponse> folders =
        archiveFolderService.listFolders(member.getId(), room.getId());

    assertThat(folders).extracting(ArchiveFolderResponse::thumbnail).containsExactly((String) null);
  }

  @Test
  void thumbnailFromAnotherRoomDoesNotLeakIntoThisRoomsFolder() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-arch-thumb-cross");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    ArchiveFolder folderInA = archiveFolderRepository.save(new ArchiveFolder(roomA, "A방 폴더"));
    ArchiveFolder folderInB = archiveFolderRepository.save(new ArchiveFolder(roomB, "B방 폴더"));
    archiveItemRepository.save(
        new ArchiveItem(folderInB, roomB, "B방 항목", null, "본문", null, "thumb-b.png", member));

    List<ArchiveFolderResponse> foldersInA =
        archiveFolderService.listFolders(member.getId(), roomA.getId());

    assertThat(foldersInA)
        .extracting(ArchiveFolderResponse::id, ArchiveFolderResponse::thumbnail)
        .containsExactly(org.assertj.core.groups.Tuple.tuple(folderInA.getId(), null));
  }

  @Test
  void renameFolderUpdatesName() {
    Room room = room();
    User member = user("uid-arch-b");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolderResponse created =
        archiveFolderService.createFolder(
            member.getId(), room.getId(), new CreateArchiveFolderRequest("원래이름"));

    ArchiveFolderResponse renamed =
        archiveFolderService.renameFolder(
            member.getId(), room.getId(), created.id(), new UpdateArchiveFolderRequest("바뀐이름"));

    assertThat(renamed.name()).isEqualTo("바뀐이름");
  }

  @Test
  void deletingFolderCascadesToItsItems() {
    Room room = room();
    User member = user("uid-arch-c");
    roomMemberRepository.save(new RoomMember(room, member));
    // 마지막 남은 폴더는 삭제가 막히므로(백엔드 요청, 2026-08-07) 남을 폴더를 하나 더 둔다.
    archiveFolderRepository.save(new ArchiveFolder(room, "남는 폴더"));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "삭제될 폴더"));
    ArchiveItem item =
        archiveItemRepository.save(
            new ArchiveItem(folder, room, "삭제될 항목", null, "본문", null, null, member));

    archiveFolderService.deleteFolder(member.getId(), room.getId(), folder.getId());

    assertThat(archiveFolderRepository.findById(folder.getId())).isEmpty();
    assertThat(archiveItemRepository.findById(item.getId())).isEmpty();
  }

  /** 방마다 폴더 최소 1개 보장(백엔드 요청, 2026-08-07). */
  @Test
  void deletingTheLastFolderInRoomIsRejected() {
    Room room = room();
    User member = user("uid-arch-last-folder");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder onlyFolder = archiveFolderRepository.save(new ArchiveFolder(room, "유일한 폴더"));

    BadRequestException ex =
        catchThrowableOfType(
            () ->
                archiveFolderService.deleteFolder(member.getId(), room.getId(), onlyFolder.getId()),
            BadRequestException.class);

    assertThat(ex).isNotNull();
    assertThat(archiveFolderRepository.findById(onlyFolder.getId())).isPresent();
  }

  /** 방에 폴더가 0개면 조회 시 "기본" 폴더가 생긴다(백엔드 요청, 2026-08-07). */
  @Test
  void listingFoldersInRoomWithNoneCreatesDefaultFolder() {
    Room room = room();
    User member = user("uid-arch-default-folder");
    roomMemberRepository.save(new RoomMember(room, member));

    List<ArchiveFolderResponse> folders =
        archiveFolderService.listFolders(member.getId(), room.getId());

    assertThat(folders)
        .extracting(ArchiveFolderResponse::name)
        .containsExactly(ArchiveFolder.DEFAULT_FOLDER_NAME);
  }

  /** 이미 폴더가 있으면 "기본"을 추가로 만들지 않는다. */
  @Test
  void listingFoldersDoesNotCreateDefaultWhenFoldersAlreadyExist() {
    Room room = room();
    User member = user("uid-arch-has-folder");
    roomMemberRepository.save(new RoomMember(room, member));
    archiveFolderRepository.save(new ArchiveFolder(room, "이미 있는 폴더"));

    List<ArchiveFolderResponse> folders =
        archiveFolderService.listFolders(member.getId(), room.getId());

    assertThat(folders).extracting(ArchiveFolderResponse::name).containsExactly("이미 있는 폴더");
  }

  @Test
  void nonMemberCannotCreateFolder() {
    Room room = room();
    User member = user("uid-arch-owner");
    roomMemberRepository.save(new RoomMember(room, member));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveFolderService.createFolder(
                    "uid-arch-outsider", room.getId(), new CreateArchiveFolderRequest("이름")),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }

  @Test
  void renamingFolderFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-arch-cross-rename");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    ArchiveFolder folderOfRoomB = archiveFolderRepository.save(new ArchiveFolder(roomB, "남의 폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveFolderService.renameFolder(
                    member.getId(),
                    roomA.getId(),
                    folderOfRoomB.getId(),
                    new UpdateArchiveFolderRequest("바꾸기")),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void deletingFolderFromAnotherRoomIsRejectedAsNotFound() {
    Room roomA = room();
    Room roomB = room();
    User member = user("uid-arch-cross-delete");
    roomMemberRepository.save(new RoomMember(roomA, member));
    roomMemberRepository.save(new RoomMember(roomB, member));
    ArchiveFolder folderOfRoomB = archiveFolderRepository.save(new ArchiveFolder(roomB, "남의 폴더"));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveFolderService.deleteFolder(
                    member.getId(), roomA.getId(), folderOfRoomB.getId()),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
    assertThat(archiveFolderRepository.findById(folderOfRoomB.getId())).isPresent();
  }
}
