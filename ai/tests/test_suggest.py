from modi_ai.main import app
from modi_ai.schemas import (
    ArchiveItemInput,
    RoomInput,
    SuggestionRequest,
    SuggestionResponse,
    TodoCandidate,
)
from modi_ai.suggest import build_payload, filter_candidates, get_llm, suggest


def _request(**overrides) -> SuggestionRequest:
    base = {
        "room": RoomInput(
            name="오픽 스터디",
            goal="오픽 IH 달성",
            start_date="2026-08-01",
            end_date="2026-08-20",
        ),
        "existing_todos": ["교재 사기"],
        "excluded_todos": [],
        "archive": [ArchiveItemInput(id=12, title="오픽 공부법", content="답변 틀을 만들자")],
    }
    return SuggestionRequest(**(base | overrides))


class TestCandidateCountRule:
    """규칙 5 의 **하한**을 못 박는다 (2026-08-09, 시연 요구 "한 번에 6~8개").

    프롬프트는 문자열이라 조용히 되돌아간다 — `test_critique.py` 는 `SYSTEM_PROMPT` 를 상수와
    비교할 뿐이라 상수 자체가 바뀌면 같이 따라간다. 요구사항 쪽을 직접 겨눈다.
    """

    def test_the_rule_asks_for_six_to_eight(self):
        from modi_ai.prompts import SYSTEM_PROMPT

        assert "6~8개를 낸다" in SYSTEM_PROMPT

    def test_the_lower_bound_yields_to_the_grounding_rule(self):
        """🔴 **하한 혼자 있으면 안 된다.**

        #32 에서 요약에 하한을 줬더니 모델이 제외 대상(계정명)까지 넣어 분량을 채웠다 —
        "하한은 규칙을 깬다". 여기서 깨질 규칙은 규칙 1(자료 근거)이고 그건 없는 가게를
        지어내는 것이다. 그래서 하한과 **같은 항목 안에** 우선순위를 적어뒀다. 누가 하한만
        남기고 이 문장을 지우면 여기서 걸린다.
        """
        from modi_ai.prompts import SYSTEM_PROMPT

        rule_five = [line for line in SYSTEM_PROMPT.splitlines() if "6~8개를 낸다" in line]
        assert len(rule_five) == 1, SYSTEM_PROMPT
        # 우선순위 문장은 같은 항목(다음 줄까지)에 붙어 있어야 한다.
        start = SYSTEM_PROMPT.index(rule_five[0])
        item = SYSTEM_PROMPT[start : start + 200]
        assert "규칙 1이 우선" in item, item


class TestBuildPayload:
    def test_includes_room_goal_todos_and_archive(self):
        payload = build_payload(_request())

        assert "오픽 IH 달성" in payload
        assert "2026-08-01 ~ 2026-08-20" in payload
        assert "교재 사기" in payload
        assert "id=12" in payload
        assert "답변 틀을 만들자" in payload


