-- 카테고리 수동 순서변경. 기존 정렬 기준(created_at ASC, id로 동률 처리)을
-- 그대로 보존해 백필하므로 마이그레이션 전후 사용자에게 보이는 순서는 바뀌지 않는다.
-- UNIQUE(room_id, position)은 일부러 넣지 않는다 — 순서변경은 N개 행을 개별 UPDATE로 반영하고
-- Hibernate가 이를 하나씩 flush하므로, 트랜잭션 도중 두 카테고리가 같은 position을 잠깐 갖는 것이
-- 정상이다(DEFERRABLE 제약 없이 UNIQUE를 걸면 정상적인 순서변경마다 위반이 난다).
ALTER TABLE categories ADD COLUMN position INT NOT NULL DEFAULT 0;

UPDATE categories c
SET position = ranked.rn
FROM (
    SELECT id, (ROW_NUMBER() OVER (PARTITION BY room_id ORDER BY created_at ASC, id ASC) - 1)::int AS rn
    FROM categories
) ranked
WHERE c.id = ranked.id;
