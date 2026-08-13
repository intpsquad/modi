package com.nomara.modi.server.domain.archive.service;

import com.nomara.modi.server.domain.activity.entity.ActivityType;
import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.archive.client.UrlSafetyValidator;
import com.nomara.modi.server.domain.archive.dto.ArchiveFolderItemsResponse;
import com.nomara.modi.server.domain.archive.dto.ArchiveImageUploadUrlResponse;
import com.nomara.modi.server.domain.archive.dto.ArchiveItemDetailResponse;
import com.nomara.modi.server.domain.archive.dto.ArchiveItemResponse;
import com.nomara.modi.server.domain.archive.dto.CreateArchiveItemRequest;
import com.nomara.modi.server.domain.archive.dto.CreateSharedArchiveItemRequest;
import com.nomara.modi.server.domain.archive.dto.MoveItemFolderRequest;
import com.nomara.modi.server.domain.archive.dto.SetItemLikedRequest;
import com.nomara.modi.server.domain.archive.dto.SetItemPinnedRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateItemMemoRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateItemTagsRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateItemUrlRequest;
import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.entity.ArchiveItemTag;
import com.nomara.modi.server.domain.archive.entity.ArchiveLike;
import com.nomara.modi.server.domain.archive.entity.ArchiveLikeId;
import com.nomara.modi.server.domain.archive.exception.ArchiveFolderNotFoundException;
import com.nomara.modi.server.domain.archive.exception.ArchiveItemNotFoundException;
import com.nomara.modi.server.domain.archive.exception.CrawlException;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemCommentRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemTagRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveLikeRepository;
import com.nomara.modi.server.domain.character.entity.UserActivityKind;
import com.nomara.modi.server.domain.character.service.UserActivityRecorder;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.exception.RoomNotFoundException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.BadRequestException;
import com.nomara.modi.server.global.exception.ServiceUnavailableException;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.RejectedExecutionException;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * specs/0010-아카이브-탭.md — S-25-A 폴더 내 항목 목록 + S-25-B 항목 상세(핀/좋아요/폴더이동/태그편집/삭제) + S-25-C 자료 등록(크롤링 +
 * AI 자동 태깅).
 */
@Service
public class ArchiveItemService {

  // 길이 상한은 ArchiveTextLimits 하나만 본다 — 크롤링 비동기 반영(ArchiveCrawlProcessor)과 같은 값을 써야 한다.
  private static final int MAX_TITLE_LENGTH = ArchiveTextLimits.MAX_TITLE;
  private static final int MAX_BODY_TEXT_LENGTH = ArchiveTextLimits.MAX_BODY_TEXT;
  private static final int MAX_TEXT_TITLE_PREVIEW = ArchiveTextLimits.TEXT_TITLE_PREVIEW;
  private static final int MAX_URL_INPUT_LENGTH = ArchiveTextLimits.MAX_URL_INPUT;
  private static final int MAX_TEXT_INPUT_LENGTH = ArchiveTextLimits.MAX_TEXT_INPUT;

  /** 크롤링 큐가 차서 못 넘겼을 때 배치에 맡기는 시각 — 배치 주기(5분) 무렵이다. */
  private static final Duration QUEUE_FULL_RETRY_DELAY = Duration.ofMinutes(5);

  /** 이미지 업로드 URL 만료 — {@code TodoImageService}와 같은 값. */
  private static final Duration IMAGE_UPLOAD_URL_EXPIRY = Duration.ofMinutes(5);

  private static final Logger log = LoggerFactory.getLogger(ArchiveItemService.class);

  private final ArchiveFolderRepository archiveFolderRepository;
  private final ArchiveItemRepository archiveItemRepository;
  private final ArchiveItemTagRepository archiveItemTagRepository;
  private final ArchiveLikeRepository archiveLikeRepository;
  private final ArchiveItemCommentRepository archiveItemCommentRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final RoomRepository roomRepository;
  private final UserRepository userRepository;
  private final UrlSafetyValidator urlSafetyValidator;
  private final ArchiveCrawlProcessor archiveCrawlProcessor;
  private final ArchiveSummaryFiller summaryFiller;
  private final ActivityService activityService;
  private final UserActivityRecorder userActivityRecorder;
  private final Optional<ObjectStorage> objectStorage;