class TestToday:
    """모델은 **지금이 언제인지 모른다.**

    프롬프트에 들어가던 것은 `기간: 2026-08-01 ~ 2026-08-20` 뿐이라, 마감 3일 전과 30일 전에
    같은 후보가 나온다. 남은 기간을 알려주면 후보의 성격이 달라질 수 있다는 가설이고,
    **아직 안 쟀다** — 그래서 값이 없으면 프롬프트가 지금과 완전히 같아야 한다.

    ⚠️ `date.today()` 를 여기서 부르지 않는다. ① 평가 픽스처가 과거 캡처라 날마다 결과가
    달라지고 곧 음수가 된다 ② 배포 컨테이너에 `TZ` 가 없어 UTC 로 돈다(`specs/OPEN.md`).
    "오늘"은 요청에 실려 온다 — `schemas` 모듈 docstring 의 원칙 그대로다.
    """

    def test_the_prompt_is_byte_identical_without_today(self):
        """**하위호환의 핵심.** Spring 이 아직 안 보내도 프롬프트가 한 글자도 안 달라야 한다."""
        assert build_payload(_request(today=None)) == build_payload(_request())

    def test_today_and_the_days_left_are_shown(self):
        payload = build_payload(_request(today="2026-08-18"))

        assert "- 오늘: 2026-08-18 (종료까지 2일)" in payload

    def test_the_line_sits_right_after_the_period(self):
        """방 정보 블록 안에 있어야 한다 — 규칙 목록에 끼면 #6 이 경고하는 변경이 된다."""
        lines = build_payload(_request(today="2026-08-18")).splitlines()
        period = next(i for i, line in enumerate(lines) if line.startswith("- 기간:"))

        assert lines[period + 1].startswith("- 오늘:")

    def test_the_last_day_is_not_zero_days_left(self):
        """종료일 당일은 D-DAY 다. `(종료까지 0일)` 은 '남았다'는 뜻으로 읽히지 않는다."""
        payload = build_payload(_request(today="2026-08-20"))

        assert "- 오늘: 2026-08-20 (오늘이 종료일)" in payload
        assert "0일" not in payload

    def test_a_date_past_the_end_never_shows_a_negative(self):
        """종료된 방은 추천을 안 부르지만, 음수 일수를 프롬프트에 흘리지는 않는다."""
        payload = build_payload(_request(today="2026-08-25"))

        assert "- 오늘: 2026-08-25 (종료일 지남)" in payload
        assert "-5" not in payload

    def test_a_date_before_the_start_still_counts_to_the_end(self):
        """시작 전 방(예약)도 종료까지의 일수는 말이 된다."""
        payload = build_payload(_request(today="2026-07-30"))

        assert "- 오늘: 2026-07-30 (종료까지 21일)" in payload

    def test_the_request_no_longer_carries_room_categories(self):
        """🔴 방의 기존 카테고리를 **받지도 쓰지도 않는다**

        Spring 이 아직 보내도 Pydantic 기본값(추가 필드 무시)이라 안 깨진다 — 배포 순서를
        맞출 필요가 없다. 되살리는 방법은 `docs/RESTORE-category-assignment.md`.
        """
        request = _request()

        assert not hasattr(request, "categories")
        assert "카테고리" not in build_payload(request)

    def test_a_categories_field_from_spring_is_ignored(self):
        """옛 Spring 이 보내던 필드가 남아 있어도 요청이 거부되지 않아야 한다."""
        request = SuggestionRequest.model_validate(
            {
                "room": {
                    "name": "방",
                    "goal": "목표",
                    "start_date": "2026-08-01",
                    "end_date": "2026-08-31",
                },
                "categories": ["공부"],
                "existing_todos": [],
                "excluded_todos": [],
                "archive": [],
            }
        )

        assert not hasattr(request, "categories")

    def test_marks_empty_sections_instead_of_omitting_them(self):
        """빈 목록을 통째로 빼면 모델이 '기존 투두가 있는데 안 준 것'으로 오해할 수 있다."""
        payload = build_payload(_request(existing_todos=[], archive=[]))

        assert payload.count("(없음)") == 2

    def test_excluded_section_appears_only_when_present(self):
        assert "이미 제안했던 후보" not in build_payload(_request())
        assert "이미 제안했던 후보" in build_payload(_request(excluded_todos=["듣기 연습하기"]))


