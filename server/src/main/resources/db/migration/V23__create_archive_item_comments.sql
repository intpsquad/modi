-- 자료 상세 댓글(docs/backend/archive-comments-handoff.md, 2026-08-08 디자인 핸드오프).
-- author_user_id는 archive_items.created_by와 같은 근거로 SET NULL이다 — 댓글은
-- 방 전체가 보는 공유 콘텐츠라 작성자가 탈퇴해도 댓글 자체는 남기고 참조만 지운다
-- (archive_likes의 CASCADE와는 다르다 — 좋아요는 순수 개인 활동 기록이라서다).
CREATE TABLE archive_item_comments (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id        BIGINT NOT NULL REFERENCES archive_items (id) ON DELETE CASCADE,
    author_user_id VARCHAR(128) REFERENCES users (id) ON DELETE SET NULL,
    body           VARCHAR(500) NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_archive_item_comments_item_id_created_at ON archive_item_comments (item_id, created_at);
