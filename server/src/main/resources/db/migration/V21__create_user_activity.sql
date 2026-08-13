-- 협업 캐릭터(specs/0016-협업-캐릭터.md) 판정용 접속·조회 로그. app_open/room_view/
-- archive_item_view/todo_view 이벤트를 append-only로 쌓는다 — 소셜 피드가 아니라
-- 개인 행동 로그라 activities 테이블과는 성격이 다르다.
--
-- 개인 행동 로그라 user_id는 CASCADE다(activities의 actor_user_id SET NULL과 다름) —
-- 탈퇴하면 그 사람의 열람 이력도 함께 사라지는 게 맞다(pokes/archive_likes와 같은 근거).
--
-- 90일 보존 후 배치 삭제(UserActivityRetentionScheduler) — 원본 이벤트는 최근 행동
-- 분석용이라 오래 남길 이유가 없다.
CREATE TABLE user_activity (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    VARCHAR(128) NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    room_id    BIGINT REFERENCES rooms (id) ON DELETE CASCADE,
    kind       VARCHAR(30) NOT NULL,
    target_id  BIGINT,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_user_activity_user_id_created_at ON user_activity (user_id, created_at DESC);
