package com.nomara.modi.server.domain.category.repository;

import com.nomara.modi.server.domain.category.entity.Category;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CategoryRepository extends JpaRepository<Category, Long> {

  List<Category> findByRoomIdOrderByPositionAscIdAsc(Long roomId);

  Optional<Category> findFirstByRoomIdOrderByPositionDesc(Long roomId);
}
