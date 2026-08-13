package com.nomara.modi.server.domain.room.repository;

import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.entity.RoomStatus;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface RoomMemberRepository extends JpaRepository<RoomMember, RoomMemberId> {

  @Query("select rm.room from RoomMember rm where rm.user.id = :uid")
  List<Room> findRoomsByUserId(@Param("uid") String uid);

  @Query(
      "select rm from RoomMember rm join fetch rm.user where rm.room.id = :roomId order by rm.joinedAt asc")
  List<RoomMember> findMembersByRoomId(@Param("roomId") Long roomId);

  @Query("select count(rm) from RoomMember rm where rm.room.id = :roomId")
  long countByRoomId(@Param("roomId") Long roomId);

  /**
   * 협업 캐릭터(specs/0016) 완주율 분모 — 이 사용자가 현재 멤버로 남아있는 방 전체 개수.
   *
   * <p>⚠️ 방을 나가면 이 행이 하드 삭제된다(`RoomService.leaveRoom`) — 종료 전에 나간 방은 이 집계에 안 잡힌다(완주율이 실제보다 낙관적으로 나올
   * 수 있음, `specs/OPEN.md` 기록).
   */
  long countByUserId(String userId);

  /** 협업 캐릭터(specs/0016) 완주율 분자 — 그중 방 상태가 {@code status}인 것(=완주로 볼 ENDED 방) 개수. */
  long countByUserIdAndRoomStatus(String userId, RoomStatus status);
}
