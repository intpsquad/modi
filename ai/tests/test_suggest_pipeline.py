"""추천 파이프라인 — **크레딧 0 · 네트워크 0.**

2026-10-18(#109)에 LangGraph 그래프·검수·임베딩 중복 거르기를 걷어내고 **LLM 1회 호출의 직선
함수**로 되돌렸다. 여기서 보는 것:

- 추천 1회 = LLM 호출 **정확히 1회**(후보가 여럿이어도 — 예전에는 임베딩이 한 번 더 붙었다)
- 자료 고르기(최신순·예산)가 프롬프트와 검증에 실제로 반영되는지
- 그래프 시절의 계약(502·토큰 로그·후보 모양·HTTP 200)이 그대로인지

순수 함수(`build_payload`·`filter_candidates`)는 `test_suggest.py`, 순위 계산은
`test_archive_ranking.py` 가 본다.
"""

import inspect

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from modi_ai.config import get_settings
from modi_ai.main import app
from modi_ai.schemas import (
    ArchiveItemInput,
    RoomInput,
    SuggestionRequest,
    SuggestionResponse,
    TodoCandidate,
)
from modi_ai.suggest import get_llm, suggest


def _request(**overrides) -> SuggestionRequest:
    base = {
        "room": RoomInput(name="방", goal="목표", start_date="2026-08-01", end_date="2026-08-31"),
        "existing_todos": [],
        "excluded_todos": [],
        "archive": [ArchiveItemInput(id=1, title="자료", content="내용")],
    }
    return SuggestionRequest(**(base | overrides))


class _Llm:
    """구조화 출력 한 가지만 흉내내고, 받은 메시지를 `calls` 에 쌓는다."""

    def __init__(self, *candidates: TodoCandidate, parsed: bool = True) -> None:
        self.candidates = list(candidates)
        self.parsed = parsed
        self.calls: list[list] = []

    def with_structured_output(self, _schema, include_raw=False):
        llm = self

        class _Structured:
            def invoke(self, messages):
                llm.calls.append(messages)
                return {
                    "raw": None,
                    "parsed": SuggestionResponse(candidates=llm.candidates) if llm.parsed else None,
                    "parsing_error": None if llm.parsed else "깨진 JSON",
                }

        return _Structured()

    def first_archive_id(self) -> str:
        """프롬프트 "아카이브 자료" 절의 **첫 자료 id**."""
        payload = self.calls[0][1].content
        return payload.split("# 아카이브 자료")[1].split("## id=")[1]


class TestOneCall:
    def test_one_recommendation_is_exactly_one_llm_call(self):
        """🔴 #109 의 요점. 후보가 둘 이상이면 예전에는 임베딩 왕복이 하나 더 붙었다."""
        llm = _Llm(
            TodoCandidate(title="후보 하나", source_item_id=1),
            TodoCandidate(title="후보 둘", source_item_id=1),
        )

        suggest(_request(), llm)

        assert len(llm.calls) == 1

    def test_the_messages_are_the_system_prompt_and_the_payload(self):
        """프롬프트는 그래프 시절과 **한 글자도 같다**.

        시스템은 `SYSTEM_PROMPT`, 사람은 고른 자료로 만든 `build_payload` 다. 다르면 평가셋
        기준선(#26)과의 비교가 깨진다(`ai/CLAUDE.md` 프롬프트 규칙).
        """
        from modi_ai.prompts import SYSTEM_PROMPT
        from modi_ai.suggest import _select_archive, build_payload

        request = _request()
        llm = _Llm()

        suggest(request, llm)

        system, human = llm.calls[0]
        assert system.content == SYSTEM_PROMPT
        assert human.content == build_payload(_select_archive(request))

    def test_suggest_takes_no_embedder(self):
        """임베더를 받는 자리가 되살아나면 외부 호출이 다시 늘어난다는 신호다."""
        assert list(inspect.signature(suggest).parameters) == ["request", "llm"]

    def test_similar_candidates_both_come_back(self):
        """의미 중복 거르기를 걷어낸 대가 — **비슷한 후보 둘이 그대로 나간다.**

        글자가 같은 것은 여전히 `filter_candidates` 가 걸러낸다(`test_suggest.py`).
        """
        llm = _Llm(
            TodoCandidate(title="유튜브 모의고사로 답변 구조 연습하기", source_item_id=1),
            TodoCandidate(title="모바일 유튜브 모의고사로 주제별 답변 연습하기", source_item_id=1),
        )

        response = suggest(_request(), llm)

        assert len(response.candidates) == 2


