"""추천 파이프라인 그래프 — **크레딧 0 · 네트워크 0.**

전환의 합격 기준은 하나였다: **`suggest()` 의 계약이 한 글자도 안 바뀐다.**
그건 기존 테스트(`test_suggest.py`·`test_semantic_dedupe.py`·`test_category_mapping.py`)가
**하나도 안 바뀌고** 통과하는 것으로 증명됐다. 여기서는 그래프가 새로 들여온 것만 본다.

- 노드·엣지 모양(전환 중 노드를 빠뜨려도 결과가 그럴듯하면 안 걸린다)
- `_has_candidates` 분기 — 후보가 없으면 임베딩을 **안 부른다**
"""

import re

import pytest
from fastapi import HTTPException

from modi_ai.config import get_settings
from modi_ai.schemas import (
    ArchiveItemInput,
    CritiqueResponse,
    CritiqueVerdict,
    RoomInput,
    SuggestionRequest,
    SuggestionResponse,
    TodoCandidate,
)
from modi_ai.suggest import CRITIQUE_INDEX_BASE, SUGGEST_GRAPH, suggest

# 검수 프롬프트가 후보를 넘기는 모양(`1. 제목`).
_NUMBERED = re.compile(r"^\d+\. ")


def _request(**overrides) -> SuggestionRequest:
    base = {
        "room": RoomInput(name="방", goal="목표", start_date="2026-08-01", end_date="2026-08-31"),
        "categories": ["공부"],
        "existing_todos": [],
        "excluded_todos": [],
        "archive": [ArchiveItemInput(id=1, title="자료", content="내용")],
    }
    return SuggestionRequest(**(base | overrides))


def _llm(*candidates: TodoCandidate, parsed: bool = True):
    """**검수 스키마도 받는다** 판정은 항상 전부 통과다.

    통과로 두는 이유는 검수 노드가 끼어들기 전에 쓰인 이 파일의 테스트들이 **원래 재던 것을
    그대로 재게** 하기 위해서다. 폴백(전부 통과)으로 넘어가면 통과는 하지만 ERROR 로그가
    하나 더 늘어 `test_the_outage_is_logged_as_an_error_twice` 같은 단언이 깨진다 —
    실제로 깨졌고, 그게 이 가짜가 스키마를 봐야 하는 이유다.
    """

    class _Structured:
        def __init__(self, schema):
            self._schema = schema

        def invoke(self, messages):
            if self._schema is CritiqueResponse:
                count = sum(
                    1 for line in str(messages[-1].content).splitlines() if _NUMBERED.match(line)
                )
                return CritiqueResponse(
                    verdicts=[
                        CritiqueVerdict(index=i, ok=True)
                        for i in range(CRITIQUE_INDEX_BASE, CRITIQUE_INDEX_BASE + count)
                    ]
                )
            return {
                "raw": None,
                "parsed": SuggestionResponse(candidates=list(candidates)) if parsed else None,
                "parsing_error": None if parsed else "깨진 JSON",
            }

    class _Llm:
        def with_structured_output(self, schema, include_raw=False):
            return _Structured(schema)

    return _Llm()


def _exploding_embed(_texts):
    """⚠️ `select` 노드에는 이걸 쓰면 안 된다 — `_goal_vector` 의 `except Exception` 이
    `AssertionError` 까지 삼켜서, 테스트가 조용히 **폴백 경로**를 타고 통과한다.
    자료가 2건 이상인 케이스에는 `_working_embed` 를 쓸 것."""
    raise AssertionError("임베딩을 부르면 안 되는 경로에서 불렀다")


def _working_embed(texts):
    return [[1.0, 0.0] for _ in texts]


