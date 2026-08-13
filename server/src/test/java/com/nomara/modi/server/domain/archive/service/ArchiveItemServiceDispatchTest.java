package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.archive.client.UrlSafetyValidator;
import com.nomara.modi.server.domain.archive.dto.ArchiveItemDetailResponse;
import com.nomara.modi.server.domain.archive.dto.CreateArchiveItemRequest;
import com.nomara.modi.server.domain.archive.dto.CreateSharedArchiveItemRequest;
import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemCommentRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemTagRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveLikeRepository;
import com.nomara.modi.server.domain.character.service.UserActivityRecorder;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.BadRequestException;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.RejectedExecutionException;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * 등록이 <b>처리기에 무엇을 넘기고 무엇을 남기는지</b>를 잰다 — 공유 등록(S-25-D)과 인앱 등록(S-25-C) 둘 다.
 *
 * <p>🔴 <b>큐가 찼을 때가 "영구 PENDING" 의 입구였다</b>(2026-08-06 리뷰 P2). {@code archiveCrawlExecutor} 는
 * {@code AbortPolicy} 라 큐(50)가 차면 예외를 던지는데, 항목은 이미 커밋된 뒤라 <b>행은 {@code PENDING} 으로 남고 사용자에겐 500</b>
 * 이 갔다. 재시도 배치가 생겼지만 그것은 {@code next_crawl_at} 이 찍힌 것만 보므로, 여기서 찍어 줘야 주워간다.
 *
 * <p>🔴 <b>인앱 등록도 비동기가 됐다</b>(2026-08-06). 예전에는 {@code createItem} 이 HTTP 응답 전에 크롤링 1 + LLM 3 을 돌아
 * 사용자를 붙잡았다(문서화된 최악 198초). 지금은 {@code PENDING} 으로 저장하고 즉시 응답하며, <b>주소 검증만</b> 동기로 남는다.
 *
 * <p>스프링을 띄우지 않는다 — 재는 것이 갈림길이라 컨테이너가 필요 없다. 주소 검증 <b>규칙</b>(사설망·스킴)은 여기서 목이고, 실제 규칙은 {@code
 * ArchiveItemServiceTest} 가 진짜 주소로 덮는다.
 */
class ArchiveItemServiceDispatchTest {

  private final ArchiveFolderRepository archiveFolderRepository =
      mock(ArchiveFolderRepository.class);
  private final ArchiveItemRepository archiveItemRepository = mock(ArchiveItemRepository.class);
  private final ArchiveItemTagRepository archiveItemTagRepository =
      mock(ArchiveItemTagRepository.class);
  private final ArchiveLikeRepository archiveLikeRepository = mock(ArchiveLikeRepository.class);
  private final ArchiveItemCommentRepository archiveItemCommentRepository =
      mock(ArchiveItemCommentRepository.class);
  private final RoomMemberRepository roomMemberRepository = mock(RoomMemberRepository.class);
  private final RoomRepository roomRepository = mock(RoomRepository.class);
  private final UserRepository userRepository = mock(UserRepository.class);
  private final ArchiveCrawlProcessor processor = mock(ArchiveCrawlProcessor.class);
  // 목이다 — 통과가 기본값. 규칙 자체(사설망·스킴)는 ArchiveItemServiceTest 가 실제 주소로 덮는다.
  private final UrlSafetyValidator urlSafetyValidator = mock(UrlSafetyValidator.class);

  private final ArchiveItemService service =
      new ArchiveItemService(
          archiveFolderRepository,
          archiveItemRepository,
          archiveItemTagRepository,
          archiveLikeRepository,
          archiveItemCommentRepository,
          roomMemberRepository,
          roomRepository,
          userRepository,
          urlSafetyValidator,
          processor,
          mock(ArchiveSummaryFiller.class),
          mock(ActivityService.class),
          mock(UserActivityRecorder.class),
          Optional.empty());

  private static final String UID = "uid-1";
  private static final long ROOM_ID = 7L;
  private static final long FOLDER_ID = 3L;

  @Test
  void 큐가_차면_배치가_주워가게_예약을_남긴다() {
    ArchiveItem[] saved = given();
    doThrow(new RejectedExecutionException("큐 참")).when(processor).process(anyLong());
    Instant before = Instant.now();

    service.createSharedItem(UID, ROOM_ID, FOLDER_ID, request());

    // 예약이 없으면 배치가 안 집는다 — 그 항목은 영영 "분석 중"이다.
    assertThat(saved[0].getNextCrawlAt()).isNotNull();
    assertThat(Duration.between(before, saved[0].getNextCrawlAt()))
        .isBetween(Duration.ofMinutes(5), Duration.ofMinutes(6));
    assertThat(saved[0].getCrawlStatus()).isEqualTo(ArchiveItem.CrawlStatus.PENDING);
    // 실패한 것이 아니라 보내지도 못한 것이다 — 배치의 rescheduleCrawl 과 같은 원칙.
    assertThat(saved[0].getCrawlRetries()).isZero();
  }

  @Test
  void 큐가_차도_사용자에게는_등록_성공이다() {
    given();
    doThrow(new RejectedExecutionException("큐 참")).when(processor).process(anyLong());

    // 예전에는 여기서 예외가 그대로 올라가 HTTP 500 이 됐다. 항목은 이미 저장됐는데도.
    assertThat(service.createSharedItem(UID, ROOM_ID, FOLDER_ID, request())).isNotNull();
  }

