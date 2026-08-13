package com.nomara.modi.server.domain.archive.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.nomara.modi.server.domain.archive.service.ArchiveAnalysisNotificationBuffer.Buffered;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.notification.PushNotifier;
import com.nomara.modi.server.global.notification.PushType;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 모아둔 것을 <b>언제 · 어떤 문구로</b> 보내는지 잰다.
 *
 * <p>스프링을 띄우지 않는다 — 버퍼는 목이고, 여기서 재는 것은 조용해졌는지 판정과 문구 조립이다.
 */
class ArchiveAnalysisNotifierTest {

  private static final String UID = "uid-1";

  private final ArchiveAnalysisNotificationBuffer buffer =
      mock(ArchiveAnalysisNotificationBuffer.class);
  private final UserRepository userRepository = mock(UserRepository.class);
  private final PushNotifier pushNotifier = mock(PushNotifier.class);

  private final ArchiveAnalysisNotifier notifier =
      new ArchiveAnalysisNotifier(buffer, userRepository, pushNotifier);

  private final User user = new User(UID, "닉네임", null);

  // --------------------------------------------------------------- 언제 보내나

  @Test
  void 아직_처리_중이면_보내지_않는다() {
    // 🔴 묶어 보내는 것의 요점. 방금 한 건이 끝났다고 바로 보내면, 연달아 넣는 동안
    // 알림이 건마다 날아간다 — 사용자가 5건 공유하면 5번 울린다.
    givenPending(Instant.now().minus(Duration.ofSeconds(10)));

    notifier.flushQuietBuffers();

    verify(pushNotifier, never()).notify(any(), any(), any(), any(), any());
    verify(buffer, never()).takeFor(any());
  }

  @Test
  void 조용해지면_한_번_보낸다() {
    givenPending(Instant.now().minus(Duration.ofMinutes(2)));
    when(buffer.takeFor(UID)).thenReturn(new Buffered(3, 0, "무엇", null, 0));
    when(userRepository.findById(UID)).thenReturn(Optional.of(user));

    notifier.flushQuietBuffers();

    verify(pushNotifier).notify(eq(user), eq(PushType.ARCHIVE_ANALYSIS_DONE), any(), any(), any());
  }

  @Test
  void 대기자가_없으면_버퍼를_읽지도_않는다() {
    when(buffer.pendingUsers()).thenReturn(Set.of());

    notifier.flushQuietBuffers();

    verify(buffer, never()).lastConfirmedAt(any());
  }

  @Test
  void 카운터가_없는_찌꺼기는_정리하고_넘어간다() {
    // TTL 로 카운터만 먼저 사라지면 목록에 uid 가 남는다 — 매 tick 마다 헛돌지 않게 지운다.
    when(buffer.pendingUsers()).thenReturn(Set.of(UID));
    when(buffer.lastConfirmedAt(UID)).thenReturn(0L);

    notifier.flushQuietBuffers();

    verify(buffer).clear(UID);
    verify(pushNotifier, never()).notify(any(), any(), any(), any(), any());
  }

  @Test
  void 탈퇴한_사람에게는_보내지_않는다() {
    givenPending(Instant.now().minus(Duration.ofMinutes(2)));
    when(buffer.takeFor(UID)).thenReturn(new Buffered(1, 0, "무엇", null, 0));
    when(userRepository.findById(UID)).thenReturn(Optional.empty());

    notifier.flushQuietBuffers();

    verify(pushNotifier, never()).notify(any(), any(), any(), any(), any());
  }

  @Test
  void 한_사람_발송이_실패해도_배치가_멈추지_않는다() {
    givenPending(Instant.now().minus(Duration.ofMinutes(2)));
    when(buffer.takeFor(UID)).thenReturn(new Buffered(1, 0, "무엇", null, 0));
    when(userRepository.findById(UID)).thenReturn(Optional.of(user));
    doThrow(new IllegalStateException("FCM 장애"))
        .when(pushNotifier)
        .notify(any(), any(), any(), any(), any());

    notifier.flushQuietBuffers(); // 예외가 새어나오면 이 줄에서 실패한다
  }

  // --------------------------------------------------------------- 어떤 문구로

