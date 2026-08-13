-- 투두 수동 드래그 순서변경(사용자 요청, 2026-08-04). position은 (room_id, category_id) 단위로
-- 스코프된다 — "기타"(category_id NULL)도 하나의 파티션으로 취급되므로 PARTITION BY가 그대로 처리한다.
-- UNIQUE(room_id, category_id, position)은 categories.position(V10)과 같은 이유로 일부러 넣지 않는다 —
-- 순서변경은 N개 행을 개별 UPDATE로 반영하므로 트랜잭션 도중 같은 position이 잠깐 겹치는 게 정상이다.
ALTER TABLE todos ADD COLUMN position INT NOT NULL DEFAULT 0;

UPDATE todos t
SET position = ranked.rn
FROM (
    SELECT id, (ROW_NUMBER() OVER (PARTITION BY room_id, category_id ORDER BY created_at ASC, id ASC) - 1)::int AS rn
    FROM todos
) ranked
WHERE t.id = ranked.id;
