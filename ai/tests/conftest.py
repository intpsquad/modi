"""테스트 공용 픽스처.

**테스트에서 실제 LLM 을 호출하지 않는다** — 크레딧을 태우지 않고, 키가 없는 CI 에서도
같은 결과가 나와야 한다. `suggest.get_llm` 을 가짜로 갈아끼우는 방식으로 격리한다.
"""

import os
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from langsmith.utils import tracing_is_enabled

from modi_ai import tracing
from modi_ai.config import get_settings
from modi_ai.main import app

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
        return {
            "raw": FakeRaw(),
            "parsed": self._model.parsed,
            "parsing_error": self._model.parsing_error,
        }


class FakeChatModel:
    """`suggest()` 가 실제로 쓰는 두 가지(`with_structured_output` → `invoke`)만 흉내낸다.

    `calls` 에 호출마다 받은 메시지를 쌓는다 — **추천 1회 = LLM 1회**(#109)를 이 개수로 잰다.
    """

    def __init__(self, parsed=None, parsing_error=None) -> None:
        self.parsed = parsed
        self.parsing_error = parsing_error
        self.calls: list = []

    def with_structured_output(self, schema, include_raw: bool = False):
        return _FakeStructuredRunnable(self, schema)


@pytest.fixture
def fake_llm():
    """`FakeChatModel` 생성기.

    테스트 파일이 conftest 를 직접 import 하지 않게 픽스처로 노출한다 — pytest 기본 import
    모드에서는 `tests` 가 패키지가 아니라 `from tests.conftest import ...` 가 깨진다.
    """

    def _make(parsed=None, parsing_error=None) -> FakeChatModel:
        return FakeChatModel(parsed=parsed, parsing_error=parsing_error)

    return _make


@pytest.fixture
def client() -> Iterator[TestClient]:
    """엔드포인트 테스트용. LLM 은 각 테스트가 `app.dependency_overrides[get_llm]` 으로 끼운다."""
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
