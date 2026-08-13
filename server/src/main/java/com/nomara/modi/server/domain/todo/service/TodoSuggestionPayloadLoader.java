package com.nomara.modi.server.domain.todo.service;

import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveItemTag;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemTagRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveLikeRepository;
import com.nomara.modi.server.domain.category.entity.Category;
import com.nomara.modi.server.domain.category.repository.CategoryRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.exception.RoomNotFoundException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.todo.client.AiSuggestPayload;
import com.nomara.modi.server.domain.todo.entity.Todo;
import com.nomara.modi.server.domain.todo.repository.TodoRepository;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * AI 서버로 나갈 재료를 모은다. AI 서버는 도메인 DB를 직접 보지 않으므로({@code ai/CLAUDE.md}) 방의 재료를 전부 여기서 실어 보낸다.
 *
 * <p><b>{@link TodoSuggestionService}에서 분리한 이유는 트랜잭션 경계다.</b> 원래는 서비스 메서드 하나가
 * {@code @Transactional(readOnly = true)}였고 그 안에서 LLM 호출까지 했다 — 실측 7~9초({@code
 * ai/docs/EXPERIMENTS.md} #10) 동안 DB 커넥션을 붙잡고 있었다. 읽기를 이 빈으로 떼어내면 커넥션이 <b>읽는 동안만</b> 잡히고 LLM 호출은
 * 트랜잭션 밖에서 일어난다.
 *
 * <p>인가 검사도 여기 있다 — 재료를 읽기 전에 막아야 하고, 읽기와 같은 트랜잭션에 있는 편이 자연스럽다.
 */
@Component
class TodoSuggestionPayloadLoader {

  private final RoomRepository roomRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final CategoryRepository categoryRepository;
  private final TodoRepository todoRepository;
  private final ArchiveItemRepository archiveItemRepository;
  private final ArchiveItemTagRepository archiveItemTagRepository;
  private final ArchiveLikeRepository archiveLikeRepository;
  private final TodoSuggestionExposureStore exposureStore;

  /**
   * 이미 노출한 후보를 프롬프트의 {@code excluded_todos}로 보낼 것인가.
   *
   * <p>🔴 <b>기본 {@code false} 다 을 의도적으로 되돌린 것이다</b>(2026-08-09 사용자 확정). 그 티켓이 고친 증상("같은 후보가 반복
   * 노출")이 이제 <b>사양</b>이다. 버그로 보고 되돌리지 말 것.
   *
   * <p>이유는 후보 개수다. 동결 스냅샷 #26({@code ai/tests/test_snapshot_room_2026_08_03.py})의 회차별 후보 수를 보면 부산
   * 방이 <b>7.00 → 4.80 → 3.40</b>, 오픽 방이 <b>6.20 → 4.40 → 4.00</b> 으로 떨어진다. 1회차는 이미 6~7개가 나오므로 원인은
   * 생성이 아니라 <b>회차마다 커지는 제외 목록</b>이다. 시연 요구가 "매번 6~8개"라 이 축을 껐다.
   *
   * <p>{@code exposureStore.record()} 는 <b>계속 남긴다</b> — 기록이 끊기면 이 값을 다시 켰을 때 빈 목록에서 시작한다. 기록은
   * insert 하나라 싸고, 조회만 끄면 된다.
   */
  private final boolean excludeRecent;

  TodoSuggestionPayloadLoader(
      RoomRepository roomRepository,
      RoomMemberRepository roomMemberRepository,
      CategoryRepository categoryRepository,
      TodoRepository todoRepository,
      ArchiveItemRepository archiveItemRepository,
      ArchiveItemTagRepository archiveItemTagRepository,
      ArchiveLikeRepository archiveLikeRepository,
      TodoSuggestionExposureStore exposureStore,
      @Value("${modi.todo.suggestion.exclude-recent:false}") boolean excludeRecent) {
    this.excludeRecent = excludeRecent;
    this.roomRepository = roomRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.categoryRepository = categoryRepository;
    this.todoRepository = todoRepository;
    this.archiveItemRepository = archiveItemRepository;
    this.archiveItemTagRepository = archiveItemTagRepository;
    this.archiveLikeRepository = archiveLikeRepository;
    this.exposureStore = exposureStore;
  }

  @Transactional(readOnly = true)
  public AiSuggestPayload load(String uid, Long roomId) {
    requireMembership(uid, roomId);
    Room room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);

    List<String> categories =
        categoryRepository.findByRoomIdOrderByPositionAscIdAsc(roomId).stream()
            .map(Category::getName)
            .toList();
    List<String> existingTodos =
        todoRepository.findByRoomIdOrderByPositionAscIdAsc(roomId).stream()
            .map(Todo::getTitle)
            .toList();

    return new AiSuggestPayload(
        new AiSuggestPayload.RoomInfo(
            room.getName(),
            room.getGoal(),
            room.getGoalDetail(),
            room.getStartDate(),
            room.getEndDate()),
        categories,
        existingTodos,
        // 이미 노출한 후보. "사용자가 거절한 것"이 아니라 "보여준 것 전부"다(TodoSuggestionExposure
        // javadoc). 🔴 기본값에서는 **빈 목록**이라 같은 후보가 다시 나온다 — 의도된 것이다
        // (`excludeRecent` javadoc 되돌림).
        excludeRecent ? exposureStore.recentTitles(roomId) : List.of(),
        loadArchive(roomId));
  }

  /**
   * 자료 하나가 프롬프트에 실려 나갈 텍스트를 고른다 — <b>요약과 본문 중 짧은 쪽</b>(2026-07-30 확정).
   *
   * <p>요약을 쓰는 것이 목적이다: 추천은 아카이브 전체를 프롬프트에 넣으므로 본문 대신 요약을 쓰면 자료 20건 기준 약 117,000 tok → 약 2,600 tok이
   * 된다({@code ai/docs/EXPERIMENTS.md} #8).
   *
   * <p><b>"짧은 쪽"인 이유는 임계값 상수를 만들지 않기 위해서다.</b> 요약이 없는 자료가 정상적으로 존재하므로(V5 이전 등록분·PENDING·요약 실패) 폴백이
   * 필요한데, "본문이 N자 미만이면 요약을 만들지 않는다" 같은 임계값을 두면 근거 없는 숫자가 코드에 남는다. 짧은 쪽을 고르면 그 세 경우와 "본문이 요약보다 짧은
   * 경우"가 규칙 하나로 전부 처리된다.
   */
  private static String pickContent(ArchiveItem item) {
    String summary = item.getSummary();
    String bodyText = item.getBodyText();
    if (summary == null) {
      return bodyText;
    }
    if (bodyText == null) {
      return summary;
    }
    return summary.length() <= bodyText.length() ? summary : bodyText;
  }

  /**
   * 방의 자료를 전부 싣는다. <b>개수 상한을 여기서 두지 않는다</b> — 프롬프트에 무엇을 넣을지는 AI 서버가 정한다(가중 순위 정규화). 서버는 재료만 모은다.
   *
   * <p>⚠️ 상한이 없다는 것이 이제 두 배로 비싸다 — 벡터가 실리면서 <b>자료 1건이 약 21.7KB</b>가 됐다(18건에 390KB 실측). AI 서버의 예산은
   * <b>프롬프트만</b> 자르지 전송량은 안 자른다. 자료 200건이면 요청이 약 4.3MB다.
   */
  private List<AiSuggestPayload.ArchiveInfo> loadArchive(Long roomId) {
    List<ArchiveItem> items =
        archiveItemRepository.findByRoomIdOrderByCreatedAtDesc(roomId, Pageable.unpaged());
    if (items.isEmpty()) {
      return List.of();
    }

    Map<Long, List<String>> tagsByItemId = new HashMap<>();
    for (ArchiveItemTag tag :
        archiveItemTagRepository.findByItemIdIn(items.stream().map(ArchiveItem::getId).toList())) {
      tagsByItemId
          .computeIfAbsent(tag.getId().getItemId(), key -> new ArrayList<>())
          .add(tag.getId().getTag());
    }

    // 좋아요는 자료마다 세면 N+1이 된다 — 태그와 같이 방 단위로 한 번에 읽어 맵으로 만든다.
    // 좋아요 0개인 항목은 이 결과에 없으므로 아래에서 기본값 0으로 채운다(리포지토리 주석의 규약).
    Map<Long, Long> likesByItemId = new HashMap<>();
    for (ArchiveLikeRepository.ItemLikeCount row :
        archiveLikeRepository.countByItemIdForRoom(roomId)) {
      likesByItemId.put(row.getItemId(), row.getLikeCount());
    }

    return items.stream()
        .map(
            item ->
                new AiSuggestPayload.ArchiveInfo(
                    item.getId(),
                    item.getTitle(),
                    pickContent(item),
                    tagsByItemId.getOrDefault(item.getId(), List.of()),
                    item.getEmbedding(),
                    item.isPinned(),
                    likesByItemId.getOrDefault(item.getId(), 0L),
                    item.getCreatedAt()))
        .toList();
  }

  private void requireMembership(String uid, Long roomId) {
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, uid))) {
      throw new NotRoomMemberException();
    }
  }
}