  /**
   * 🔴 <b>크롤러·요약기·임베더·태깅 클라이언트가 여기서 사라졌다</b>(2026-08-06). 넷 다 {@code createItem} 의 동기 경로에서만 쓰이던
   * 것인데, 그 경로가 비동기로 옮겨가면서 이 서비스는 <b>더 이상 크롤링도 AI 도 하지 않는다.</b> 전부 {@link ArchiveCrawlProcessor} 의
   * 몫이다 — 한 가지 일을 두 곳에서 하지 않게 됐다.
   */
  public ArchiveItemService(
      ArchiveFolderRepository archiveFolderRepository,
      ArchiveItemRepository archiveItemRepository,
      ArchiveItemTagRepository archiveItemTagRepository,
      ArchiveLikeRepository archiveLikeRepository,
      ArchiveItemCommentRepository archiveItemCommentRepository,
      RoomMemberRepository roomMemberRepository,
      RoomRepository roomRepository,
      UserRepository userRepository,
      UrlSafetyValidator urlSafetyValidator,
      ArchiveCrawlProcessor archiveCrawlProcessor,
      ArchiveSummaryFiller summaryFiller,
      ActivityService activityService,
      UserActivityRecorder userActivityRecorder,
      Optional<ObjectStorage> objectStorage) {
    this.archiveFolderRepository = archiveFolderRepository;
    this.archiveItemRepository = archiveItemRepository;
    this.archiveItemTagRepository = archiveItemTagRepository;
    this.archiveLikeRepository = archiveLikeRepository;
    this.archiveItemCommentRepository = archiveItemCommentRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.roomRepository = roomRepository;
    this.userRepository = userRepository;
    this.urlSafetyValidator = urlSafetyValidator;
    this.archiveCrawlProcessor = archiveCrawlProcessor;
    this.summaryFiller = summaryFiller;
    this.activityService = activityService;
    this.userActivityRecorder = userActivityRecorder;
    this.objectStorage = objectStorage;
  }

  /**
   * 폴더 직접 업로드 이미지(V28)의 MinIO presigned PUT 업로드 URL 발급 — {@link
   * com.nomara.modi.server.domain.todo.service.TodoImageService#createUploadUrl}과 같은 패턴.
   */
  @Transactional(readOnly = true)
  public ArchiveImageUploadUrlResponse createImageUploadUrl(String uid, Long roomId) {
    requireMembership(uid, roomId);
    ObjectStorage storage =
        objectStorage.orElseThrow(() -> new ServiceUnavailableException("이미지 업로드가 지금은 지원되지 않아요"));
    // "archive/" 로 시작해야 MinioConfig.publicReadPolicy 의 공개 읽기 접두사(인스타 썸네일용으로
    // 이미 열려 있음)에 걸린다. 다른 접두사(예: archive-images/)를 쓰면 업로드는 성공하고 앱에서만
    // 403 이 나는 함정을 반복한다(사고 재현, 이번에 실제로 겪음).
    String objectKey = "archive/images/" + roomId + "/" + UUID.randomUUID();
    return new ArchiveImageUploadUrlResponse(
        storage.createPresignedUploadUrl(objectKey, IMAGE_UPLOAD_URL_EXPIRY),
        storage.publicUrl(objectKey));
  }

  /** 텍스트 등록의 제목 — 본문 앞부분이다. LLM 을 부르지 않으므로 등록 시점에 그대로 정한다. */
  private static String textTitle(String text) {
    String title =
        text.length() > MAX_TEXT_TITLE_PREVIEW
            ? ArchiveTextLimits.truncate(text, MAX_TEXT_TITLE_PREVIEW) + "…"
            : text;
    return ArchiveTextLimits.truncate(title, MAX_TITLE_LENGTH);
  }