  @Test
  void 한_건_성공이면_고정_문구_실패면_이모지_문구를_쓴다() {
    // 성공 제목은 고정 문구다(2026-08-09 사용자 확정) — 어떤 자료인지는 본문이 말해 준다.
    assertThat(ArchiveAnalysisNotifier.title(new Buffered(1, 0, "강릉 여행 코스", null, 0)))
        .isEqualTo("AI로 자료 분석이 끝났어요");
    // 실패는 dev에서 합류한 이모지 카피를 그대로 쓴다.
    assertThat(ArchiveAnalysisNotifier.title(new Buffered(0, 1, "강릉 여행 코스", null, 0)))
        .isEqualTo("「강릉 여행 코스」 못 가져왔어요 😢");
  }

  @Test
  void 한_건_성공이면_본문에_제목과_방_이름을_담는다() {
    // 2026-08-09 사용자 확정 — 어디 가서 볼지 본문에서 바로 알려준다.
    assertThat(ArchiveAnalysisNotifier.body(new Buffered(1, 0, "강릉 여행 코스", "여행방", 0)))
        .isEqualTo("강릉 여행 코스의 내용을 여행방 모아보기에서 확인해보세요");
  }

  @Test
  void 방_이름이_없으면_기존_문구로_폴백한다() {
    // 여러 건이면 여러 방에 걸칠 수 있어 방 이름을 안 쓴다 — 이 값이 비어 있는 경우와 같은 폴백.
    assertThat(ArchiveAnalysisNotifier.body(new Buffered(1, 0, "강릉 여행 코스", null, 0)))
        .isEqualTo("모아보기에서 확인해 보세요");
  }

  @Test
  void 여러_건이면_개수로_묶는다() {
    assertThat(ArchiveAnalysisNotifier.title(new Buffered(3, 0, "무엇", null, 0)))
        .isEqualTo("자료 3건 정리 완료 ✨");
    assertThat(ArchiveAnalysisNotifier.title(new Buffered(0, 2, "무엇", null, 0)))
        .isEqualTo("자료 2건 못 가져왔어요 😢");
    assertThat(ArchiveAnalysisNotifier.title(new Buffered(3, 1, "무엇", null, 0)))
        .isEqualTo("자료 3건 완료 · 1건 실패");
  }

  @Test
  void 제목이_없으면_개수로_적는다() {
    // 제목은 Redis 에서 오므로 없을 수 있다(TTL·장애). 「」 만 남은 문구가 나가면 안 된다.
    assertThat(ArchiveAnalysisNotifier.title(new Buffered(1, 0, null, null, 0)))
        .isEqualTo("자료 1건 정리 완료 ✨");
    assertThat(ArchiveAnalysisNotifier.title(new Buffered(1, 0, "  ", null, 0)))
        .isEqualTo("자료 1건 정리 완료 ✨");
  }

  @Test
  void 전부_실패했으면_링크는_남아_있다고_알려준다() {
    // 실패 알림이 "다 날아갔다"로 읽히면 안 된다 — 자료와 링크는 그대로 있다.
    assertThat(ArchiveAnalysisNotifier.body(new Buffered(0, 2, null, null, 0)))
        .contains("링크는 저장돼 있어요");
    assertThat(ArchiveAnalysisNotifier.body(new Buffered(2, 0, null, null, 0)))
        .doesNotContain("링크는 저장돼 있어요");
  }

  @Test
  void 성공과_실패가_섞이면_제목에_둘_다_적는다() {
    ArgumentCaptor<String> title = ArgumentCaptor.forClass(String.class);
    givenPending(Instant.now().minus(Duration.ofMinutes(2)));
    when(buffer.takeFor(UID)).thenReturn(new Buffered(2, 1, "무엇", null, 0));
    when(userRepository.findById(UID)).thenReturn(Optional.of(user));

    notifier.flushQuietBuffers();

    verify(pushNotifier).notify(any(), any(), any(), title.capture(), any());
    assertThat(title.getValue()).contains("2건").contains("1건");
  }

  private void givenPending(Instant lastConfirmedAt) {
    when(buffer.pendingUsers()).thenReturn(Set.of(UID));
    when(buffer.lastConfirmedAt(UID)).thenReturn(lastConfirmedAt.toEpochMilli());
  }
}