class TestFilterCandidates:
    def test_drops_candidate_matching_existing_todo_ignoring_spaces(self):
        candidates = [TodoCandidate(title="교재  사기", source_item_id=12)]

        assert filter_candidates(candidates, _request()) == []

    def test_drops_candidate_matching_excluded_todo(self):
        request = _request(excluded_todos=["듣기 연습하기"])
        candidates = [TodoCandidate(title="듣기 연습하기", source_item_id=12)]

        assert filter_candidates(candidates, request) == []

    def test_drops_candidate_pointing_at_unknown_archive_item(self):
        """근거 자료 id 를 지어내는 것은 환각 신호다 — 프롬프트가 아니라 코드로 막는다."""
        candidates = [
            TodoCandidate(title="살아남는 후보", source_item_id=12),
            TodoCandidate(title="없는 자료 참조", source_item_id=999),
            TodoCandidate(title="근거 없음", source_item_id=None),
        ]

        kept = filter_candidates(candidates, _request())

        assert [c.title for c in kept] == ["살아남는 후보"]

    def test_skips_id_check_when_room_has_no_archive(self):
        """자료가 0건인 방에서는 근거 id 를 요구할 수 없다 — 목표만 보고 제안한다."""
        candidates = [TodoCandidate(title="목표 세분화하기", source_item_id=None)]

        kept = filter_candidates(candidates, _request(archive=[]))

        assert [c.title for c in kept] == ["목표 세분화하기"]

    def test_drops_blank_and_overlong_titles(self):
        candidates = [
            TodoCandidate(title="   ", source_item_id=12),
            TodoCandidate(title="가" * 51, source_item_id=12),
            TodoCandidate(title="가" * 50, source_item_id=12),
        ]

        kept = filter_candidates(candidates, _request())

        assert [len(c.title) for c in kept] == [50]

    def test_dedupes_candidates_against_each_other(self):
        candidates = [
            TodoCandidate(title="답변 틀 만들기", source_item_id=12),
            TodoCandidate(title="답변  틀  만들기", source_item_id=12),
        ]

        assert len(filter_candidates(candidates, _request())) == 1

    def test_strips_surrounding_whitespace_from_kept_title(self):
        candidates = [TodoCandidate(title="  답변 틀 만들기  ", source_item_id=12)]

        assert filter_candidates(candidates, _request())[0].title == "답변 틀 만들기"


class TestEndpoint:
    def test_returns_filtered_candidates(self, client, sample_request, fake_llm):
        """🔴 **API 계약** — 응답에 `category` 가 **없다**

        AI 는 카테고리를 정하지 않고 후보는 기타(미분류)로 나간다. 받는 쪽은 안 고쳐도 된다 —
        Spring 의 `AiCandidate` 는 Java record 라 키가 없으면 `null` 이 들어가고, 앱의
        `_resolveCategoryId` 는 빈 이름을 `null`(= 기타)로 해석한다.
        """
        parsed = SuggestionResponse(
            candidates=[
                TodoCandidate(title="답변 틀 만들기", source_item_id=12),
                TodoCandidate(title="교재 사기", source_item_id=12),
            ]
        )
        app.dependency_overrides[get_llm] = lambda: fake_llm(parsed=parsed)

        res = client.post("/v1/todo-suggestions", json=sample_request)

        assert res.status_code == 200
        assert res.json() == {"candidates": [{"title": "답변 틀 만들기", "source_item_id": 12}]}

    def test_a_category_the_model_invents_never_reaches_the_response(
        self, client, sample_request, fake_llm
    ):
        """모델이 `category` 를 써 보내도 스키마에 없으므로 버려진다.

        ⚠️ 이게 없으면 "필드를 지웠다"가 **응답까지 지웠다**는 보장이 안 된다 — Pydantic 이
        모르는 필드를 조용히 무시하므로 실수로 되살아나도 눈에 안 띈다.
        """
        app.dependency_overrides[get_llm] = lambda: fake_llm(
            parsed=SuggestionResponse.model_validate(
                {
                    "candidates": [
                        {"title": "답변 틀 만들기", "category": "공부", "source_item_id": 12}
                    ]
                }
            )
        )

        res = client.post("/v1/todo-suggestions", json=sample_request)

        assert res.status_code == 200
        assert "category" not in res.json()["candidates"][0]

    def test_sends_system_and_human_messages_to_the_model(self, fake_llm, fake_embedder):
        """인젝션 방어의 전제 — 사용자 데이터는 절대 system 에 섞이지 않는다."""
        fake = fake_llm(parsed=SuggestionResponse())

        suggest(_request(), fake, fake_embedder())

        system, human = fake.calls[0]
        assert "지시문" in system.content
        assert "오픽 IH 달성" in human.content
        assert "오픽 IH 달성" not in system.content

    def test_returns_502_when_structured_output_cannot_be_parsed(
        self, client, sample_request, fake_llm
    ):
        app.dependency_overrides[get_llm] = lambda: fake_llm(
            parsed=None, parsing_error=ValueError("not json")
        )

        res = client.post("/v1/todo-suggestions", json=sample_request)

        assert res.status_code == 502