  /**
   * 자료 등록(S-25-C). <b>{@code PENDING} 으로 저장하고 즉시 응답한다</b> — 크롤링·요약·임베딩·태깅은 {@link
   * ArchiveCrawlProcessor} 가 백그라운드에서 한다(2026-08-06).
   *
   * <p>🔴 <b>왜 비동기로 바꿨나.</b> 예전에는 이 메서드가 HTTP 응답 전에 외부 호출을 4회 돌았다 — 크롤링 1 + LLM 3. 문서화된 최악 대기가 약
   * 198초였고, 사용자는 [등록]을 누른 채 그동안 화면에 묶여 있었다. 실측으로도 텍스트 한 줄 등록에 13초가 걸렸다. 공유 경로(S-25-D)는 이미 같은 이유로
   * 비동기라, 두 경로가 이제 같은 모양이 된다.
   *
   * <p><b>주소 검증만 동기로 남긴다</b>({@link UrlSafetyValidator}). 오타·사설망 주소는 등록 시점에 400 으로 즉시 알려주는 편이 낫다 —
   * 그것까지 뒤로 미루면 사용자가 잘못 붙여넣은 링크도 일단 등록됐다가 나중에 "분석 실패"로 나타난다. ⚠️ 이 검증은 DNS 를 한 번 탄다.
   *
   * <p><b>제목은 나중에 크롤링 결과로 바뀐다.</b> URL 등록은 사용자가 제목을 적지 않으므로 URL 자체를 제목으로 넣어 두고, {@code
   * ArchiveItem.markCrawlDone} 이 <b>아직 URL 그대로일 때만</b> 교체한다(공유 경로와 같은 규칙). 텍스트 등록은 지금처럼 본문 앞부분을
   * 제목으로 쓴다 — LLM 이 필요 없다.
   *
   * <p>{@code @Transactional} 을 걸지 않는 것은 그대로다. 이제 남은 것은 조회 두 번과 저장 한 번뿐이라 붙잡을 커넥션도 짧다.
   */
  public ArchiveItemDetailResponse createItem(
      String uid, Long roomId, Long folderId, CreateArchiveItemRequest request) {
    requireMembership(uid, roomId);
    ArchiveFolder folder = resolveFolder(roomId, folderId);

    String url = blankToNull(request.url());
    String text = blankToNull(request.text());
    String imageUrl = blankToNull(request.imageUrl());
    int filled = (url != null ? 1 : 0) + (text != null ? 1 : 0) + (imageUrl != null ? 1 : 0);
    if (filled != 1) {
      throw new BadRequestException("링크·텍스트·이미지 중 하나를 입력해 주세요");
    }
    if (url != null && url.length() > MAX_URL_INPUT_LENGTH) {
      throw new BadRequestException("링크가 너무 길어요");
    }
    if (text != null && text.length() > MAX_TEXT_INPUT_LENGTH) {
      throw new BadRequestException("텍스트가 너무 길어요");
    }
    if (url != null) {
      try {
        urlSafetyValidator.validate(url);
      } catch (CrawlException e) {
        throw new BadRequestException(e.getMessage(), e);
      }
    }
    String memo = blankToNull(request.memo());
    if (memo != null && memo.length() > ArchiveTextLimits.MAX_MEMO) {
      throw new BadRequestException("메모가 너무 길어요");
    }

    User createdBy = userRepository.findById(uid).orElseThrow();
    if (imageUrl != null) {
      // 폴더 직접 업로드 이미지(V28) — 크롤링·AI 태깅/요약/임베딩 대상이 아니라 곧바로 DONE이고
      // dispatchCrawl을 타지 않는다(투두 첨부 이미지와 같은 원칙, todo-image-archive-handoff.md).
      String imageTitle = blankToNull(request.title());
      ArchiveItem imageItem =
          ArchiveItem.imageDone(
              folder,
              folder.getRoom(),
              imageTitle != null ? ArchiveTextLimits.truncate(imageTitle, MAX_TITLE_LENGTH) : "사진",
              imageUrl,
              createdBy,
              memo);
      ArchiveItem savedImage = archiveItemRepository.save(imageItem);
      activityService.record(
          folder.getRoom(), ActivityType.ARCHIVE_ADDED, createdBy, null, folder.getName(), null);
      return buildDetail(savedImage, uid);
    }

    ArchiveItem pending =
        url != null
            // 제목 자리에 URL 을 넣는다 — 크롤링이 끝나면 진짜 제목으로 바뀐다.
            ? ArchiveItem.pending(
                folder,
                folder.getRoom(),
                ArchiveTextLimits.truncate(url, MAX_TITLE_LENGTH),
                url,
                createdBy,
                memo)
            : ArchiveItem.textDone(
                folder,
                folder.getRoom(),
                textTitle(text),
                ArchiveTextLimits.truncate(text, MAX_BODY_TEXT_LENGTH),
                createdBy,
                memo);

    ArchiveItem saved = archiveItemRepository.save(pending);
    dispatchCrawl(saved);
    activityService.record(
        folder.getRoom(), ActivityType.ARCHIVE_ADDED, createdBy, null, folder.getName(), null);
    return buildDetail(saved, uid);
  }