class TestArchiveSelection:
    """자료 고르기가 프롬프트와 검증에 실제로 반영되는지.

    순위 계산 자체는 `test_archive_ranking.py` 가 본다.
    """

    def _archive(self, count: int, liked: int) -> list[ArchiveItemInput]:
        return [
            ArchiveItemInput(
                id=i,
                title=f"자료{i}",
                content="내용",
                like_count=1 if i == liked else 0,
                created_at=f"2026-07-{i + 1:02d}T00:00:00Z",
            )
            for i in range(count)
        ]

    def test_the_newest_item_is_first_in_the_prompt(self):
        """**기본값**은 최신순이다(2026-08-09).

        시연에서 직전에 추가한 자료가 반드시 들어가야 해서 최신순으로 확정했다.
        """
        llm = _Llm()

        # id=4 가 가장 최신. 좋아요는 가장 오래된 id=0 에 준다 — 순위 모드였다면 id=0 이 1등이다.
        suggest(_request(archive=self._archive(5, liked=0)), llm)

        assert llm.first_archive_id().startswith("4 ")

    def test_the_liked_item_is_first_when_ranking_is_on(self, monkeypatch):
        """순위 모드는 **목표 임베딩 없이도** 돈다 — 유사도 축만 빠지고 좋아요가 순서를 정한다.

        좋아요를 **가운데** 자료에 준다 — 입력 순서(0)·최신순(4)·순위(2)가 서로 갈려야 이 테스트가
        "순위가 실제로 매겨졌다"를 잰다(맨 앞 자료에 주면 아무것도 안 해도 통과했다, #109 리뷰).
        """
        from modi_ai import config
        from modi_ai import suggest as module

        monkeypatch.setattr(
            module, "get_settings", lambda: config.Settings(archive_select_by_recency=False)
        )
        llm = _Llm()

        suggest(_request(archive=self._archive(5, liked=2)), llm)

        assert llm.first_archive_id().startswith("2 ")

    def test_items_over_budget_are_dropped_from_validation_too(self, monkeypatch):
        """잘려나간 자료의 id 를 근거로 댄 후보는 버린다 — 모델이 실제로 본 자료만 유효하다."""
        from modi_ai import config
        from modi_ai import suggest as module

        monkeypatch.setattr(
            module, "get_settings", lambda: config.Settings(archive_prompt_budget_chars=1)
        )
        # 예산 1자면 1등(가장 최신 id=4) 하나만 남는다.
        grounded_in_a_dropped_item = TodoCandidate(title="후보", source_item_id=0)

        response = suggest(
            _request(archive=self._archive(5, liked=-1)), _Llm(grounded_in_a_dropped_item)
        )

        assert response.candidates == []

    def test_a_one_item_room_still_goes_through_the_budget(self):
        """자료가 1건뿐인 방도 **예산을 탄다**(2026-08-02 리뷰 — 건너뛰면 예산의 1.7배가 됐다)."""
        llm = _Llm()
        budget = get_settings().archive_prompt_budget_chars
        huge = ArchiveItemInput(id=1, title="요약이 없는 자료", content="가" * 20_000)

        suggest(_request(archive=[huge]), llm)

        section = llm.calls[0][1].content.split("# 아카이브 자료", 1)[1]
        # `+1` 은 `build_payload` 의 줄바꿈 구분자 — 자료 1건당 1자의 기존 오차다.
        assert len(section) <= budget + 1, f"자료 1건짜리 방이 예산을 우회했다: {len(section):,}자"


class TestContract:
    """그래프 시절의 `suggest()` 가 하던 약속 — 직선으로 바꿨다고 달라지면 안 된다."""

    def test_an_empty_answer_is_a_normal_empty_list(self):
        assert suggest(_request(), _Llm()).candidates == []

    def test_candidates_grounded_in_unknown_items_are_dropped(self):
        bogus = TodoCandidate(title="후보", source_item_id=999)

        assert suggest(_request(), _Llm(bogus)).candidates == []

    def test_a_parsing_failure_is_a_502(self):
        with pytest.raises(HTTPException) as exc:
            suggest(_request(), _Llm(parsed=False))

        assert exc.value.status_code == 502

    def test_the_token_and_duration_logs_come_out(self, caplog):
        """두 줄 다 운영 관측용이다 — 지우지 말 것(`suggest` docstring)."""
        with caplog.at_level("INFO"):
            suggest(_request(), _Llm())

        messages = [r.getMessage() for r in caplog.records]
        assert any("todo-suggestions: archive=1 items" in m for m in messages)
        assert any(m.startswith("투두 추천: ") and "자료 1/1건" in m for m in messages)

    def test_a_surviving_candidate_comes_back_whole(self):
        response = suggest(_request(), _Llm(TodoCandidate(title="후보 하나", source_item_id=1)))

        assert [(c.title, c.source_item_id) for c in response.candidates] == [("후보 하나", 1)]

    def test_the_http_endpoint_returns_200(self, client: TestClient, sample_request):
        app.dependency_overrides[get_llm] = lambda: _Llm(
            TodoCandidate(title="후보", source_item_id=12)
        )
        try:
            response = client.post("/v1/todo-suggestions", json=sample_request)
        finally:
            app.dependency_overrides.pop(get_llm, None)

        assert response.status_code == 200
        assert [c["title"] for c in response.json()["candidates"]] == ["후보"]