class TestGraphShape:
    """노드를 빠뜨려도 결과가 그럴듯하면 안 걸린다 — 모양을 직접 못 박는다."""

    def test_every_node_exists(self):
        nodes = set(SUGGEST_GRAPH.get_graph().nodes)

        assert {"select", "generate", "critique", "batch", "dedupe"} <= nodes

    def test_the_category_node_is_gone(self):
        """🔴 `match`(카테고리 매칭)를 걷어냈다.

        AI 가 카테고리를 정하지 않는다. 되살리는 방법은 `docs/RESTORE-category-assignment.md`.
        """
        assert "match" not in set(SUGGEST_GRAPH.get_graph().nodes)

    def test_the_pipeline_runs_in_this_order(self):
        edges = {(e.source, e.target) for e in SUGGEST_GRAPH.get_graph().edges}

        # `select` 는 **`generate` 앞**이다 — 프롬프트에 실을 자료를 정하는 노드라
        # LLM 호출보다 뒤에 있으면 아무 의미가 없다.
        assert ("__start__", "select") in edges
        assert ("select", "generate") in edges
        assert ("batch", "dedupe") in edges
        assert ("dedupe", "__end__") in edges

    def test_generate_can_short_circuit_to_the_end(self):
        """후보가 없으면 남은 노드를 건너뛴다."""
        edges = {(e.source, e.target) for e in SUGGEST_GRAPH.get_graph().edges}

        assert ("generate", "__end__") in edges


