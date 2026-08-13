package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.archive.client.CompositeUrlCrawler;
import com.nomara.modi.server.domain.archive.client.CrawlResult;
import com.nomara.modi.server.domain.archive.dto.CreateArchiveItemRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateItemUrlRequest;
import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveItemTag;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemTagRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
import java.time.LocalDate;
import java.util.List;
import java.util.concurrent.Executor;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.springframework.core.task.SyncTaskExecutor;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 링크 편집(S-25-B, 2026-08-06) — URL을 바꾸면 비동기 재분석이 다시 도는지를 {@code ArchiveCrawlRetryFlowTest}와 같은 방식(동기
 * 실행기 + 크롤러 목)으로 잰다.
 */
@Testcontainers
@SpringBootTest(properties = "spring.main.allow-bean-definition-overriding=true")
class ArchiveItemUrlEditTest {

  @Container @ServiceConnection
  static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.flyway.enabled", () -> "true");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "validate");
  }

  /** 재크롤링을 같은 스레드에서 끝내 상태 전이를 결정적으로 관찰한다(ArchiveCrawlRetryFlowTest와 동일). */
  @TestConfiguration
  static class SyncExecutorConfig {

    @Bean(name = "archiveCrawlExecutor")
    Executor archiveCrawlExecutor() {
      return new SyncTaskExecutor();
    }
  }

  @MockitoBean private CompositeUrlCrawler urlCrawler;

  @Autowired private ArchiveItemService archiveItemService;
  @Autowired private ArchiveItemRepository archiveItemRepository;
  @Autowired private ArchiveItemTagRepository archiveItemTagRepository;
  @Autowired private ArchiveFolderRepository archiveFolderRepository;
  @Autowired private RoomRepository roomRepository;
  @Autowired private RoomMemberRepository roomMemberRepository;
  @Autowired private UserRepository userRepository;

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
  void editingUrlReplacesContentAndTagsWithTheNewCrawl() {
    when(urlCrawler.crawl(any()))
        .thenReturn(new CrawlResult("옛 제목", "옛 본문", null, "old.com"))
        .thenReturn(new CrawlResult("새 제목", "새 본문", null, "new.com"));

    Room room = room();
    User member = user("uid-url-edit-a");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    var created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest("https://example.com/a", null, null, null, null));

    var updated =
        archiveItemService.updateUrl(
            member.getId(),
            room.getId(),
            created.id(),
            new UpdateItemUrlRequest("https://example.org/b"));

    // 응답은 항상 PENDING이다 — 재분석은 비동기라 이 시점엔 아직 반영되지 않은 스냅샷을 돌려준다
    // (등록과 같은 설계, ArchiveItemService.createItem/createSharedItem과 동일한 이유).
    assertThat(updated.url()).isEqualTo("https://example.org/b");
    assertThat(updated.crawlStatus()).isEqualTo("PENDING");

    // 실제 재분석 결과는 DB에서 다시 읽어야 보인다 — 동기 실행기라 이미 끝나 있다.
    ArchiveItem reloaded = archiveItemRepository.findById(created.id()).orElseThrow();
    assertThat(reloaded.getTitle()).isEqualTo("새 제목");
    assertThat(reloaded.getBodyText()).isEqualTo("새 본문");
    assertThat(reloaded.getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.DONE);
  }

  /**
   * 🔴 <b>{@code @Transactional} 없는 경로에서도 상세 응답이 만들어진다</b>(2026-08-08, S-25-B 리디자인 회귀 방지).
   *
   * <p>{@code updateUrl}은 의도적으로 {@code @Transactional}이 아니고({@code createItem}과 같은 이유 — 커밋 전에 비동기
   * 크롤링 스레드가 옛 상태를 읽는 경합을 피한다) {@code spring.jpa.open-in-view}도 {@code false}다. 상세 응답이 폴더 이름과 등록자
   * 닉네임을 싣게 되면서 <b>지연 로딩 두 개를 새로 건드리게 됐는데</b>, {@code resolveItem}이 그냥 {@code findById}로 읽으면 여기서
   * {@code LazyInitializationException}이 난다 — 프록시를 초기화할 세션이 이미 닫혔기 때문이다.
   *
   * <p><b>이 테스트를 빨갛게 만드는 것은 {@code buildDetail(item)} → {@code buildDetail(saved)} 되돌림 하나다</b>(실측).
   * {@code findForDetailById}의 join fetch 를 {@code findById}로 되돌려도 통과한다 — 그쪽은 방어선이 아니라 쿼리 수
   * 최적화다(리포지터리 주석 참고). 다른 상세 테스트들은 전부 {@code @Transactional}인 {@code getDetail}을 타서 이 구멍 자체를 못 잡는다.
   */
  @Test
  void editingUrlStillBuildsDetailWithFolderNameAndCreator() {
    when(urlCrawler.crawl(any()))
        .thenReturn(new CrawlResult("옛 제목", "옛 본문", null, "old.com"))
        .thenReturn(new CrawlResult("새 제목", "새 본문", null, "new.com"));

    Room room = room();
    User member = user("uid-url-edit-detail");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "링크 폴더"));
    var created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest("https://example.com/a", null, null, null, null));

    // 등록 경로도 @Transactional 이 아니다. 이쪽이 안전한 것은 새 엔티티라 save() 가 merge 가 아니라
    // persist 이고(같은 인스턴스를 돌려준다) folder/createdBy 가 프록시가 아닌 실체이기 때문인데,
    // 그 안전성이 코드에 드러나 있지 않아 여기서 함께 못 박는다.
    assertThat(created.folderName()).isEqualTo("링크 폴더");
    assertThat(created.createdBy()).isNotNull();

    var updated =
        archiveItemService.updateUrl(
            member.getId(),
            room.getId(),
            created.id(),
            new UpdateItemUrlRequest("https://example.org/b"));

    assertThat(updated.folderName()).isEqualTo("링크 폴더");
    assertThat(updated.createdBy()).isNotNull();
    assertThat(updated.createdBy().userId()).isEqualTo(member.getId());
  }

  @Test
  void editingUrlClearsStaleTagsBeforeRecrawling() {
    when(urlCrawler.crawl(any()))
        .thenReturn(new CrawlResult("옛 제목", "옛 본문", null, "old.com"))
        .thenReturn(new CrawlResult("새 제목", "새 본문", null, "new.com"));

    Room room = room();
    User member = user("uid-url-edit-tags");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    var created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest("https://example.com/c", null, null, null, null));
    ArchiveItem item = archiveItemRepository.findById(created.id()).orElseThrow();
    archiveItemTagRepository.save(new ArchiveItemTag(item, "옛태그"));

    archiveItemService.updateUrl(
        member.getId(),
        room.getId(),
        created.id(),
        new UpdateItemUrlRequest("https://example.org/d"));

    List<ArchiveItemTag> tags = archiveItemTagRepository.findByItemId(created.id());
    assertThat(tags).extracting(t -> t.getId().getTag()).doesNotContain("옛태그");
  }

  @Test
  void editingUrlOfATextItemIsRejected() {
    Room room = room();
    User member = user("uid-url-edit-text");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    var created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest(null, "본문", null, null, null));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.updateUrl(
                    member.getId(),
                    room.getId(),
                    created.id(),
                    new UpdateItemUrlRequest("https://example.com")),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void editingUrlWhilePendingIsRejected() {
    Room room = room();
    User member = user("uid-url-edit-pending");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    ArchiveItem pending =
        archiveItemRepository.save(
            ArchiveItem.pending(
                folder, room, "https://example.net", "https://example.net", member));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.updateUrl(
                    member.getId(),
                    room.getId(),
                    pending.getId(),
                    new UpdateItemUrlRequest("https://example.com")),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.BAD_REQUEST);
  }

  @Test
  void nonMemberCannotEditUrl() {
    when(urlCrawler.crawl(any())).thenReturn(new CrawlResult("제목", "본문", null, "old.com"));
    Room room = room();
    User member = user("uid-url-edit-owner");
    roomMemberRepository.save(new RoomMember(room, member));
    ArchiveFolder folder = archiveFolderRepository.save(new ArchiveFolder(room, "폴더"));
    var created =
        archiveItemService.createItem(
            member.getId(),
            room.getId(),
            folder.getId(),
            new CreateArchiveItemRequest("https://example.com/e", null, null, null, null));

    ApiException ex =
        catchThrowableOfType(
            () ->
                archiveItemService.updateUrl(
                    "uid-url-edit-outsider",
                    room.getId(),
                    created.id(),
                    new UpdateItemUrlRequest("https://example.com")),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.FORBIDDEN);
  }
}