  /**
   * 폴더 미지정 자료 등록(백엔드 요청, 2026-08-07) — "기본" 폴더(없으면 새로 만듦)에 등록하고, 나머지는 {@link #createItem}에 그대로
   * 위임한다(검증·크롤링 디스패치·활동 기록을 중복하지 않는다).
   */
  public ArchiveItemDetailResponse createItemInDefaultFolder(
      String uid, Long roomId, CreateArchiveItemRequest request) {
    ArchiveFolder defaultFolder = resolveOrCreateDefaultFolder(roomId);
    return createItem(uid, roomId, defaultFolder.getId(), request);
  }

  private ArchiveFolder resolveOrCreateDefaultFolder(Long roomId) {
    return archiveFolderRepository
        .findFirstByRoomIdAndName(roomId, ArchiveFolder.DEFAULT_FOLDER_NAME)
        .orElseGet(
            () -> {
              Room room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
              return archiveFolderRepository.save(
                  new ArchiveFolder(room, ArchiveFolder.DEFAULT_FOLDER_NAME));
            });
  }

  /**
   * S-25-D 외부 공유 등록(네이티브 Android/iOS). <b>URL 이든 텍스트든 {@code PENDING}으로 즉시 저장하고 {@link
   * ArchiveCrawlProcessor}에 넘긴 뒤 바로 응답한다</b> — 네이티브 공유 시트는 등록 확인만 받고 닫혀야 한다
   * (specs/0014-외부-공유-등록.md).
   *
   * <p>🔴 <b>텍스트도 비동기가 된 이유</b>(2026-08-05): 예전엔 텍스트만 동기로 {@code DONE} 등록했다 — "크롤링이 없으니 빠르다"는 전제였는데
   * <b>틀렸다.</b> 크롤링은 없어도 태깅·요약·임베딩으로 LLM 을 3번 부른다. 그게 네이티브 공유 시트의 클라이언트 타임아웃(5초)을 넘겨 <b>서버는 성공했는데
   * 앱에는 "등록하지 못했어요"가 뜨고</b>, 사용자가 다시 누르면 중복이 쌓였다({@code ShareActivity} 의 {@code SocketException:
   * Socket closed}). 두 경로를 같은 모양으로 맞춰 원인을 없앤다 — <b>그래서 클라이언트 타임아웃은 늘리지 않는다.</b>
   *
   * <p>S-25-C 앱 안 등록({@link #createItem})은 그대로 동기다 — 거기엔 5초 제약이 없고 사용자가 결과를 보고 있다.
   */
  public ArchiveItemDetailResponse createSharedItem(
      String uid, Long roomId, Long folderId, CreateSharedArchiveItemRequest request) {
    requireMembership(uid, roomId);
    ArchiveFolder folder = resolveFolder(roomId, folderId);

    if (blankToNull(request.title()) == null) {
      throw new BadRequestException("제목을 입력해 주세요");
    }
    String url = blankToNull(request.url());
    String text = blankToNull(request.text());
    if ((url == null) == (text == null)) {
      throw new BadRequestException("링크 또는 텍스트 중 하나를 입력해 주세요");
    }
    if (url != null && url.length() > MAX_URL_INPUT_LENGTH) {
      throw new BadRequestException("링크가 너무 길어요");
    }
    if (text != null && text.length() > MAX_TEXT_INPUT_LENGTH) {
      throw new BadRequestException("텍스트가 너무 길어요");
    }

    String title = ArchiveTextLimits.truncate(request.title(), MAX_TITLE_LENGTH);

    User createdBy = userRepository.findById(uid).orElseThrow();

    ArchiveItem pending =
        url != null
            ? ArchiveItem.pending(folder, folder.getRoom(), title, url, createdBy)
            : ArchiveItem.textDone(
                folder,
                folder.getRoom(),
                title,
                ArchiveTextLimits.truncate(text, MAX_BODY_TEXT_LENGTH),
                createdBy);

    ArchiveItem saved = archiveItemRepository.save(pending);
    dispatchCrawl(saved);
    activityService.record(
        folder.getRoom(), ActivityType.ARCHIVE_ADDED, createdBy, null, folder.getName(), null);
    return buildDetail(saved, uid);
  }

