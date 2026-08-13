-- 홈 활동 피드(docs/backend/home-activity-feed.md)의 TODO_ADDED/SCHEDULE_ADDED 이벤트에
-- actor(작성자)가 필요해서 추가한다. archive_items.created_by와 같은 패턴 —
-- 투두/일정은 방 전체가 보는 공유 콘텐츠이므로 작성자가 탈퇴해도 행은 남고 작성자만 NULL이 된다
-- (CASCADE가 아니라 SET NULL, V9 주석 참고). 기존 행은 NULL(과거분은 작성자 미표시, 백필 안 함).
ALTER TABLE todos ADD COLUMN created_by VARCHAR(128) REFERENCES users (id) ON DELETE SET NULL;
ALTER TABLE schedules ADD COLUMN created_by VARCHAR(128) REFERENCES users (id) ON DELETE SET NULL;
