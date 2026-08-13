package com.nomara.modi.server.domain.poke.dto;

import com.nomara.modi.server.domain.poke.entity.Poke;
import java.time.Instant;

public record PokeResponse(Long id, Instant createdAt) {

  public static PokeResponse of(Poke poke) {
    return new PokeResponse(poke.getId(), poke.getCreatedAt());
  }
}