class TestArchiveSelection:
    """`select` 노드가 프롬프트와 검증에 실제로 반영되는지.

    순위 계산 자체는 `test_archive_ranking.py` 가 본다. 여기서는 **그래프에 꽂힌 결과**만 본다.
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

    def _capture_first_id(self, archive) -> str:
        """프롬프트 "아카이브 자료" 절의 **첫 자료 id**. LLM 은 안 부른다."""
        seen = {}

        class _Structured:
            def invoke(self, messages):
                seen["payload"] = messages[1].content
                return {
                    "raw": None,
                    "parsed": SuggestionResponse(candidates=[]),
                    "parsing_error": None,
                }

        class _Llm:
            def with_structured_output(self, _schema, include_raw=False):
                return _Structured()

        suggest(_request(archive=archive), _Llm(), _working_embed)
        return seen["payload"].split("# 아카이브 자료")[1].split("## id=")[1]

    def test_the_newest_item_is_first_in_the_prompt(self):
        """**기본값**은 최신순이다(2026-08-09, `archive_select_by_recency`).

        예산이 3,000 자로 내려와 상시 발동하게 되면서 "무엇이 먼저 오는가"가 결과를 바꾼다 —
        시연에서 직전에 추가한 자료가 반드시 들어가야 해서 최신순으로 확정했다.
        """
        # id=4 가 가장 최신(2026-07-05). 좋아요는 가장 오래된 id=0 에 준다 —
        # 순위 모드였다면 id=0 이 1등이다(아래 테스트).
        first = self._capture_first_id(self._archive(5, liked=0))

        assert first.startswith("4 ")

    def test_the_liked_item_is_first_when_ranking_is_on(self, monkeypatch):
        """순위 모드에서는 좋아요가 순서에 반영돼야 한다 — 가중치 3.0 의 존재 이유다.

        기본값이 최신순으로 바뀌었어도 순위 코드는 살아 있다(`config` 주석 참고). 플래그를
        되돌렸을 때 예전 동작이 그대로인지를 여기서 지킨다.
        """
        from modi_ai import config
        from modi_ai import suggest as module

        monkeypatch.setattr(
            module, "get_settings", lambda: config.Settings(archive_select_by_recency=False)
        )

        first = self._capture_first_id(self._archive(5, liked=0))

        assert first.startswith("0 ")

    def test_recency_mode_does_not_embed_the_goal(self):
        """최신순에서는 **LLM 앞 임베딩 왕복이 사라진다** — 지연 이득의 정체다.

        유사도 축을 안 쓰므로 목표 벡터가 필요 없다. 이 절감이 조용히 되돌아가면
        (`_select_archive` 가 다시 `_goal_vector` 를 부르면) 여기서 걸린다.
        """
        calls = []

        def _counting_embed(texts):
            calls.append(list(texts))
            return _working_embed(texts)

        archive = [
            ArchiveItemInput(id=i, title=f"자료{i}", content="내용", embedding=[1.0, 0.0])
            for i in (1, 2)
        ]

        request = _request(archive=archive)
        suggest(request, _llm(), _counting_embed)

        # 목표 임베딩은 방 목표 문자열 **하나만** 담아 나간다(`_goal_vector`).
        assert not any(texts == [request.room.goal] for texts in calls), calls

    def test_items_over_budget_are_dropped_from_validation_too(self, monkeypatch):
        """잘려나간 자료의 id 를 근거로 댄 후보는 버려져야 한다.

        `filter_candidates` 가 **모델이 실제로 본 자료**만 유효 id 로 봐야 한다는 뜻이다 —
        `select` 가 `request` 를 갈아끼우는 이유가 이것이다.
        """
        from modi_ai import config
        from modi_ai import suggest as module

        monkeypatch.setattr(
            module, "get_settings", lambda: config.Settings(archive_prompt_budget_chars=1)
        )

        # 예산 1자면 아무것도 안 들어가므로 1등 하나만 남는다.
        # id=4(가장 최신)가 살고 나머지는 잘린다.
        grounded_in_a_dropped_item = TodoCandidate(title="후보", source_item_id=0)

        response = suggest(
            _request(archive=self._archive(5, liked=-1)),
            _llm(grounded_in_a_dropped_item),
            _working_embed,
        )

        assert response.candidates == []

    def test_a_one_item_room_still_goes_through_the_budget(self):
        """자료가 1건뿐인 방도 **예산을 탄다.**

        ⚠️ 원래 `_select_archive` 가 `len(archive) < 2` 면 노드를 통째로 빠져나갔고, 그
        docstring 은 "결과가 완전히 같아서 왕복만 아낀다"고 적고 있었다 — **거짓이었다.**
        예산이 아예 안 돌아서, 요약 없는 거대한 자료 한 건짜리 방의 프롬프트가 예산의
        1.7배가 됐다(2026-08-02 리뷰).

        `select_archive` 를 직접 부르는 테스트로는 이 회귀를 못 잡는다 — 그쪽은 예산을 인자로
        받으니 항상 돈다. **그래프를 통과시켜야** 단축이 되살아났을 때 걸린다.
        """
        seen = {}

        class _Structured:
            def invoke(self, messages):
                seen["payload"] = messages[1].content
                return {
                    "raw": None,
                    "parsed": SuggestionResponse(candidates=[]),
                    "parsing_error": None,
                }

        class _Llm:
            def with_structured_output(self, _schema, include_raw=False):
                return _Structured()

        budget = get_settings().archive_prompt_budget_chars
        huge = ArchiveItemInput(id=1, title="요약이 없는 자료", content="가" * 20_000)

        suggest(_request(archive=[huge]), _Llm(), _working_embed)

        section = seen["payload"].split("# 아카이브 자료", 1)[1]

        # `+1` 은 `build_payload` 의 `"\n".join(lines)` 구분자다 — 자료 1건당 1자가 예산 계산에
        # 안 잡히는 **기존** 오차이고 이 티켓의 범위가 아니다(리뷰에서 확인). 우회가 되살아나면
        # 여기가 20,268자가 되므로 1자 여유로도 충분히 걸린다.
        assert len(section) <= budget + 1, f"자료 1건짜리 방이 예산을 우회했다: {len(section):,}자"

    def test_the_recommendation_survives_a_goal_embedding_outage(self):
        """목표 임베딩이 죽어도 200 이어야 한다 — 유사도 축만 빠지고 나머지 셋으로 순위를 낸다."""

        def _boom(_texts):
            raise RuntimeError("임베딩 게이트웨이 장애")

        kept = TodoCandidate(title="후보 하나", source_item_id=0)

        response = suggest(_request(archive=self._archive(5, liked=0)), _llm(kept), _boom)

        assert [c.title for c in response.candidates] == ["후보 하나"]


class TestShortCircuit:
    def test_no_embedding_call_when_the_model_returns_nothing(self):
        """빈 결과는 정상 경로다 — 제외 창이 차면 실제로 그렇게 된다."""
        response = suggest(_request(), _llm(), _exploding_embed)

        assert response.candidates == []

    def test_no_embedding_call_when_the_filter_drops_everything(self):
        """`source_item_id` 가 입력에 없는 id 면 코드가 버린다 — 그 뒤에도 부르면 안 된다."""
        bogus = TodoCandidate(title="후보", source_item_id=999)

        response = suggest(_request(), _llm(bogus), _exploding_embed)

        assert response.candidates == []


class TestContractIsUnchanged:
    """전환 전 `suggest()` 가 하던 약속. 그래프 안으로 들어갔다고 달라지면 안 된다."""

    def test_a_parsing_failure_is_still_a_502(self):
        with pytest.raises(HTTPException) as exc:
            suggest(_request(), _llm(parsed=False), _exploding_embed)

        assert exc.value.status_code == 502

    def test_the_token_log_still_comes_out(self, caplog):
        with caplog.at_level("INFO"):
            suggest(_request(), _llm(), _exploding_embed)

        assert any("todo-suggestions: archive=1 items" in r.getMessage() for r in caplog.records)

    def test_a_surviving_candidate_comes_back_whole(self):
        kept = TodoCandidate(title="후보 하나", source_item_id=1)

        response = suggest(_request(), _llm(kept), lambda ts: [[1.0, 0.0] for _ in ts])

        assert len(response.candidates) == 1
        assert response.candidates[0].title == "후보 하나"

    def test_the_graph_is_compiled_once(self):
        """요청마다 컴파일하면 지연이 붙는다 — 모듈 상수여야 한다."""
        from modi_ai import suggest as module

        assert module.SUGGEST_GRAPH is SUGGEST_GRAPH


class TestEmbeddingOutageDoesNotKillTheRecommendation:
    """⚠️ **이 클래스는 실제 회귀를 막는다.** 없어서 한 번 뚫렸다.

    임베딩 게이트웨이가 죽어도 추천은 **200 + 후보 유지**여야 한다. 후보는 이미 LLM 크레딧을
    쓴 결과이고, 나중에 붙인 개선(자료 순위·중복 제거) 때문에 화면 본체를 잃으면 안 된다.
    2026-07-30 리뷰에서 P1 으로 잡아 고친 동작인데(`embeddings.py` 주석에 기록돼 있다),
    에서 `_prewarm` 이 `try/except` **밖**에서 네트워크를 부르는 바람에
    **조용히 500 으로 되돌아갔다** — 그때 테스트 196개가 전부 초록이었다.

    Spring 은 5xx 를 `BadGatewayException("AI 추천 서버에 연결하지 못했어요")` 로 올린다
    (`HttpTodoSuggestionClient`). 즉 사용자는 후보 대신 에러 화면을 본다.
    """

    def _boom(self, _texts):
        raise RuntimeError("임베딩 게이트웨이 장애")

    def test_candidates_survive_a_total_embedding_outage(self):
        kept = [
            TodoCandidate(title="후보 하나", source_item_id=1),
            TodoCandidate(title="후보 둘", source_item_id=1),
        ]

        response = suggest(_request(excluded_todos=["이미 본 것"]), _llm(*kept), self._boom)

        assert [c.title for c in response.candidates] == ["후보 하나", "후보 둘"]

    def test_the_outage_is_logged_as_an_error(self):
        """폴백 층이 자기 실패를 남긴다 — 조용히 죽으면 운영자가 알 방법이 없다.

        ⚠️ 원래 **2건**이었다(중복 제거 + 카테고리 매칭). 카테고리 매칭을 걷어내
        1건이 됐다. 자료가 없는 요청이라 목표 임베딩 층은 안 탄다.
        """
        import logging

        kept = [TodoCandidate(title="후보", source_item_id=1)]
        records = []
        handler = logging.Handler()
        handler.emit = records.append
        logging.getLogger("modi_ai.suggest").addHandler(handler)
        try:
            suggest(_request(excluded_todos=["이미 본 것"]), _llm(*kept), self._boom)
        finally:
            logging.getLogger("modi_ai.suggest").removeHandler(handler)

        assert sum(1 for r in records if r.levelname == "ERROR") == 1

    def test_the_log_says_which_exception_it_swallowed(self, monkeypatch):
        """게이트웨이 장애와 **우리 코드 버그**가 같은 로그로 수렴하면 안 된다.

        폴백은 `except Exception` 이라 `AttributeError`·`TypeError`·`IndexError` 까지 삼킨다.
        정책은 그대로 둔다(임베딩 장애가 추천 장애가 되면 안 된다 — 2026-07-30 P1). 다만
        재배포로만 고쳐지는 버그가 "게이트웨이 죽음"처럼 읽히면 아무도 안 본다. 타입을 남긴다.

        ⚠️ **순위 모드로 고정한다**(2026-08-09). 목표 임베딩 폴백은 유사도 축을 쓸 때만
        존재하고, 기본값인 최신순에서는 그 호출 자체가 없다 — 최신순에서 폴백이 하나 줄어드는
        것은 회귀가 아니라 이번 변경의 이득이다(`test_recency_mode_does_not_embed_the_goal`).
        """
        import logging

        from modi_ai import config
        from modi_ai import suggest as module

        monkeypatch.setattr(
            module, "get_settings", lambda: config.Settings(archive_select_by_recency=False)
        )

        kept = [TodoCandidate(title="후보", source_item_id=1)]

        def _typo(_texts):
            raise AttributeError("리팩터링 오타")

        # 자료 2건 + 벡터가 있어야 `_goal_vector` 까지 탄다 — 없으면 두 폴백 중 하나만 돈다.
        archive = [
            ArchiveItemInput(id=i, title=f"자료{i}", content="내용", embedding=[1.0, 0.0])
            for i in (1, 2)
        ]

        records = []
        handler = logging.Handler()
        handler.emit = records.append
        logging.getLogger("modi_ai.suggest").addHandler(handler)
        try:
            suggest(_request(archive=archive, excluded_todos=["이미 본 것"]), _llm(*kept), _typo)
        finally:
            logging.getLogger("modi_ai.suggest").removeHandler(handler)

        messages = [r.getMessage() for r in records if r.levelname == "ERROR"]

        # 둘 다 돌아야 한다 — 목표 임베딩 · 의미 중복. (카테고리 매칭은 -243 에서 걷어냄)
        assert len(messages) == 2, messages
        assert all("AttributeError" in m for m in messages), messages

    def test_a_malformed_embedding_response_does_not_500_either(self):
        """길이가 안 맞는 응답도 같은 경로다 — `zip(strict=True)` 가 던진다."""
        kept = [TodoCandidate(title="후보", source_item_id=1)]

        response = suggest(_request(excluded_todos=["이미 본 것"]), _llm(*kept), lambda ts: [[1.0]])

        assert [c.title for c in response.candidates] == ["후보"]

    def test_the_http_endpoint_returns_200(self):
        """`suggest()` 만이 아니라 **엔드포인트까지** 확인한다 — Spring 이 보는 것이 그것이다."""
        from fastapi.testclient import TestClient

        from modi_ai.embeddings import get_embedder
        from modi_ai.main import app
        from modi_ai.security import verify_internal_key
        from modi_ai.suggest import get_llm as production_llm

        kept = TodoCandidate(title="후보", source_item_id=1)
        app.dependency_overrides[production_llm] = lambda: _llm(kept)
        app.dependency_overrides[get_embedder] = lambda: self._boom
        app.dependency_overrides[verify_internal_key] = lambda: None
        try:
            response = TestClient(app).post(
                "/v1/todo-suggestions",
                json=_request(excluded_todos=["이미 본 것"]).model_dump(mode="json"),
            )
        finally:
            app.dependency_overrides.clear()

        assert response.status_code == 200
        assert [c["title"] for c in response.json()["candidates"]] == ["후보"]
