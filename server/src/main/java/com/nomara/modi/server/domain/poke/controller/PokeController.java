package com.nomara.modi.server.domain.poke.controller;

import com.nomara.modi.server.domain.poke.dto.PokeResponse;
import com.nomara.modi.server.domain.poke.service.PokeService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** specs/0011-멤버-투두-콕찌르기.md — 확인 없이 즉시 실행, 홈 아바타줄과 S-30-M 버튼이 같은 엔드포인트를 쓴다. */
@RestController
public class PokeController {

  private final PokeService pokeService;

  public PokeController(PokeService pokeService) {
    this.pokeService = pokeService;
  }

  @PostMapping("/rooms/{roomId}/members/{userId}/pokes")
  @ResponseStatus(HttpStatus.CREATED)
  public PokeResponse sendPoke(
      HttpServletRequest request, @PathVariable Long roomId, @PathVariable String userId) {
    return pokeService.sendPoke(uid(request), roomId, userId);
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }
}
