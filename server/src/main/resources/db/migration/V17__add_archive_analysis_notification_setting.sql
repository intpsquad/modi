-- 자료 분석 완료·실패 알림 on/off (2026-08-06).
--
-- ⚠️ 원래 V16 이었는데 dev 에 V16(투두 리마인더)이 먼저 들어와 V17 로 옮겼다.
--    Flyway 는 같은 버전이 둘이면 기동 자체를 거부한다.
--
-- 왜 필요한가: 자료 등록이 양쪽 경로(인앱 S-25-C · 공유 S-25-D) 모두 비동기가 되면서
-- "언제 분석이 끝났는지" 를 알 방법이 앱을 다시 여는 것뿐이 됐다. 등록 직후 신호(스낵바 ·
-- "분석 중 N건")는 넣었지만 완료 시점은 비어 있었다.
--
-- 이 프로젝트의 푸시는 타입마다 설정 스위치가 딸린 구조라(PushType 이 NotificationSetting 의
-- 필드를 하나씩 가리킨다), 알림을 추가하려면 컬럼이 함께 늘어야 한다.
--
-- 기본값 TRUE 인 이유: 이 알림이 없으면 사용자는 완료 시점을 알 방법이 없다. 받기 싫은
-- 사람이 끄는 쪽이 맞다. 기존 행도 전부 TRUE 로 채워진다(V13 의 다른 알림 컬럼과 같은 방침).
ALTER TABLE notification_settings
    ADD COLUMN archive_analysis_done_enabled BOOLEAN NOT NULL DEFAULT TRUE;
