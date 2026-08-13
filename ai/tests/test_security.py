"""`X-Internal-Key` 검증.

이 서버는 외부에 포트를 열지 않지만, "Spring 만 호출한다"는 전제를 코드로도 못 박는다.
"""

import pytest

from modi_ai.main import app
from modi_ai.schemas import SuggestionResponse
from modi_ai.suggest import get_llm


@pytest.fixture(autouse=True)
def _stub_llm(fake_llm):
    """인증 테스트가 LLM 유무에 흔들리지 않게 고정한다."""
    app.dependency_overrides[get_llm] = lambda: fake_llm(parsed=SuggestionResponse())
    yield
    app.dependency_overrides.clear()


class TestWithKeyConfigured:
    @pytest.fixture(autouse=True)
    def _set_key(self, monkeypatch):
        # 환경변수가 .env 보다 우선하므로 개발자의 .env 값과 무관하게 동작한다.
        monkeypatch.setenv("INTERNAL_API_KEY", "test-internal-key")

    def test_rejects_request_without_header(self, client, sample_request):
        res = client.post("/v1/todo-suggestions", json=sample_request)

        assert res.status_code == 401

    def test_rejects_request_with_wrong_key(self, client, sample_request):
        res = client.post(
            "/v1/todo-suggestions", json=sample_request, headers={"X-Internal-Key": "wrong"}
        )

        assert res.status_code == 401

    def test_accepts_request_with_correct_key(self, client, sample_request):
        res = client.post(
            "/v1/todo-suggestions",
            json=sample_request,
            headers={"X-Internal-Key": "test-internal-key"},
        )

        assert res.status_code == 200

    def test_health_stays_open(self, client):
        """컨테이너 헬스체크는 키를 모른다 — 막으면 기동 판정이 실패한다."""
        assert client.get("/v1/health").status_code == 200


class TestWithoutKeyConfigured:
    @pytest.fixture(autouse=True)
    def _clear_key(self, monkeypatch):
        monkeypatch.setenv("INTERNAL_API_KEY", "")

    def test_skips_verification_so_local_curl_works(self, client, sample_request):
        res = client.post("/v1/todo-suggestions", json=sample_request)

        assert res.status_code == 200
