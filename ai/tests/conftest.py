"""테스트 공용 픽스처.

**테스트에서 실제 LLM 을 호출하지 않는다** — 크레딧을 태우지 않고, 키가 없는 CI 에서도
같은 결과가 나와야 한다. `suggest.get_llm` 을 가짜로 갈아끼우는 방식으로 격리한다.
"""

import os
import re
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from langsmith.utils import tracing_is_enabled

from modi_ai import tracing
from modi_ai.config import get_settings
from modi_ai.embeddings import get_embedder
from modi_ai.main import app
from modi_ai.schemas import CritiqueResponse, CritiqueVerdict
from modi_ai.suggest import CRITIQUE_INDEX_BASE

# 검수 프롬프트가 후보를 넘기는 모양(`1. 제목`). 가짜가 개수를 세는 데 쓴다.
_NUMBERED = re.compile(r"^\d+\. ")

_TRACING_ENVS = (
    "LANGSMITH_TRACING",
    "LANGSMITH_TRACING_V2",
    "LANGCHAIN_TRACING_V2",
    "LANGCHAIN_TRACING",
    "LANGSMITH_API_KEY",
    "LANGSMITH_PROJECT",
)


@pytest.fixture(scope="session", autouse=True)
def _never_trace_from_tests() -> Iterator[None]:
    """테스트에서 LangSmith 업로드가 **구조적으로** 불가능하게 만든다.

    `modi_ai.main` 을 import 하면 그 시점에 `configure_tracing()` 이 돌고, 개발자의
    `ai/.env` 가 `LANGSMITH_TRACING=true` 이면 **pytest 프로세스가 추적 켜진 상태로 돈다.**
    지금 아무것도 올라가지 않는 것은 `FakeChatModel` 이 langchain Runnable 이 아니어서
    트레이스가 만들어지지 않기 때문일 뿐이다 — 누군가 `FakeListChatModel` 같은 진짜
    Runnable 로 바꾸면 테스트 페이로드가 개발자 프로젝트로 조용히 올라간다.

    **env 를 지우는 것만으로는 부족하다**(리뷰 지적). `langsmith.utils.get_env_var` 가
    `lru_cache` 라, 수집 시점에 이미 한 번 읽혔으면 그 값이 캐시에 남아 이 픽스처가 무효가
    된다. 그래서 캐시를 비우고 **실제로 꺼졌는지 단언**한다 — 주장과 구현을 일치시킨다.

    `test_tracing.py` 는 `configure_tracing` 을 직접 호출해 검증하므로 이 픽스처와 충돌하지
    않는다(자기 픽스처로 환경을 다시 세운다).
    """
    saved = {name: os.environ.get(name) for name in _TRACING_ENVS}
    for name in _TRACING_ENVS:
        os.environ.pop(name, None)
    os.environ["LANGSMITH_TRACING"] = "false"
    tracing._invalidate_sdk_cache()
    assert tracing_is_enabled() is False, "테스트 세션에서 LangSmith 추적이 꺼지지 않았다"
    yield
    for name, value in saved.items():
        if value is None:
            os.environ.pop(name, None)
        else:
            os.environ[name] = value
    tracing._invalidate_sdk_cache()


@pytest.fixture(autouse=True)
def _clear_settings_cache() -> Iterator[None]:
    """`get_settings` 가 `lru_cache` 라, 환경변수를 바꾸는 테스트는 캐시를 비워야 한다."""
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


class FakeRaw:
    """`usage_metadata` 만 있으면 되는 최소 응답 객체."""

    def __init__(self, usage: dict[str, int] | None = None) -> None:
        self.usage_metadata = usage or {"input_tokens": 0, "output_tokens": 0, "total_tokens": 0}


class _FakeStructuredRunnable:
    def __init__(self, model: "FakeChatModel", schema) -> None:
        self._model = model
        self._schema = schema

    def invoke(self, messages: list):
        self._model.calls.append(messages)
        if self._schema is CritiqueResponse:
            self._model.critique_calls.append(messages)
            return self._model.critique_for(messages)
        return {
            "raw": FakeRaw(),
            "parsed": self._model.parsed,
            "parsing_error": self._model.parsing_error,
        }


class FakeChatModel:
    """`suggest()` 가 실제로 쓰는 두 가지(`with_structured_output` → `invoke`)만 흉내낸다.

    **스키마를 본다** 검수 노드는 `CritiqueResponse` 로 부르고 `include_raw`
    를 안 쓰므로 dict 가 아니라 파싱된 객체를 기대한다.

    기본 판정은 **전부 통과**다 — 그래야 검수 노드가 끼어들기 전에 쓰인 테스트들이 **의미를
    그대로 유지**한다. 통과 대신 폴백(전부 통과)으로 넘어가면 테스트가 통과는 하지만 아무것도
    안 재게 된다. 반려를 시키려면 `critique` 에 판정 목록을 준다.
    """

    def __init__(self, parsed=None, parsing_error=None, critique=None) -> None:
        self.parsed = parsed
        self.parsing_error = parsing_error
        self.calls: list = []
        self.critique_calls: list = []
        self._critique = list(critique) if critique is not None else None

    def with_structured_output(self, schema, include_raw: bool = False):
        return _FakeStructuredRunnable(self, schema)

    def critique_for(self, messages: list) -> CritiqueResponse:
        """`critique` 를 안 주면 **입력에 적힌 번호만큼 전부 통과**를 만들어 돌려준다.

        ⚠️ **번호는 운영과 같은 기준에서 시작해야 한다** 여기가 0 부터면
        운영의 번호 검사가 어긋나 **모든 그래프 테스트가 fail-open 을 타고** 통과한다 —
        초록인 채로 검수를 하나도 안 재게 된다.
        """
        if self._critique:
            return self._critique.pop(0)
        count = sum(1 for line in str(messages[-1].content).splitlines() if _NUMBERED.match(line))
        return CritiqueResponse(
            verdicts=[
                CritiqueVerdict(index=i, ok=True)
                for i in range(CRITIQUE_INDEX_BASE, CRITIQUE_INDEX_BASE + count)
            ]
        )


