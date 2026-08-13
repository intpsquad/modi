-- 홈 활동 피드(docs/backend/home-activity-feed.md) 이벤트 테이블. 각 도메인 액션이 일어나는
-- 순간 한 행씩 append한다(적재형 9종). 파생형 4종(SCHEDULE_SOON 등)은 여기 저장하지 않고
-- 조회 시점에 계산해 합류한다 — ActivityService 참고.
--
-- actor_user_id/target_user_id는 SET NULL이다 — 활동 피드는 방 전체가 보는 공유 콘텐츠라
-- (archive_items.created_by와 같은 근거) 작성자가 탈퇴해도 행은 남고 참조만 NULL이 된다.
CREATE TABLE activities (
    id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_id        BIGINT NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    type           VARCHAR(30) NOT NULL,
    actor_user_id  VARCHAR(128) REFERENCES users (id) ON DELETE SET NULL,
    target_user_id VARCHAR(128) REFERENCES users (id) ON DELETE SET NULL,
    target_name    VARCHAR(255),
    count          INT,
    created_at     TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_activities_room_id_created_at ON activities (room_id, created_at DESC);
