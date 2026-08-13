-- 일정 장소(MR !52). 프론트는 이미 place 를 nullable 로 파싱해 두고
-- 등록/수정 시트에서 보내지만, 지금은 저장할 컬럼이 없어 서버가 조용히 버린다.
--
-- nullable 이다: 장소는 선택 입력이라 없는 일정이 정상이다(예: 온라인/비대면 일정).
-- 시간은 단일 값 유지 방침이라 end_time 은 만들지 않는다.
ALTER TABLE schedules ADD COLUMN place VARCHAR(100);
