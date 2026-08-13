-- 알림 내역(specs/0017-알림-내역.md, S-41). 발송 트리거 7종(PushType)이 개별 채널 게이트를
-- 통과하는 순간 PushNotifier가 이 테이블에도 기록한다 — FCM 발송 성공 여부와 무관하게 기록한다
-- ("발송 대상이었다"는 사실 기록이지 "기기에 도착했다"는 기록이 아니다).
--
-- 개인 기록이라 user_id는 CASCADE(user_activity와 같은 근거). room_id는 방이 나중에 삭제돼도
-- 알림 기록 자체는 남겨야 하므로 SET NULL(activities.actor_user_id와 같은 근거로 다른 방향).
--
-- title/body는 발송 시점에 실제로 쓰인 문자열을 그대로 스냅샷 저장한다 — 나중에 문구가 바뀌어도
-- 과거 기록은 그때 실제로 보낸 문구를 유지한다.
--
-- 90일 보존 후 배치 삭제(NotificationRetentionScheduler) — user_activity와 동일 정책.
CREATE TABLE notifications (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    VARCHAR(128) NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    room_id    BIGINT REFERENCES rooms (id) ON DELETE SET NULL,
    type       VARCHAR(32) NOT NULL,
    title      VARCHAR(255) NOT NULL,
    body       VARCHAR(255) NOT NULL,
    read_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_notifications_user_id_created_at ON notifications (user_id, created_at DESC);
CREATE INDEX idx_notifications_user_id_unread ON notifications (user_id) WHERE read_at IS NULL;