  /**
   * 처리기에 넘긴다. <b>큐가 차면 배치가 주워가게 예약만 남긴다</b>(2026-08-06 리뷰 P2).
   *
   * <p>🔴 <b>여기가 "영구 PENDING" 의 입구였다.</b> {@code archiveCrawlExecutor} 는 {@code AbortPolicy} 라
   * 큐(50)가 차면 {@code RejectedExecutionException} 을 던진다. 이 메서드는 {@code @Transactional} 이 아니라 위
   * {@code save()} 가 이미 커밋된 뒤이므로, 예전에는 <b>행은 {@code PENDING} 으로 남고 사용자에겐 500</b> 이 갔다. 스위퍼가 없어 그
   * 항목은 "분석 중" 배지가 영원히 붙은 채 요약·임베딩·태그가 누락됐다({@code specs/OPEN.md}).
   *
   * <p>이제 {@code next_crawl_at} 만 찍어 두면 {@code ArchiveCrawlRetryScheduler} 가 다음 tick 에 주워간다 — 등록은
   * 성공으로 끝나고 사용자는 평소처럼 "분석 중"을 본다.
   *
   * <p><b>재시도 횟수는 올리지 않는다</b> — 실패한 것이 아니라 보내지도 못한 것이다(배치의 {@code rescheduleCrawl} 과 같은 원칙).
   */
  private void dispatchCrawl(ArchiveItem saved) {
    try {
      archiveCrawlProcessor.process(saved.getId());
    } catch (RejectedExecutionException e) {
      saved.delayCrawlRetry(Instant.now().plus(QUEUE_FULL_RETRY_DELAY));
      archiveItemRepository.save(saved);
      log.warn("크롤링 큐가 차서 배치에 넘긴다: itemId={}", saved.getId(), e);
    }
  }

  private String blankToNull(String value) {
    return (value == null || value.isBlank()) ? null : value;
  }

  @Transactional(readOnly = true)
  public ArchiveFolderItemsResponse listItems(String uid, Long roomId, Long folderId) {
    requireMembership(uid, roomId);
    ArchiveFolder folder = resolveFolder(roomId, folderId);

    // 핀 고정 항목은 항상 최상단 — pinned desc, createdAt desc.
    List<ArchiveItem> items =
        archiveItemRepository.findByFolderIdOrderByPinnedDescCreatedAtDesc(folderId);
    if (items.isEmpty()) {
      return new ArchiveFolderItemsResponse(folder.getId(), folder.getName(), List.of());
    }

    List<Long> itemIds = items.stream().map(ArchiveItem::getId).toList();

    Map<Long, List<String>> tagsByItemId = new HashMap<>();
    for (ArchiveItemTag tag : archiveItemTagRepository.findByItemIdIn(itemIds)) {
      tagsByItemId
          .computeIfAbsent(tag.getItem().getId(), key -> new ArrayList<>())
          .add(tag.getId().getTag());
    }

    Map<Long, Long> likesByItemId = new HashMap<>();
    for (ArchiveLikeRepository.ItemLikeCount row :
        archiveLikeRepository.countByItemIdForFolder(folderId)) {
      likesByItemId.put(row.getItemId(), row.getLikeCount());
    }

    List<ArchiveItemResponse> responses =
        items.stream()
            .map(
                item ->
                    ArchiveItemResponse.of(
                        item,
                        tagsByItemId.getOrDefault(item.getId(), List.of()),
                        likesByItemId.getOrDefault(item.getId(), 0L)))
            .collect(Collectors.toList());

    return new ArchiveFolderItemsResponse(folder.getId(), folder.getName(), responses);
  }

