-- 같은 URL 을 최근에 이미 크롤링했는지 찾기 위한 인덱스 (2026-08-06).
--
-- 왜 필요한가: 운영 EC2 IP 가 인스타그램에서 소프트 블록됐고, 참조 문서(test.md)의 처방 셋 중
-- 첫째가 "Cache aggressively (e.g. 24h)" 다. ArchiveCrawlProcessor 가 크롤링 전에
-- "이 URL 을 24시간 안에 이미 긁었나" 를 묻는데, V1 에는 (folder_id, room_id, created_by)
-- 인덱스만 있어서 그 조회가 풀스캔이 된다.
--
-- 조회 모양: where url = ? and crawl_status = 'DONE' and created_at > ? order by created_at desc
-- 그래서 (url, created_at desc) 로 잡는다 — crawl_status 는 선택도가 낮아(DONE 이 대부분)
-- 인덱스에 넣어도 이득이 적다.
--
-- url 은 nullable 이다(텍스트 공유). PostgreSQL 은 NULL 을 인덱스에 담지만 이 조회는 늘
-- url = ? 이라 NULL 행을 타지 않는다.
CREATE INDEX idx_archive_items_url_created_at
    ON archive_items (url, created_at DESC);
