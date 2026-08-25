-- 인앱 피드백(문의하기, #70). 기존 문의는 mailto: 딥링크라 서버에 아무 기록이 없었고,
-- 사용자가 앱 버전·기기 정보를 직접 적어야 해서 버그 제보의 품질이 낮았다.
--
-- user_id 는 SET NULL 이다(사용자 확정, 2026-08-25). V9__account_deletion_cascades.sql 이
-- "공유 콘텐츠는 SET NULL / 개인 활동 기록은 CASCADE" 로 갈라놨는데 피드백은 둘 중 어느 쪽도
-- 아니다 — 다른 사용자와 공유하지는 않지만 **팀이 처리해야 하는 제보**라, 제보자가 탈퇴했다고
-- 미해결 버그 기록이 통째로 사라지면 안 된다. 대신 개인정보인 reply_email 은 탈퇴 로직
-- (UserService.withdrawAppData)이 유저 행 삭제 전에 명시적으로 NULL 로 지운다 — FK SET NULL 은
-- user_id 만 비우고 다른 컬럼은 건드리지 않기 때문이다.
--
-- image_key 는 URL 이 아니라 오브젝트 키다. 스크린샷은 개인정보가 담길 수 있어 rooms/cover/*
-- 처럼 공개 읽기로 열지 않는다(MinioConfig 의 버킷 정책 미변경) — 공개 URL 이 존재하지 않으므로
-- 키만 남기고 필요할 때 스토리지에서 꺼낸다. 알림 메일에는 이미지를 첨부로 실어 보낸다.
--
-- 보존 기간은 **아직 정하지 않았다**(specs/OPEN.md). user_activity 90일 선례가 있지만 피드백은
-- 처리 이력이라 성격이 달라, 정해지기 전에 삭제 배치를 만들지 않는다.
CREATE TABLE feedback (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     VARCHAR(128) REFERENCES users (id) ON DELETE SET NULL,
    type        VARCHAR(20) NOT NULL,
    content     TEXT NOT NULL,
    reply_email VARCHAR(255),
    app_version VARCHAR(50),
    device_info VARCHAR(200),
    image_key   VARCHAR(255),
    created_at  TIMESTAMPTZ NOT NULL
);

-- 읽기 경로는 "최근 제보부터 훑기"뿐이다(운영자가 DB/콘솔에서 본다 — 조회 API 없음).
CREATE INDEX idx_feedback_created_at ON feedback (created_at DESC);

-- 아래는 일부러 넣지 않았다.
--   ① status/처리상태 컬럼 — 지금은 이메일 알림으로 처리하고 관리 화면이 없다. 쓰지 않을
--      컬럼을 미리 만들지 않는다(todo_suggestion_exposures 의 category 선례).
--   ② user_id 인덱스 — "이 사람의 문의 목록"을 보는 화면이 없다. 필요해지면 그때 추가한다.