  @Transactional(readOnly = true)
  public ArchiveItemDetailResponse getDetail(String uid, Long roomId, Long itemId) {
    requireMembership(uid, roomId);
    ArchiveItem item = resolveItem(roomId, itemId);
    userActivityRecorder.record(uid, UserActivityKind.ARCHIVE_ITEM_VIEW, item.getRoom(), itemId);
    return buildDetail(item, uid);
  }

  /**
   * AI 요약을 지금 만든다(2026-08-06 사용자 확정 — S-25-B 「AI 요약 만들기」).
   *
   * <p><b>왜 버튼인가.</b> 텍스트로 등록한 자료는 자동 요약을 하지 않게 바꿨다 — 사용자가 직접 적은 짧은 메모는 본문이 곧 요약이라 얻는 것이 거의 없으면서
   * LLM 호출만 쓴다. 링크 자료의 자동 요약은 그대로다(본문이 길어 요약이 값을 한다).
   *
   * <p><b>요약이 이미 있으면 거절한다.</b> 다시 만들 이유가 없고, 그 규칙이 <b>남용 방지도 겸한다</b> — 한 번 성공하면 그 자료로는 더 못 부르므로 별도
   * 레이트 리밋을 두지 않았다. 실패하면 다시 누를 수 있는데, 그건 사용자 인내심이 상한이다.
   *
   * <p>⚠️ <b>{@code @Transactional} 안에서 외부 호출을 2회 돈다</b>(요약 + 임베딩, 약 1.3~4초). 사용자가 버튼을 누르고 기다리는 동기
   * 경로다 — 등록 경로를 비동기로 옮긴 것과 방향이 반대로 보이지만, 여기는 <b>명시적으로 요청한 작업이고 화면에 스피너가 있다</b>는 점이 다르다. 더 길어지면 이
   * 판단을 다시 볼 것.
   */
  @Transactional
  public ArchiveItemDetailResponse summarizeItem(String uid, Long roomId, Long itemId) {
    requireMembership(uid, roomId);
    ArchiveItem item = resolveItem(roomId, itemId);
    if (item.getSummary() != null) {
      throw new BadRequestException("이미 요약이 있어요");
    }
    if (item.getBodyText() == null || item.getBodyText().isBlank()) {
      // 크롤링이 아직 안 끝났거나(PENDING) 실패한 자료 — 요약할 본문이 없다.
      throw new BadRequestException("아직 요약할 내용이 없어요");
    }
    if (!summaryFiller.fill(item)) {
      throw new BadRequestException("요약을 만들지 못했어요. 잠시 후 다시 시도해 주세요");
    }
    return buildDetail(item, uid);
  }

  @Transactional
  public ArchiveItemDetailResponse setPinned(
      String uid, Long roomId, Long itemId, SetItemPinnedRequest request) {
    requireMembership(uid, roomId);
    ArchiveItem item = resolveItem(roomId, itemId);
    if (request.pinned()) {
      item.pin();
    } else {
      item.unpin();
    }
    return buildDetail(item, uid);
  }

  @Transactional
  public ArchiveItemDetailResponse setLiked(
      String uid, Long roomId, Long itemId, SetItemLikedRequest request) {
    requireMembership(uid, roomId);
    ArchiveItem item = resolveItem(roomId, itemId);
    ArchiveLikeId likeId = new ArchiveLikeId(itemId, uid);
    if (request.liked()) {
      if (!archiveLikeRepository.existsById(likeId)) {
        User user = userRepository.findById(uid).orElseThrow();
        archiveLikeRepository.save(new ArchiveLike(item, user));
        // 홈 활동 피드 ARCHIVE_LIKE_MILESTONE(2026-08-06) — actor는 좋아요를 받은 자료의
        // 작성자다. 작성자가 탈퇴했으면(created_by null) 알려줄 사람이 없어 건너뛴다.
        if (item.getCreatedBy() != null) {
          long likeCount = archiveLikeRepository.countByItemId(itemId);
          if (activityService.isMilestone(likeCount)) {
            activityService.record(
                item.getRoom(),
                ActivityType.ARCHIVE_LIKE_MILESTONE,
                item.getCreatedBy(),
                null,
                item.getTitle(),
                (int) likeCount);
          }
        }
      }
    } else {
      if (archiveLikeRepository.existsById(likeId)) {
        archiveLikeRepository.deleteById(likeId);
      }
    }
    return buildDetail(item, uid);
  }

