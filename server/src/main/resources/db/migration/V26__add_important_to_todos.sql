-- 투두 "중요 표시" 복원(docs/backend/todo-form-handoff.md, 2026-08-09 백엔드 요청서 1순위).
-- V16의 flagged 컬럼과는 별개의 새 컬럼이다 — flagged는 2026-08-07 롤백된 옛 인라인 작성기
-- 전용 의미로 죽어 있어 재활용할 근거가 없다(image_url과 달리 이번엔 새로 만든다).
ALTER TABLE todos
    ADD COLUMN important BOOLEAN NOT NULL DEFAULT FALSE;
