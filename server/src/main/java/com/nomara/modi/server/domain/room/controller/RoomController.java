package com.nomara.modi.server.domain.room.controller;

import com.nomara.modi.server.domain.room.dto.CoverImageResponse;
import com.nomara.modi.server.domain.room.dto.CreateRoomRequest;
import com.nomara.modi.server.domain.room.dto.InviteCodePreviewResponse;
import com.nomara.modi.server.domain.room.dto.InviteCodeResponse;
import com.nomara.modi.server.domain.room.dto.MemberBriefResponse;
import com.nomara.modi.server.domain.room.dto.MemberProgress;
import com.nomara.modi.server.domain.room.dto.PastRoomSummaryResponse;
import com.nomara.modi.server.domain.room.dto.RoomResponse;
import com.nomara.modi.server.domain.room.dto.RoomSummaryResponse;
import com.nomara.modi.server.domain.room.dto.UpdateRoomRequest;
import com.nomara.modi.server.domain.room.service.RoomCoverImageService;
import com.nomara.modi.server.domain.room.service.RoomService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/** specs/0004-방-생성-참여.md 기준 방 생성/초대코드 미리보기/참여 엔드포인트. */
@RestController
public class RoomController {

  private final RoomService roomService;
  private final RoomCoverImageService roomCoverImageService;

  public RoomController(RoomService roomService, RoomCoverImageService roomCoverImageService) {
    this.roomService = roomService;
    this.roomCoverImageService = roomCoverImageService;
  }

  @PostMapping("/rooms")
  @ResponseStatus(HttpStatus.CREATED)
  public RoomResponse create(
      HttpServletRequest request, @Valid @RequestBody CreateRoomRequest body) {
    return roomService.createRoom(uid(request), displayName(request), body);
  }

  @GetMapping("/rooms")
  public List<RoomSummaryResponse> listMine(HttpServletRequest request) {
    return roomService.listMyRooms(uid(request));
  }

  @GetMapping("/rooms/past")
  public List<PastRoomSummaryResponse> listPast(HttpServletRequest request) {
    return roomService.listPastRooms(uid(request));
  }

  @PatchMapping("/rooms/{roomId}")
  public RoomResponse update(
      HttpServletRequest request,
      @PathVariable Long roomId,
      @Valid @RequestBody UpdateRoomRequest body) {
    return roomService.updateRoom(uid(request), roomId, body);
  }

  @GetMapping("/rooms/{roomId}/invite-code")
  public InviteCodeResponse getInviteCode(HttpServletRequest request, @PathVariable Long roomId) {
    return roomService.getInviteCode(uid(request), roomId);
  }

  @PostMapping("/rooms/{roomId}/invite-code/reissue")
  public InviteCodeResponse reissueInviteCode(
      HttpServletRequest request, @PathVariable Long roomId) {
    return roomService.reissueInviteCode(uid(request), roomId);
  }

  @DeleteMapping("/rooms/{roomId}/members/me")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void leaveRoom(HttpServletRequest request, @PathVariable Long roomId) {
    roomService.leaveRoom(uid(request), roomId);
  }

  @GetMapping("/rooms/{roomId}/members")
  public List<MemberBriefResponse> listMembers(
      HttpServletRequest request, @PathVariable Long roomId) {
    return roomService.listMembers(uid(request), roomId);
  }

  @GetMapping("/rooms/{roomId}/members/progress")
  public List<MemberProgress> listMemberProgress(
      HttpServletRequest request, @PathVariable Long roomId) {
    return roomService.listMemberProgress(uid(request), roomId);
  }

  /**
   * — 방 대표 이미지 업로드(`docs/api/room-cover-image.md`). 방이 아직 없어도(생성 화면) 호출되므로 roomId 경로 없이 범용 업로드로 둔다.
   * 반환된 URL은 이 엔드포인트가 아니라 기존 {@link #create}/{@link #update}의 {@code coverImage} 문자열 필드로 저장한다.
   */
  @PostMapping(value = "/rooms/cover-image", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
  @ResponseStatus(HttpStatus.CREATED)
  public CoverImageResponse uploadCoverImage(@RequestPart("image") MultipartFile image) {
    return roomCoverImageService.upload(image);
  }

  @GetMapping("/invite-codes/{code}")
  public InviteCodePreviewResponse preview(@PathVariable String code) {
    return roomService.previewInvite(code);
  }

  @PostMapping("/invite-codes/{code}/join")
  public RoomResponse join(HttpServletRequest request, @PathVariable String code) {
    return roomService.joinRoom(uid(request), displayName(request), code);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }

  private String displayName(HttpServletRequest request) {
    String name = (String) request.getAttribute(FirebaseAuthFilter.ATTR_NAME);
    if (name != null) {
      return name;
    }
    String email = (String) request.getAttribute(FirebaseAuthFilter.ATTR_EMAIL);
    if (email != null) {
      return email;
    }
    return uid(request);
  }
}