  @Transactional
  public ArchiveItemDetailResponse moveToFolder(
      String uid, Long roomId, Long itemId, MoveItemFolderRequest request) {
    requireMembership(uid, roomId);
    ArchiveItem item = resolveItem(roomId, itemId);
    ArchiveFolder folder = resolveFolder(roomId, request.folderId());
    item.moveToFolder(folder);
    return buildDetail(item, uid);
  }

  /** 메모 편집(S-25-B, 2026-08-06) — 단순 필드 갱신이라 외부 호출이 없다({@code setPinned}과 같은 형태). */
  @Transactional
  public ArchiveItemDetailResponse updateMemo(
      String uid, Long roomId, Long itemId, UpdateItemMemoRequest request) {
    requireMembership(uid, roomId);
    ArchiveItem item = resolveItem(roomId, itemId);
    String memo = blankToNull(request.memo());
    if (memo != null && memo.length() > ArchiveTextLimits.MAX_MEMO) {
      throw new BadRequestException("메모가 너무 길어요");
    }
    item.editMemo(memo);
    return buildDetail(item, uid);
  }

  /**
   * 링크 편집(S-25-B, 2026-08-06) — 새 URL로 재분석해야 하므로 항목을 {@code PENDING}으로 되돌리고 {@link #dispatchCrawl}로
   * 비동기 재크롤링을 건다. 텍스트(메모형) 항목이나 이미 분석 중인 항목은 대상이 아니다.
   *
   * <p>{@code @Transactional}을 걸지 않는다 — {@code createItem}/{@code createSharedItem}과 같은 이유다. 커밋 전에
   * 비동기 스레드가 먼저 조회하면 옛 상태를 읽는 경합이 생긴다.
   */
  public ArchiveItemDetailResponse updateUrl(
      String uid, Long roomId, Long itemId, UpdateItemUrlRequest request) {
    requireMembership(uid, roomId);
    ArchiveItem item = resolveItem(roomId, itemId);
    if (item.getUrl() == null) {
      throw new BadRequestException("링크 자료만 링크를 수정할 수 있어요");
    }
    if (item.getCrawlStatus() == ArchiveItem.CrawlStatus.PENDING) {
      throw new BadRequestException("분석 중에는 수정할 수 없어요");
    }
    String url = blankToNull(request.url());
    if (url == null) {
      throw new BadRequestException("링크를 입력해 주세요");
    }
    if (url.length() > MAX_URL_INPUT_LENGTH) {
      throw new BadRequestException("링크가 너무 길어요");
    }
    try {
      urlSafetyValidator.validate(url);
    } catch (CrawlException e) {
      throw new BadRequestException(e.getMessage(), e);
    }
    // 옛 URL 콘텐츠 기반 태그를 지운다 — ArchiveCrawlProcessor는 새 태그를 추가만 하고 지우지
    // 않는다(원래 태그가 없는 신규 PENDING 항목 전용이었다). 여기서 안 지우면 재크롤링 뒤 옛
    // 태그와 새 태그가 섞여 남는다.
    //
    // ⚠️ deleteByItemId(파생 삭제 쿼리)가 아니라 deleteAll(CrudRepository 기본 메서드)을 쓴다 —
    // 이 메서드는 이 서비스의 다른 mutate 메서드들과 달리 @Transactional이 아니라서(아래 주석),
    // 파생 삭제 쿼리는 "현재 스레드에 트랜잭션이 없다"로 실패한다. 기본 CRUD 메서드는 자체
    // @Transactional을 갖고 있어 트랜잭션 없이 호출해도 스스로 하나를 연다.
    archiveItemTagRepository.deleteAll(archiveItemTagRepository.findByItemId(itemId));
    item.editUrl(url, ArchiveTextLimits.truncate(url, MAX_TITLE_LENGTH));
    archiveItemRepository.save(item);
    dispatchCrawl(item);
    // 🔴 응답은 save() 가 돌려준 인스턴스가 아니라 **resolveItem 이 돌려준 item** 으로 만든다.
    //
    // 이 메서드는 (위 주석대로) @Transactional 이 아니라서 resolveItem 이 돌려준 엔티티가 detached 다.
    // 그러면 save() 는 persist 가 아니라 merge 이고, merge 는 인자를 관리 상태로 바꾸는 것이 아니라
    // **복사본을 새로 만들어 돌려준다** — 그 복사본의 folder/createdBy 는 미초기화 프록시라, 그것으로
    // 응답을 만들면 트랜잭션이 닫힌 뒤 폴더 이름을 읽다가 LazyInitializationException 이 난다.
    // 상세 응답에 folderName·createdBy 가 들어오기 전에는 식별자만 읽어서(getFolder().getId())
    // 드러나지 않던 함정이다. 2026-08-08 실측으로 ArchiveItemUrlEditTest 3건이 이걸 잡았다.
    //
    // 저장 후 다시 읽는 방법은 쓸 수 없다 — 바로 위 dispatchCrawl 이 (테스트의 동기 실행기에서는)
    // 그 자리에서 크롤링을 끝내 버려서, 다시 읽으면 "응답은 항상 PENDING" 이라는 이 API 의 계약이
    // 깨진다. item 은 우리가 방금 고친 값(새 URL · PENDING)을 그대로 들고 있다.
    return buildDetail(item, uid);
  }

