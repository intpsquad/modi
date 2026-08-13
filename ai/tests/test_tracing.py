"""LangSmith 추적 배선.

`.env` 값이 실제로 SDK 까지 도달하는지만 본다. 네트워크도 크레딧도 쓰지 않는다 —
트레이스를 만들지 않고 플래그만 확인한다.
"""

import os

import pytest
from langsmith.utils import tracing_is_enabled

from modi_ai.config import Settings
from modi_ai.tracing import configure_tracing

_ENVS = (
    "LANGSMITH_TRACING",
    "LANGSMITH_API_KEY",
    "LANGSMITH_PROJECT",
    "LANGSMITH_TRACING_V2",
    "LANGCHAIN_TRACING_V2",
    "LANGCHAIN_TRACING",
)


@pytest.fixture(autouse=True)
def _isolate_env():
    """개발자 셸에 남아 있는 값이 판정을 흔들지 않게 지우고, **끝나면 되돌린다.**

    `monkeypatch.delenv` 만으로는 안 된다 — 원래 없던 키는 undo 가 기록되지 않는데
    `configure_tracing` 은 진짜 `os.environ` 에 쓴다. 그래서 CI 처럼 변수가 없던 환경에서는
    이 파일 이후 모든 테스트가 `LANGSMITH_TRACING=true` + 가짜 키를 물고 돌았다.
    저장·복원을 직접 한다.
    """
    saved = {name: os.environ.get(name) for name in _ENVS}
    for name in _ENVS:
        os.environ.pop(name, None)
    yield
    for name, value in saved.items():
        if value is None:
            os.environ.pop(name, None)
        else:
            os.environ[name] = value


def _settings(**kwargs) -> Settings:
    """`.env` 를 읽지 않는 Settings — 개발자 로컬 파일과 무관하게 같은 결과를 낸다."""
    return Settings(_env_file=None, **kwargs)


class TestDisabled:
    def test_returns_false_and_pins_env_off(self):
        enabled = configure_tracing(_settings(langsmith_tracing=False))

        assert enabled is False
        assert os.environ["LANGSMITH_TRACING"] == "false"
        assert tracing_is_enabled() is False

    def test_overwrites_a_stale_on_value(self, monkeypatch):
        """셸에 켜진 값이 남아 있어도 설정이 끄기면 꺼야 한다 — 운영 기본값이 꺼짐이다."""
        monkeypatch.setenv("LANGSMITH_TRACING", "true")

        assert configure_tracing(_settings(langsmith_tracing=False)) is False
        assert tracing_is_enabled() is False


class TestEnabledWithoutKey:
    def test_stays_off(self):
        """키가 없으면 그 기능만 비활성 — `security.verify_internal_key` 와 같은 방향."""
        enabled = configure_tracing(_settings(langsmith_tracing=True, langsmith_api_key=""))

        assert enabled is False
        assert tracing_is_enabled() is False


class TestEnabledWithKey:
    def test_reaches_the_sdk(self):
        """이 단언이 이 모듈의 존재 이유다.

        pydantic-settings 는 `.env` 를 Settings 객체에만 채우고 `os.environ` 에는 넣지
        않는데, LangSmith SDK 는 `os.environ` 만 본다. 배선이 없으면 여기서 False 가 난다.
        """
        settings = _settings(
            langsmith_tracing=True,
            langsmith_api_key="fake-key-not-used-for-network",
            langsmith_project="modi-ai-test",
        )

        enabled = configure_tracing(settings)

        assert enabled is True
        assert tracing_is_enabled() is True
        assert os.environ["LANGSMITH_API_KEY"] == "fake-key-not-used-for-network"
        assert os.environ["LANGSMITH_PROJECT"] == "modi-ai-test"

    def test_stale_legacy_var_does_not_win(self, monkeypatch):
        """SDK 는 `LANGCHAIN_TRACING_V2` 를 `LANGSMITH_TRACING` 보다 먼저 본다.

        셸에 남은 구세대 값 하나가 우리가 켠 설정을 이기면 안 된다.
        """
        monkeypatch.setenv("LANGCHAIN_TRACING_V2", "false")

        enabled = configure_tracing(_settings(langsmith_tracing=True, langsmith_api_key="fake-key"))

        assert enabled is True
        assert tracing_is_enabled() is True
