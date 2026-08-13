package com.nomara.modi.server.domain.archive.repository;

import com.nomara.modi.server.domain.archive.entity.ArchiveFolder;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

/** specs/0010-아카이브-탭.md — S-25 폴더 CRUD. */
public interface ArchiveFolderRepository extends JpaRepository<ArchiveFolder, Long> {

  List<ArchiveFolder> findByRoomIdOrderByCreatedAtAsc(Long roomId);

  /** 방마다 폴더 최소 1개 보장(백엔드 요청, 2026-08-07) — 0개면 기본 폴더를 만들어야 한다. */
  long countByRoomId(Long roomId);

  /** 폴더 미지정 자료 등록이 재사용할 기본 폴더를 찾는다(없으면 호출부가 새로 만든다). */
  Optional<ArchiveFolder> findFirstByRoomIdAndName(Long roomId, String name);
}
