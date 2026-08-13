package com.nomara.modi.server.domain.room.repository;

import com.nomara.modi.server.domain.room.entity.Room;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RoomRepository extends JpaRepository<Room, Long> {}