  @Test
  void 큐가_비어_있으면_예약을_남기지_않는다() {
    // 반대편 말뚝 — 늘 예약을 찍으면 배치가 이미 처리 중인 항목을 또 집는다.
    ArchiveItem[] saved = given();

    service.createSharedItem(UID, ROOM_ID, FOLDER_ID, request());

    assertThat(saved[0].getNextCrawlAt()).isNull();
  }

  // ------------------------------------------------ 인앱 등록(S-25-C)도 비동기다 (2026-08-06)

  @Test
  void 인앱_URL_등록은_사용자를_붙잡지_않는다() {
    // 🔴 이 커밋의 요점. 예전에는 이 호출 안에서 크롤링 1 + LLM 3 을 돌았고(문서화된 최악 198초),
    // 사용자는 [등록]을 누른 채 그동안 화면에 묶여 있었다.
    ArchiveItem[] saved = given();

    ArchiveItemDetailResponse response =
        service.createItem(UID, ROOM_ID, FOLDER_ID, urlRequest("https://example.com/a"));

    verify(processor).process(42L);
    assertThat(response.crawlStatus()).isEqualTo("PENDING");
    // 제목은 URL 그대로 둔다 — 크롤링이 끝나면 markCrawlDone 이 진짜 제목으로 바꾼다.
    assertThat(saved[0].getTitle()).isEqualTo("https://example.com/a");
    assertThat(saved[0].getBodyText()).isNull();
  }

  @Test
  void 인앱_텍스트_등록은_본문을_바로_채운다() {
    // 텍스트는 크롤링할 것이 없다 — 제목·본문은 등록 시점에 정해지고 LLM 만 뒤로 미룬다.
    ArchiveItem[] saved = given();

    service.createItem(UID, ROOM_ID, FOLDER_ID, textRequest("오늘 읽은 글 메모"));

    verify(processor).process(42L);
    assertThat(saved[0].getBodyText()).isEqualTo("오늘 읽은 글 메모");
    assertThat(saved[0].getTitle()).isEqualTo("오늘 읽은 글 메모");
    assertThat(saved[0].getUrl()).isNull();
  }

  @Test
  void 주소_검증은_등록_시점에_동기로_한다() {
    // 오타·사설망 주소까지 뒤로 미루면 사용자는 일단 등록됐다가 나중에 "분석 실패"를 본다.
    // 여기서 즉시 400 으로 돌려주는 편이 낫다.
    given();
    doThrow(new CrawlException("등록할 수 없는 주소예요"))
        .when(urlSafetyValidator)
        .validate("http://127.0.0.1/x");

    assertThatThrownBy(
            () -> service.createItem(UID, ROOM_ID, FOLDER_ID, urlRequest("http://127.0.0.1/x")))
        .isInstanceOf(BadRequestException.class)
        .hasMessage("등록할 수 없는 주소예요");

    // 거절한 주소를 저장하거나 처리기에 넘기면 안 된다.
    verify(archiveItemRepository, never()).save(any(ArchiveItem.class));
    verify(processor, never()).process(anyLong());
  }

  @Test
  void 텍스트_등록은_주소_검증을_거치지_않는다() {
    // url 이 null 인데 검증을 부르면 그 안에서 터진다.
    given();

    service.createItem(UID, ROOM_ID, FOLDER_ID, textRequest("메모"));

    verify(urlSafetyValidator, never()).validate(any());
  }

  private static CreateArchiveItemRequest urlRequest(String url) {
    return new CreateArchiveItemRequest(url, null, null, null, null);
  }

  private static CreateArchiveItemRequest textRequest(String text) {
    return new CreateArchiveItemRequest(null, text, null, null, null);
  }

  private static CreateSharedArchiveItemRequest request() {
    return new CreateSharedArchiveItemRequest(
        "https://example.com/a", "https://example.com/a", null);
  }

  /**
   * 등록이 통과하도록 최소한만 채우고, {@code save()} 가 받는 엔티티를 담을 자리를 돌려준다.
   *
   * <p>배열로 돌려주는 이유: 엔티티는 {@code createSharedItem} 안에서 만들어지므로 <b>호출 뒤에야</b> 존재한다.
   */
  private ArchiveItem[] given() {
    Room room = new Room("방", null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10));
    ReflectionTestUtils.setField(room, "id", ROOM_ID);
    ArchiveFolder folder = new ArchiveFolder(room, "링크 모음");
    ReflectionTestUtils.setField(folder, "id", FOLDER_ID);

    when(roomMemberRepository.existsById(any())).thenReturn(true);
    when(archiveFolderRepository.findById(FOLDER_ID)).thenReturn(Optional.of(folder));
    when(userRepository.findById(UID)).thenReturn(Optional.of(new User(UID, UID, null)));
    when(archiveItemTagRepository.findByItemId(any())).thenReturn(List.of());

    ArchiveItem[] captured = new ArchiveItem[1];
    when(archiveItemRepository.save(any(ArchiveItem.class)))
        .thenAnswer(
            invocation -> {
              ArchiveItem item = invocation.getArgument(0, ArchiveItem.class);
              ReflectionTestUtils.setField(item, "id", 42L);
              captured[0] = item;
              return item;
            });
    return captured;
  }
}