@pytest.fixture
def fake_llm():
    """`FakeChatModel` 생성기.

    테스트 파일이 conftest 를 직접 import 하지 않게 픽스처로 노출한다 — pytest 기본 import
    모드에서는 `tests` 가 패키지가 아니라 `from tests.conftest import ...` 가 깨진다.
    """

    def _make(parsed=None, parsing_error=None, critique=None) -> FakeChatModel:
        return FakeChatModel(parsed=parsed, parsing_error=parsing_error, critique=critique)

    return _make


class FakeEmbedder:
    """제목을 **미리 정해둔 벡터**로 바꿔주는 가짜 임베더.

    실제 임베딩 API 를 부르지 않는 이유는 `FakeChatModel` 과 같다 — 크레딧 0 이고, 키 없는
    CI 에서도 같은 결과가 나와야 한다. 유사도 판정 로직만 재려면 벡터가 실제 의미를 반영할
    필요가 없고, 오히려 **직접 정한 벡터**여야 "임계값 위/아래"를 확정적으로 테스트할 수 있다.

    등록되지 않은 제목은 서로 직교하는 축을 하나씩 받는다(= 유사도 0).

    **모든 벡터를 같은 차원으로 패딩한다.** 이게 없으면 등록된 벡터(길이 2)와 미등록 벡터가
    한 호출에 섞일 때 `_cosine` 의 `zip(strict=True)` 가 터지고, 그 예외를 폴백이 조용히
    삼켜 **테스트가 통과하는 것처럼 보인다**(2026-07-30 리뷰 P2-5).
    """

    DIM = 64

    def __init__(self, vectors: dict[str, list[float]] | None = None) -> None:
        self.vectors = vectors or {}
        self.calls: list[list[str]] = []

    def _pad(self, vector: list[float]) -> list[float]:
        if len(vector) > self.DIM:
            raise ValueError(f"FakeEmbedder.DIM({self.DIM}) 보다 긴 벡터를 등록했다")
        return list(vector) + [0.0] * (self.DIM - len(vector))

    def __call__(self, texts: list[str]) -> list[list[float]]:
        self.calls.append(list(texts))
        result = []
        for index, text in enumerate(texts):
            if text in self.vectors:
                result.append(self._pad(self.vectors[text]))
            else:
                # 미등록 제목은 서로 직교하게 — 등록된 벡터가 쓰는 앞쪽 축은 피한다.
                axis = [0.0] * self.DIM
                axis[self.DIM - 1 - (index % (self.DIM // 2))] = 1.0
                result.append(axis)
        return result


@pytest.fixture
def fake_embedder():
    """`FakeEmbedder` 생성기. `fake_llm` 과 같은 이유로 픽스처로 노출한다."""

    def _make(vectors: dict[str, list[float]] | None = None) -> FakeEmbedder:
        return FakeEmbedder(vectors=vectors)

    return _make


@pytest.fixture
def client() -> Iterator[TestClient]:
    """엔드포인트 테스트용. **임베더는 기본으로 가짜를 끼운다.**

    `/v1/todo-suggestions` 가 `Depends(get_embedder)` 를 쓰기 때문에 이걸
    안 끼우면 FastAPI 가 의존성을 해석하는 단계에서 실제 `get_embedder()` 를 부르고, 키가 없는
    CI 에서 핸들러에 닿기도 전에 503 이 난다. 유사도 판정을 직접 재는 테스트는 이 오버라이드를
    자기 것으로 다시 덮으면 된다.
    """
    app.dependency_overrides[get_embedder] = lambda: FakeEmbedder()
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def sample_request() -> dict:
    return {
        "room": {
            "name": "오픽 스터디",
            "goal": "오픽 IH 달성",
            "goal_detail": None,
            "start_date": "2026-08-01",
            "end_date": "2026-08-20",
        },
        "categories": ["공부"],
        "existing_todos": ["교재 사기"],
        "excluded_todos": [],
        "archive": [
            {
                "id": 12,
                "title": "오픽 공부법",
                "content": "오픽 IH를 받으려면 스크립트를 외우기보다 답변 틀을 만드는 게 낫다.",
                "tags": ["오픽", "꿀팁"],
            }
        ],
    }
