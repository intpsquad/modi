-- 모아보기 폴더에 사진을 직접 올리는 새 자료 경로(2026-08-09 후속 확정) — 투두 첨부 이미지
-- 피드(V25, todos.image_url)는 그대로 두고, archive_items에 별도 image_url을 추가한다.
-- 링크(url)/텍스트(둘 다 null)와 같은 관례로 image_url != null이면 이미지 자료다 — 별도 type
-- 컬럼은 두지 않는다(ArchiveItem.java).
ALTER TABLE archive_items
    ADD COLUMN image_url VARCHAR(2048);
