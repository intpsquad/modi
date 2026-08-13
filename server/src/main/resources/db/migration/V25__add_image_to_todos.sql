-- 투두 사진 첨부 → 모아보기 "이미지" 탭(docs/backend/todo-image-archive-handoff.md, 2026-08-09 기획 확정).
-- todos.image_url(VARCHAR(1024))은 V16에서 이미 만들어졌으나 2026-08-07 인라인 작성기 롤백으로
-- 매핑을 걷어냈던 죽은 컬럼이다 — 여기서 다시 살려 쓴다(신규 컬럼 아님). 핀·첨부시각만 새로 추가한다.
--
-- image_attached_at은 "이미지 탭" 피드 정렬(핀 우선 → 최신순) 기준이다. created_at을 재사용하지
-- 않는 이유: 투두 자체의 생성 시각과 사진을 (나중에) 첨부한 시각은 다르고, 재첨부 시 재정렬돼야 한다.
ALTER TABLE todos
    ADD COLUMN image_pinned      BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN image_attached_at TIMESTAMPTZ;

-- 2026-08-06~07 iPhone 미리 알림식 인라인 작성기가 실제로 채워 넣은 옛 image_url 값을 정리한다
-- (specs/OPEN.md "인라인 작성기 롤백으로 남은 미사용 DB 컬럼" 항목 — 값이 존재한다는 사실 자체가
-- 이미 기록돼 있다). 새 코드(Todo.attachImage/detachImage)는 image_url과 image_attached_at을
-- 항상 함께 채우고 함께 비우는 불변식을 가정하는데, 이 옛 값들은 그때 image_attached_at 컬럼
-- 자체가 없어 그 불변식 밖에 있다 — 그대로 두면 새 "이미지" 탭 피드 쿼리(핀 우선 →
-- image_attached_at desc)에서 NULL이 맨 앞으로 정렬돼 나오고, 앱은 그 자리의 createdAt을
-- non-null로 파싱해 피드 전체가 죽는다. 몇 주째 어느 화면에도 노출된 적 없는 죽은 참조라 URL만
-- 지워도 잃는 데이터가 없다.
UPDATE todos SET image_url = NULL WHERE image_url IS NOT NULL;

CREATE INDEX idx_todos_room_id_image_attached_at
    ON todos (room_id, image_attached_at DESC) WHERE image_url IS NOT NULL;
