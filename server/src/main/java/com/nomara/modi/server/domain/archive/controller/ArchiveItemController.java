package com.nomara.modi.server.domain.archive.controller;

import com.nomara.modi.server.domain.archive.dto.ArchiveFolderItemsResponse;
import com.nomara.modi.server.domain.archive.dto.ArchiveImageUploadUrlResponse;
import com.nomara.modi.server.domain.archive.dto.ArchiveItemDetailResponse;
import com.nomara.modi.server.domain.archive.dto.CreateArchiveItemRequest;
import com.nomara.modi.server.domain.archive.dto.CreateSharedArchiveItemRequest;
import com.nomara.modi.server.domain.archive.dto.MoveItemFolderRequest;
import com.nomara.modi.server.domain.archive.dto.SetItemLikedRequest;
import com.nomara.modi.server.domain.archive.dto.SetItemPinnedRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateItemMemoRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateItemTagsRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateItemUrlRequest;
import com.nomara.modi.server.domain.archive.service.ArchiveItemService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** specs/0010-아카이브-탭.md — S-25-A 폴더 내 항목 목록(읽기 전용) + S-25-B 항목 상세/조작 + S-25-C 자료 등록. */
@RestController
public class ArchiveItemController {

  private final ArchiveItemService archiveItemService;

  public ArchiveItemController(ArchiveItemService archiveItemService) {
    this.archiveItemService = archiveItemService;
  }

  @GetMapping("/rooms/{roomId}/archive/folders/{folderId}/items")
  public ArchiveFolderItemsResponse list(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable Long folderId) {
    return archiveItemService.listItems(uid(request), roomId, folderId);
  }

  @PostMapping("/rooms/{roomId}/archive/folders/{folderId}/items")
  @ResponseStatus(HttpStatus.CREATED)
  public ArchiveItemDetailResponse create(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long folderId,
      @RequestBody CreateArchiveItemRequest body) {
    return archiveItemService.createItem(uid(request), roomId, folderId, body);
  }

  /** 폴더 미지정 자료 등록(백엔드 요청, 2026-08-07) — "기본" 폴더로 들어간다. */
  @PostMapping("/rooms/{roomId}/archive/items")
  @ResponseStatus(HttpStatus.CREATED)
  public ArchiveItemDetailResponse createInDefaultFolder(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @RequestBody CreateArchiveItemRequest body) {
    return archiveItemService.createItemInDefaultFolder(uid(request), roomId, body);
  }

  @PostMapping("/rooms/{roomId}/archive/folders/{folderId}/items/pending")
  @ResponseStatus(HttpStatus.CREATED)
  public ArchiveItemDetailResponse createShared(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long folderId,
      @Valid @RequestBody CreateSharedArchiveItemRequest body) {
    return archiveItemService.createSharedItem(uid(request), roomId, folderId, body);
  }

  /** 폴더 직접 업로드 이미지(V28)의 MinIO presigned PUT 업로드 URL 발급. */
  @PostMapping("/rooms/{roomId}/archive/items/image/upload-url")
  public ArchiveImageUploadUrlResponse createImageUploadUrl(
      HttpServletRequest request, @PathVariable Long roomId) {
    return archiveItemService.createImageUploadUrl(uid(request), roomId);
  }

  @GetMapping("/rooms/{roomId}/archive/items/{itemId}")
  public ArchiveItemDetailResponse detail(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable Long itemId) {
    return archiveItemService.getDetail(uid(request), roomId, itemId);
  }

  /**
   * AI 요약을 지금 만든다(2026-08-06).
   *
   * <p>텍스트로 등록한 자료는 자동 요약을 하지 않는다 — 짧은 메모는 본문이 곧 요약이라 얻는 것이 적으면서 LLM 호출만 쓴다. 필요한 사람이 자료 상세에서 이걸
   * 부른다. 요약이 실패했던 링크 자료도 같은 경로로 되살릴 수 있다.
   *
   * <p><b>요약이 이미 있으면 거절한다</b>(400). 다시 만들 이유가 없고, 그 규칙이 남용 방지도 겸한다 — 한 번 성공하면 그 자료로는 더 부를 수 없다.
   */
  @PostMapping("/rooms/{roomId}/archive/items/{itemId}/summary")
  public ArchiveItemDetailResponse summarize(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable Long itemId) {
    return archiveItemService.summarizeItem(uid(request), roomId, itemId);
  }

  @PatchMapping("/rooms/{roomId}/archive/items/{itemId}/pin")
  public ArchiveItemDetailResponse setPinned(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long itemId,
      @Valid @RequestBody SetItemPinnedRequest body) {
    return archiveItemService.setPinned(uid(request), roomId, itemId, body);
  }

  @PatchMapping("/rooms/{roomId}/archive/items/{itemId}/like")
  public ArchiveItemDetailResponse setLiked(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long itemId,
      @Valid @RequestBody SetItemLikedRequest body) {
    return archiveItemService.setLiked(uid(request), roomId, itemId, body);
  }

  @PatchMapping("/rooms/{roomId}/archive/items/{itemId}/folder")
  public ArchiveItemDetailResponse moveToFolder(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long itemId,
      @Valid @RequestBody MoveItemFolderRequest body) {
    return archiveItemService.moveToFolder(uid(request), roomId, itemId, body);
  }

  @PatchMapping("/rooms/{roomId}/archive/items/{itemId}/memo")
  public ArchiveItemDetailResponse updateMemo(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long itemId,
      @RequestBody UpdateItemMemoRequest body) {
    return archiveItemService.updateMemo(uid(request), roomId, itemId, body);
  }

  @PatchMapping("/rooms/{roomId}/archive/items/{itemId}/url")
  public ArchiveItemDetailResponse updateUrl(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long itemId,
      @RequestBody UpdateItemUrlRequest body) {
    return archiveItemService.updateUrl(uid(request), roomId, itemId, body);
  }

  @PatchMapping("/rooms/{roomId}/archive/items/{itemId}/tags")
  public ArchiveItemDetailResponse updateTags(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long itemId,
      @Valid @RequestBody UpdateItemTagsRequest body) {
    return archiveItemService.updateTags(uid(request), roomId, itemId, body);
  }

  @DeleteMapping("/rooms/{roomId}/archive/items/{itemId}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void delete(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable Long itemId) {
    archiveItemService.deleteItem(uid(request), roomId, itemId);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
