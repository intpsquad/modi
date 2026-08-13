package com.nomara.modi.server.domain.archive.controller;

import com.nomara.modi.server.domain.archive.dto.ArchiveFolderResponse;
import com.nomara.modi.server.domain.archive.dto.CreateArchiveFolderRequest;
import com.nomara.modi.server.domain.archive.dto.UpdateArchiveFolderRequest;
import com.nomara.modi.server.domain.archive.service.ArchiveFolderService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** specs/0010-아카이브-탭.md — 아카이브 폴더 CRUD(S-25). */
@RestController
public class ArchiveFolderController {

  private final ArchiveFolderService archiveFolderService;

  public ArchiveFolderController(ArchiveFolderService archiveFolderService) {
    this.archiveFolderService = archiveFolderService;
  }

  @GetMapping("/rooms/{roomId}/archive/folders")
  public List<ArchiveFolderResponse> list(HttpServletRequest request, @PathVariable Long roomId) {
    return archiveFolderService.listFolders(uid(request), roomId);
  }

  @PostMapping("/rooms/{roomId}/archive/folders")
  @ResponseStatus(HttpStatus.CREATED)
  public ArchiveFolderResponse create(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @Valid @RequestBody CreateArchiveFolderRequest body) {
    return archiveFolderService.createFolder(uid(request), roomId, body);
  }

  @PatchMapping("/rooms/{roomId}/archive/folders/{folderId}")
  public ArchiveFolderResponse rename(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @PathVariable Long folderId,
      @Valid @RequestBody UpdateArchiveFolderRequest body) {
    return archiveFolderService.renameFolder(uid(request), roomId, folderId, body);
  }

  @DeleteMapping("/rooms/{roomId}/archive/folders/{folderId}")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void delete(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable Long folderId) {
    archiveFolderService.deleteFolder(uid(request), roomId, folderId);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
