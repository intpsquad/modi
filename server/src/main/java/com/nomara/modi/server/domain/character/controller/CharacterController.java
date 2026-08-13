package com.nomara.modi.server.domain.character.controller;

import com.nomara.modi.server.domain.character.dto.CharacterResponse;
import com.nomara.modi.server.domain.character.entity.UserActivityKind;
import com.nomara.modi.server.domain.character.service.CharacterService;
import com.nomara.modi.server.domain.character.service.UserActivityRecorder;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** specs/0016-협업-캐릭터.md — 마이 탭 협업 캐릭터 조회 + 접속 로그. */
@RestController
public class CharacterController {

  private final CharacterService characterService;
  private final UserActivityRecorder userActivityRecorder;

  public CharacterController(
      CharacterService characterService, UserActivityRecorder userActivityRecorder) {
    this.characterService = characterService;
    this.userActivityRecorder = userActivityRecorder;
  }

  @GetMapping("/me/character")
  public CharacterResponse myCharacter(HttpServletRequest request) {
    return characterService.getCharacter(uid(request));
  }

  @GetMapping("/rooms/{roomId}/members/{userId}/character")
  public CharacterResponse memberCharacter(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable String userId) {
    return characterService.getCharacterForRoomMember(uid(request), roomId, userId);
  }

  /**
   * 앱 진입 로그(specs/0016 4.2 {@code APP_OPEN}) — 대응하는 기존 조회 엔드포인트가 없어 전용으로 뒀다. 이 커밋 시점엔 앱이 아직 호출하지
   * 않는다(폴더 미지정 등록 엔드포인트와 같은 선례 — 백엔드만 준비해 둔다).
   */
  @PostMapping("/me/activity/app-open")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void recordAppOpen(HttpServletRequest request) {
    userActivityRecorder.record(uid(request), UserActivityKind.APP_OPEN, null, null);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
