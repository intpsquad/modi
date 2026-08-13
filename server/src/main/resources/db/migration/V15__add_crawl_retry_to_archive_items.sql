-- 크롤링 자동 재시도 (2026-08-06).
--
-- 왜 필요한가: 운영 EC2 IP 가 인스타그램에서 소프트 블록되는데, 그 차단은 영구가 아니라
-- 10~20분이면 풀린다(운영 DB 실측: 12:45 실패 → 12:54 성공 / 15:18 실패 → 15:36 성공).
-- 지금은 그 순간 들어온 공유가 그대로 FAILED 로 확정돼 사용자에게 "분석 실패" 가 뜬다 —
-- 실패율 58%(인스타 19건 중 11건)의 실체가 그것이고, 그 11건은 "안 되는 링크" 가 아니라
-- "타이밍이 나빴던 링크" 다. 잠시 뒤 서버가 한 번 더 긁으면 사용자는 실패를 볼 일이 없다.
--
-- crawl_retries : 자동 재시도를 예약한 횟수. 총 시도 횟수는 1 + crawl_retries 다.
--                 성공하면 늘지 않고, 초기화하지도 않는다 — 나중에 "이 자료는 몇 번 만에
--                 됐나" 를 물을 수 있게 기록으로 남긴다.
-- next_crawl_at : 다음 시도 시각. NULL 이면 배치가 집어가지 않는다 —
--                 (1) 재시도 대상이 아닌 항목, (2) 배치가 방금 집어간 항목(재선점 방지),
--                 (3) 이미 끝난 항목이 전부 NULL 이다.
--
-- 기존 행은 crawl_retries = 0, next_crawl_at = NULL 로 들어간다. 즉 이 마이그레이션이
-- 과거의 FAILED 를 되살리거나 배치를 갑자기 바쁘게 만들지 않는다.
ALTER TABLE archive_items
    ADD COLUMN crawl_retries INT NOT NULL DEFAULT 0,
    ADD COLUMN next_crawl_at TIMESTAMPTZ;

-- 배치 조회 모양: where crawl_status = 'PENDING' and next_crawl_at <= now() order by next_crawl_at
--
-- 부분 인덱스인 이유: 재시도를 기다리는 행은 전체의 극히 일부다(대부분 DONE + NULL).
-- 조건절에 넣으면 인덱스가 그 소수만 담아 작게 유지되고, 갱신 부하도 그 행들에만 붙는다.
CREATE INDEX idx_archive_items_next_crawl_at
    ON archive_items (next_crawl_at)
    WHERE next_crawl_at IS NOT NULL;
