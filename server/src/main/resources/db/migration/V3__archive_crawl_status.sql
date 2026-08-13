-- S-25-D 외부 공유 등록: URL 공유는 크롤링이 끝날 때까지 PENDING 상태로 남고, 그동안 body_text가 없다.
ALTER TABLE archive_items ALTER COLUMN body_text DROP NOT NULL;
ALTER TABLE archive_items ADD COLUMN crawl_status VARCHAR(10) NOT NULL DEFAULT 'DONE';
ALTER TABLE archive_items ADD CONSTRAINT chk_archive_items_crawl_status
  CHECK (crawl_status IN ('PENDING', 'DONE', 'FAILED'));
