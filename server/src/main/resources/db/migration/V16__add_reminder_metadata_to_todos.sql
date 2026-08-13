-- iPhone 미리 알림형 인라인 작성기가 저장하는 투두 메타데이터.
-- 기존 투두를 안전하게 유지하기 위해 새 값은 전부 nullable(플래그만 false 기본값)로 확장한다.
ALTER TABLE todos
    ADD COLUMN due_date DATE,
    ADD COLUMN location VARCHAR(200),
    ADD COLUMN flagged BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN image_url VARCHAR(1024);

-- 태그는 검색·필터 확장을 고려해 JSON이 아닌 정규화 테이블로 둔다.
CREATE TABLE todo_tags (
    todo_id BIGINT NOT NULL REFERENCES todos (id) ON DELETE CASCADE,
    tag VARCHAR(50) NOT NULL,
    PRIMARY KEY (todo_id, tag)
);
CREATE INDEX idx_todo_tags_tag ON todo_tags (tag);
