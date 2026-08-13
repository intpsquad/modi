-- AI 추천 후보의 "이미 노출함" 기록. 이것이 없어서 추천을 두 번 누르면 같은 후보가
-- 또 나왔다 — TodoSuggestionService 가 excluded_todos 를 빈 배열로 보내고 있었다.
--
-- ⚠️ 이름 주의: excluded_todos 는 "사용자가 거절한 후보"가 아니라 **이미 노출한 후보 전부**다.
-- full_spec.md:130 에 거절 버튼이 없고 "중복 후보 재노출 안 함"만 있기 때문이다. 채택하지 않고
-- 시트를 닫은 후보도 전부 여기 들어간다. 거절로 읽으면 rejected 플래그를 만들게 되는데, 그것을
-- 채울 사용자 입력이 앱에 없다(ai/docs/DECISIONS.md).
--
-- 기록 시점 = 후보를 **생성**해 앱에 반환할 때(2026-07-30 사용자 확정). 앱이 "실제로 보여줬다"를
-- 따로 알려주는 방식은 기각했다 — 엔드포인트와 앱 변경이 늘고, 그 보고가 실패하면 막으려던
-- 중복 노출이 그대로 재발한다. 대가로 사용자가 응답을 받기 전에 이탈하면 못 본 후보도 제외되는데,
-- 아래 50개 상한이 롤오버되면서 되살아나므로 영구 손실은 아니다.
CREATE TABLE todo_suggestion_exposures (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    room_id     BIGINT NOT NULL REFERENCES rooms (id) ON DELETE CASCADE,
    title       VARCHAR(255) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL
);

-- 읽기는 언제나 "이 방의 최근 50개"뿐이라 (room_id, created_at DESC) 하나로 충분하다.
CREATE INDEX idx_todo_suggestion_exposures_room_id
    ON todo_suggestion_exposures (room_id, created_at DESC);

-- 아래 셋은 **일부러 넣지 않았다.**
--   ① UNIQUE (room_id, title) — 동시 요청이 겹치면 INSERT 가 터져 사용자의 추천 자체가 실패한다.
--      중복 행 하나보다 나쁘다. 중복 제거는 TodoSuggestionExposureStore 가 코드로 한다.
--   ② category / source_item_id — AI 계약이 excluded_todos: list[str] 이라 제목만 읽는다.
--      읽지 않을 데이터를 저장하지 않는다.
--   ③ 50개 초과 행 삭제(프루닝) — 상한은 "LLM 에 보내는 양"에 대한 것이므로 조회를 50개로
--      제한하면 충족된다. 누르기당 최대 8행이고(ai/src/modi_ai/prompts.py 규칙 6: "후보는 최대
--      8개까지 낸다") 방 삭제 시 위 CASCADE 로 정리되므로 삭제 쿼리를 둘 값이 없다.
