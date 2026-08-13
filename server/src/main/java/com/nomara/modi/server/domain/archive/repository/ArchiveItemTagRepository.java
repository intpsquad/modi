package com.nomara.modi.server.domain.archive.repository;

import com.nomara.modi.server.domain.archive.entity.ArchiveItemTag;
import com.nomara.modi.server.domain.archive.entity.ArchiveItemTagId;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ArchiveItemTagRepository extends JpaRepository<ArchiveItemTag, ArchiveItemTagId> {

  List<ArchiveItemTag> findByItemIdIn(List<Long> itemIds);

  List<ArchiveItemTag> findByItemId(Long itemId);

  void deleteByItemId(Long itemId);
}
