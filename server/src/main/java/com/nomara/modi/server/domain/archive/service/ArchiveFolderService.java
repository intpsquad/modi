package com.nomara.modi.server.domain.archive.service;

import com.nomara.modi.server.domain.archive.dto.ArchiveFolderResponse;
import com.nomara.modi.server.domain.archive.dto.CreateArchiveFolderRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateArchiveFolderRequest;
import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import com.nomara.modi.server.domain.archive.entity.ArchiveItem;
import com.nomara.modi.server.domain.archive.exception.ArchiveFolderNotFoundException;
import com.nomara.modi.server.domain.archive.repository.ArchiveFolderRepository;
import com.nomara.modi.server.domain.archive.repository.ArchiveItemRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.exception.RoomNotFoundException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.global.exception.BadRequestException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** specs/0010-아카이브-탭.md — S-25 폴더 목록/추가/이름수정/삭제. */
@Service
public class ArchiveFolderService {

  private final ArchiveFolderRepository archiveFolderRepository;
  private final ArchiveItemRepository archiveItemRepository;
  private final RoomRepository roomRepository;
  private final RoomMemberRepository roomMemberRepository;

  public ArchiveFolderService(
      ArchiveFolderRepository archiveFolderRepository,
      ArchiveItemRepository archiveItemRepository,
      RoomRepository roomRepository,
      RoomMemberRepository roomMemberRepository) {
    this.archiveFolderRepository = archiveFolderRepository;
    this.archiveItemRepository = archiveItemRepository;
    this.roomRepository = roomRepository;
    this.roomMemberRepository = roomMemberRepository;
  }

  @Transactional
  public List<ArchiveFolderResponse> listFolders(String uid, Long roomId) {
    requireMembership(uid, roomId);
    ensureDefaultFolder(roomId);
    List<ArchiveFolder> folders = archiveFolderRepository.findByRoomIdOrderByCreatedAtAsc(roomId);

    Map<Long, Long> itemCounts = new HashMap<>();
    for (ArchiveItemRepository.FolderItemCount row :
        archiveItemRepository.countByFolderIdForRoom(roomId)) {
      itemCounts.put(row.getFolderId(), row.getItemCount());
    }

    // 최신순으로 훑으므로 폴더당 처음 나오는 것(=가장 최근에 썸네일이 있는 항목)만 남는다.
    Map<Long, String> thumbnails = new HashMap<>();
    for (ArchiveItemRepository.FolderThumbnail row :
        archiveItemRepository.findThumbnailCandidatesForRoom(roomId)) {
      thumbnails.putIfAbsent(row.getFolderId(), row.getThumbnail());
    }

    return folders.stream()
        .map(
            folder ->
                ArchiveFolderResponse.of(
                    folder,
                    itemCounts.getOrDefault(folder.getId(), 0L),
                    thumbnails.get(folder.getId())))
        .toList();
  }

  @Transactional
  public ArchiveFolderResponse createFolder(
      String uid, Long roomId, CreateArchiveFolderRequest request) {
    requireMembership(uid, roomId);
    Room room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
    ArchiveFolder saved = archiveFolderRepository.save(new ArchiveFolder(room, request.name()));
    return ArchiveFolderResponse.of(saved, 0L, null);
  }

  @Transactional
  public ArchiveFolderResponse renameFolder(
      String uid, Long roomId, Long folderId, UpdateArchiveFolderRequest request) {
    requireMembership(uid, roomId);
    ArchiveFolder folder = resolveFolder(roomId, folderId);
    folder.rename(request.name());
    return ArchiveFolderResponse.of(
        folder, archiveItemRepository.countByFolderId(folderId), resolveThumbnail(folderId));
  }

  private String resolveThumbnail(Long folderId) {
    return archiveItemRepository.findByFolderIdOrderByCreatedAtDesc(folderId).stream()
        .map(ArchiveItem::getThumbnail)
        .filter(Objects::nonNull)
        .findFirst()
        .orElse(null);
  }

  @Transactional
  public void deleteFolder(String uid, Long roomId, Long folderId) {
    requireMembership(uid, roomId);
    ArchiveFolder folder = resolveFolder(roomId, folderId);
    // 방마다 폴더 최소 1개 보장(백엔드 요청, 2026-08-07) — 이름이 "기본"인지는 안 보고 남은 폴더가
    // 1개뿐이면 무조건 막는다. 폴더 0개 상태를 원천적으로 안 만들면 이름에 의존할 필요가 없다.
    if (archiveFolderRepository.countByRoomId(roomId) <= 1) {
      throw new BadRequestException("마지막 폴더는 삭제할 수 없어요");
    }
    // 하위 archive_items/archive_item_tags/archive_likes는 DB ON DELETE CASCADE로 함께 삭제된다
    // (specs/0002-data-model.md) — 앱에서 파괴적 확인 모달을 거친 뒤에만 호출되는 엔드포인트다.
    archiveFolderRepository.delete(folder);
  }

  /** 방에 폴더가 0개면 "기본" 폴더를 만든다(백엔드 요청, 2026-08-07 — 기존 방 보정용). */
  private void ensureDefaultFolder(Long roomId) {
    if (archiveFolderRepository.countByRoomId(roomId) > 0) {
      return;
    }
    Room room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
    archiveFolderRepository.save(new ArchiveFolder(room, ArchiveFolder.DEFAULT_FOLDER_NAME));
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
