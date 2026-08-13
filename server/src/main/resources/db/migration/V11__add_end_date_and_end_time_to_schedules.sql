-- 일정 종료 시간 + 다중일(기간) 지원(사용자 요청, 2026-08-04).
-- V8__add_place_to_schedules.sql의 "시간은 단일 값 유지 방침이라 end_time은 두지 않는다"를
-- 뒤집는다 — 과거 파일은 보존 원칙상 수정하지 않고 여기서 정책 변경만 남긴다.
-- 둘 다 nullable: NULL = "설정 안 함"(기존 단일일·단일시간 일정과 완전히 호환), 백필 불필요.
ALTER TABLE schedules ADD COLUMN end_date DATE;
ALTER TABLE schedules ADD COLUMN end_time TIME;
