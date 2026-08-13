-- knock_enabled 잔재 정리(specs/OPEN.md, docs/backend/notification-handoff.md §D).
-- 콕찌르기/재촉은 2026-07-29 POKE 하나로 통일됐고 KNOCK은 그때부터 기록되지 않았다 — 컬럼·제약을
-- 이제 제거한다. 앱(app/lib/features/settings/settings_screens.dart)도 같은 커밋에서 knockEnabled
-- 파싱을 끊었으므로 서버·앱 배포 순서에 무관하게 안전하다(Spring 기본 Jackson 설정은 초과 요청
-- 필드를 조용히 무시한다 — 실제 위험은 응답에서 이 필드를 읽던 구버전 앱 쪽이었다).
ALTER TABLE notification_settings
    DROP COLUMN knock_enabled;

ALTER TABLE pokes
    DROP CONSTRAINT pokes_type_check,
    ADD CONSTRAINT pokes_type_check CHECK (type = 'POKE');