  @Transactional
  public ArchiveItemDetailResponse updateTags(
      String uid, Long roomId, Long itemId, UpdateItemTagsRequest request) {
    requireMembership(uid, roomId);
    ArchiveItem item = resolveItem(roomId, itemId);
    archiveItemTagRepository.deleteByItemId(itemId);
    for (String tag : new LinkedHashSet<>(request.tags())) {
      archiveItemTagRepository.save(new ArchiveItemTag(item, tag.trim()));
    }
    return buildDetail(item, uid);
  }

  @Transactional
  public void deleteItem(String uid, Long roomId, Long itemId) {
    requireMembership(uid, roomId);
    ArchiveItem item = resolveItem(roomId, itemId);
    // 하위 archive_item_tags/archive_likes는 DB ON DELETE CASCADE로 함께 삭제된다(specs/0002-data-model.md).
    archiveItemRepository.delete(item);
  }

  private ArchiveItemDetailResponse buildDetail(ArchiveItem item, String uid) {
    List<String> tags =
        archiveItemTagRepository.findByItemId(item.getId()).stream()
            .map(tag -> tag.getId().getTag())
            .toList();
    long likeCount = archiveLikeRepository.countByItemId(item.getId());
    boolean likedByMe = archiveLikeRepository.existsById(new ArchiveLikeId(item.getId(), uid));
    long commentCount = archiveItemCommentRepository.countByItemId(item.getId());
    return ArchiveItemDetailResponse.of(item, tags, likeCount, likedByMe, commentCount);
  }

  /**
   * 상세 응답을 만들 항목을 찾는다. {@code folder}·{@code createdBy}를 함께 가져오는 이유(쿼리 수)는 {@link
   * ArchiveItemRepository#findForDetailById}에 적어 뒀다.
   */
  private ArchiveItem resolveItem(Long roomId, Long itemId) {
    ArchiveItem item =
        archiveItemRepository
            .findForDetailById(itemId)
            .orElseThrow(ArchiveItemNotFoundException::new);
    if (!item.getRoom().getId().equals(roomId)) {
      throw new ArchiveItemNotFoundException();
    }
    return item;
  }

  private ArchiveFolder resolveFolder(Long roomId, Long folderId) {
    ArchiveFolder folder =
        archiveFolderRepository.findById(folderId).orElseThrow(ArchiveFolderNotFoundException::new);
    if (!folder.getRoom().getId().equals(roomId)) {
      throw new ArchiveFolderNotFoundException();
    }
    return folder;
  }

  private void requireMembership(String uid, Long roomId) {
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, uid))) {
      throw new NotRoomMemberException();
    }
  }
}
