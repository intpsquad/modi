import inspect

from fastapi.testclient import TestClient

from modi_ai.main import app, health

client = TestClient(app)


def test_health_returns_ok():
    res = client.get("/v1/health")

    assert res.status_code == 200
    assert res.json() == {"status": "ok"}


def test_health_does_not_require_api_key():
    """키가 없어도 헬스체크는 떠야 한다 — 컨테이너 기동 판정에 쓰이기 때문."""
    res = client.get("/v1/health")

    assert res.status_code == 200


def test_health_runs_on_the_event_loop_not_the_threadpool():
    """`def` 로 두면 추천과 **같은 스레드풀**(기본 40)을 쓴다 — 추천이 풀을 채우면 굶는다.

    응답 시간으로 재려면 스레드풀을 좁히고 느린 추천을 밀어 넣어야 하는데, 그 테스트는
    타이밍 의존이라 CI 에서 흔들린다. 대신 **원인을 직접 못 박는다.** starlette 는
    코루틴이 아닌 핸들러만 `run_in_threadpool` 로 보낸다.
    """
    assert inspect.iscoroutinefunction(health), (
        "health 가 sync 다 — 추천과 스레드풀을 공유해 컨테이너가 unhealthy 로 뒤집힌다"
    )
