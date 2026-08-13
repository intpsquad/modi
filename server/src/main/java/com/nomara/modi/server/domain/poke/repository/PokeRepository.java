package com.nomara.modi.server.domain.poke.repository;

import com.nomara.modi.server.domain.poke.entity.Poke;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PokeRepository extends JpaRepository<Poke, Long> {

  /** 홈 활동 피드 POKE_ACCUMULATED 임계값 판정용(방 범위 누적 수신 콕 수). */
  long countByRoomIdAndToUserId(Long roomId, String toUserId);
}
