package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.archive.client.UrlSafetyValidator;
import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
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
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * 「AI 요약 만들기」 버튼이 부르는 경로를 잰다(2026-08-06).
 *
 * <p>🔴 <b>왜 버튼인가.</b> 텍스트로 등록한 자료는 자동 요약을 하지 않게 바꿨다 — 사용자가 직접 적은 짧은 메모는 본문이 곧 요약이라 얻는 것이 거의 없으면서
 * LLM 호출만 쓴다(유저 테스트 피드백: "AI 응답 기다리는 시간이 아쉽다"). 필요한 사람이 상세에서 만든다.
 *
 * <p><b>"요약이 이미 있으면 거절"이 남용 방지도 겸한다</b> — 한 번 성공하면 그 자료로는 더 못 부르므로 별도 레이트 리밋을 두지 않았다.
 */
class ArchiveSummaryOnDemandTest {

  private static final String UID = "uid-1";
  private static final long ROOM_ID = 7L;
  private static final long ITEM_ID = 11L;

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
  private final ArchiveSummaryFiller summaryFiller = mock(ArchiveSummaryFiller.class);

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
          new UrlSafetyValidator(),
          mock(ArchiveCrawlProcessor.class),
          summaryFiller,
          mock(ActivityService.class),
          mock(UserActivityRecorder.class),
          Optional.empty());

  @Test
  void 요약이_없으면_만들어_준다() {
    ArchiveItem item = given(itemWith("적어둔 메모 본문", null));
    when(summaryFiller.fill(item)).thenReturn(true);

    service.summarizeItem(UID, ROOM_ID, ITEM_ID);

    verify(summaryFiller).fill(item);
  }

  @Test
  void 이미_요약이_있으면_거절한다() {
    // 다시 만들 이유가 없다. 그리고 이 규칙이 남용 방지를 겸한다 —
    // 한 번 성공하면 그 자료로는 더 못 부른다.
    given(itemWith("본문", "이미 있는 요약"));

    assertThatThrownBy(() -> service.summarizeItem(UID, ROOM_ID, ITEM_ID))
        .isInstanceOf(BadRequestException.class)
        .hasMessage("이미 요약이 있어요");

    verify(summaryFiller, never()).fill(any());
  }

  @Test
  void 본문이_없으면_거절한다() {
    // 크롤링이 아직 안 끝났거나(PENDING) 실패한 자료 — 요약할 것이 없는데 게이트웨이를 부르면 안 된다.
    given(itemWith(null, null));

    assertThatThrownBy(() -> service.summarizeItem(UID, ROOM_ID, ITEM_ID))
        .isInstanceOf(BadRequestException.class)
        .hasMessage("아직 요약할 내용이 없어요");

    verify(summaryFiller, never()).fill(any());
  }

  @Test
  void 요약_생성이_실패하면_다시_시도하라고_알려준다() {
    // ArchiveSummaryFiller 는 예외를 안 던지고 false 를 준다(백필이 한 건 때문에 멈추지 않게 한 계약).
    // 사용자 요청 경로에서는 그 false 가 조용히 성공으로 보이면 안 된다.
    ArchiveItem item = given(itemWith("본문", null));
    when(summaryFiller.fill(item)).thenReturn(false);

    assertThatThrownBy(() -> service.summarizeItem(UID, ROOM_ID, ITEM_ID))
        .isInstanceOf(BadRequestException.class)
        .hasMessage("요약을 만들지 못했어요. 잠시 후 다시 시도해 주세요");
  }

  @Test
  void 방_멤버가_아니면_아예_못_부른다() {
    when(roomMemberRepository.existsById(any())).thenReturn(false);

    assertThatThrownBy(() -> service.summarizeItem(UID, ROOM_ID, ITEM_ID))
        .isInstanceOf(Exception.class);

    verify(summaryFiller, never()).fill(any());
  }

  private ArchiveItem itemWith(String bodyText, String summary) {
    Room room = new Room("방", null, "목표", null, LocalDate.now(), LocalDate.now().plusDays(10));
    ReflectionTestUtils.setField(room, "id", ROOM_ID);
    ArchiveFolder folder = new ArchiveFolder(room, "폴더");
    ArchiveItem item =
        bodyText == null
            ? ArchiveItem.pending(folder, room, "제목", "https://example.com/a", null)
            : ArchiveItem.textDone(folder, room, "제목", bodyText, null);
    ReflectionTestUtils.setField(item, "id", ITEM_ID);
    if (summary != null) {
      item.applySummary(summary);
    }
    return item;
  }

  private ArchiveItem given(ArchiveItem item) {
    when(roomMemberRepository.existsById(any())).thenReturn(true);
    // 2026-08-08: 상세 응답이 폴더 이름·등록자를 싣게 되면서 resolveItem 이 findById →
    // findForDetailById(폴더·등록자 join fetch)로 바뀌었다. 목이라 실제 쿼리는 안 돌지만
    // 스텁 이름은 따라가야 한다.
    when(archiveItemRepository.findForDetailById(ITEM_ID)).thenReturn(Optional.of(item));
    when(archiveItemTagRepository.findByItemId(any())).thenReturn(List.of());
    when(userRepository.findById(UID)).thenReturn(Optional.of(new User(UID, UID, null)));
    return item;
  }
}
