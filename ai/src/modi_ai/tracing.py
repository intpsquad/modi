"""LangSmith 추적 배선.

**왜 이 모듈이 따로 필요한가.** pydantic-settings 는 `.env` 를 읽어 `Settings` 객체에만
채우고 `os.environ` 에는 넣지 않는다. 반면 LangSmith SDK 는 `os.environ` 만 본다. 그래서
`ai/.env` 에 `LANGSMITH_TRACING=true` 를 적어도 추적은 켜지지 않는다 — 실측으로 확인했다
(`settings.langsmith_tracing` 는 True 인데 `tracing_is_enabled()` 는 False). 여기서 그
간극을 메운다.

**운영 기본값은 꺼짐이다.** 켜면 사용자 자료 본문이 제3자 SaaS 로 전송되고, 개인정보
처리위탁 명시와 Play Console 데이터 보안 신고 대상이 된다(`docs/DECISIONS.md`).
그래서 끌 때도 환경변수를 명시적으로 `false` 로 박는다 — 셸에 켜진 값이 남아 있어도
설정이 이긴다.
"""

import logging
import os

from modi_ai.config import Settings, get_settings

log = logging.getLogger(__name__)

_TRACING_ENV = "LANGSMITH_TRACING"
_API_KEY_ENV = "LANGSMITH_API_KEY"
_PROJECT_ENV = "LANGSMITH_PROJECT"

# SDK 는 `LANGSMITH_TRACING_V2` → `LANGCHAIN_TRACING_V2` → `LANGSMITH_TRACING` →
# `LANGCHAIN_TRACING` 순으로 먼저 찾은 값을 쓴다(`langsmith.utils.tracing_is_enabled`).
# 즉 셸에 남은 `LANGCHAIN_TRACING_V2=false` 하나가 우리가 켠 `LANGSMITH_TRACING=true` 를
# 이긴다. 그래서 앞자리 이름들을 지워 `LANGSMITH_TRACING` 하나만 스위치로 남긴다.
_OVERRIDING_ENVS = ("LANGSMITH_TRACING_V2", "LANGCHAIN_TRACING_V2", "LANGCHAIN_TRACING")


def configure_tracing(settings: Settings | None = None) -> bool:
    """설정값을 `os.environ` 으로 옮긴다. 실제로 켜졌는지를 돌려준다.

    키가 비어 있으면 `langsmith_tracing=True` 여도 켜지 않는다 — "키가 없으면 그 기능만
    비활성, 나머지는 그대로 동작"(`security.verify_internal_key` 와 같은 방향).
    """
    settings = settings or get_settings()

    if not settings.langsmith_tracing:
        _turn_off()
        return False

    if not settings.langsmith_api_key:
        log.warning(
            "LANGSMITH_TRACING=true 이지만 LANGSMITH_API_KEY 가 비어 있어 추적을 켜지 않는다"
        )
        _turn_off()
        return False

    _write_env("true")
    os.environ[_API_KEY_ENV] = settings.langsmith_api_key
    os.environ[_PROJECT_ENV] = settings.langsmith_project
    log.warning(
        "LangSmith 추적 켜짐 (project=%s) — 자료 본문이 외부로 전송된다. 개발 환경 전용이다.",
        settings.langsmith_project,
    )
    return True


def _turn_off() -> None:
    _write_env("false")


def _write_env(value: str) -> None:
    for name in _OVERRIDING_ENVS:
        os.environ.pop(name, None)
    os.environ[_TRACING_ENV] = value
    _invalidate_sdk_cache()


def _invalidate_sdk_cache() -> None:
    """`langsmith.utils.get_env_var` 는 `lru_cache` 라 첫 읽기 값을 그대로 물고 있다.

    방금 환경을 바꿨으니 캐시는 낡았다. 비우지 않으면 프로세스가 살아 있는 동안 설정이
    영영 반영되지 않는다(실측: 켜도 `tracing_is_enabled()` 가 False 로 남았다).
    캐시가 사라진 버전이면 비울 것도 없으므로 조용히 넘어간다.
    """
    from langsmith import utils as langsmith_utils

    cache_clear = getattr(langsmith_utils.get_env_var, "cache_clear", None)
    if cache_clear is not None:
        cache_clear()
