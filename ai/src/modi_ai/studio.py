"""LangGraph Studio 진입점 — **개발 전용. 운영 경로에 끼지 않는다.**

    cd ai && PYTHONUTF8=1 uv run --group studio langgraph dev

브라우저가 열리고 `smith.langchain.com/studio` 가 로컬 서버(127.0.0.1:2024)에 붙는다.
`LANGSMITH_API_KEY` 가 필요하다(`ai/.env`).

⚠️ **`PYTHONUTF8=1` 이 없으면 안 뜬다** — cp949 윈도우에서 세 군데가 각각 죽는다.
`langgraph.json` · `ai/.env`(둘 다 한글이 들어 있다) · **`langgraph_api` 가 자기 패키지에
번들한 `openapi.json`**(라이브러리 쪽 문제라 우리가 못 고친다). UTF-8 모드가 셋을 한 번에
해결한다. 실제로 세 번 연달아 겪었다.

## 왜 필요한가

에서 `critique → generate` **되돌아가는 엣지**가 생겼다. 그 전까지 그래프는
직선이라 볼 것이 없었고 `docs/DECISIONS.md` 도 "기능 이득 0"이라고 적어뒀다. 이제는 실행마다
**어느 후보가 반려돼서 몇 번 되돌아갔는지**가 다르고, 그건 트레이스 목록보다 그림으로 보는
쪽이 훨씬 빠르다.

## 왜 별도 그래프가 필요한가

`SuggestState` 는 `llm` 과 `embed` 를 **상태로** 들고 다닌다(호출부가 주입한다 — 크레딧 0 으로
테스트하기 위한 설계다). Studio 의 입력은 JSON 이라 그 둘을 넣을 방법이 없다.

그래서 **`prepare` 노드 하나를 앞에 붙여** 서버 쪽에서 만들어 넣는다. 나머지 노드·엣지는
`_build_graph` 를 그대로 재사용한다 — Studio 쪽에서 배선을 다시 선언하면 **그림과 실제
파이프라인이 조용히 갈린다.** 그 동일성은 `tests/test_studio_graph.py` 가 지킨다.

## 입력 예시 (Studio 의 Input 창에 붙여넣는다)

    {
      "request": {
        "room": {"name": "주우", "goal": "부산 여행",
                 "start_date": "2026-07-28", "end_date": "2026-08-05"},
        "existing_todos": [],
        "excluded_todos": [],
        "archive": [{"id": 1, "title": "부산 2박3일 코스",
                     "content": "서면 돼지국밥, 모모스커피, 흰여울문화마을을 다녀온다."}]
      },
      "candidates": [], "rejected": [], "attempts": 0, "passed": []
    }

얼려둔 방 픽스처를 그대로 쓰려면 `evals/data/rooms/*.json` 의 `request` 를 복사한다
(임베딩이 실려 있어 크지만 Studio 가 받는다).

⚠️ **실제 LLM 을 호출한다 — 크레딧을 쓴다.** 그리고 `LANGSMITH_TRACING` 이 켜져 있으면
자료 본문이 LangSmith 로 올라간다. 운영에서는 둘 다 금지다(`ai/CLAUDE.md`).

⚠️ **`ai/.env` 가 Studio 를 운영과 다르게 만들 수 있다.** `langgraph.json` 이 `.env` 를
읽고, `_has_candidates`/`_should_regenerate` 는 `get_settings()` 를 **호출 시점에** 부른다.
그래서 `.env` 에 `CRITIQUE_MAX_ATTEMPTS` 나 다른 `OPENAI_MODEL` 이 들어 있으면 **Studio 가
운영과 다른 경로를 보여주면서 아무 경고도 안 낸다.** 그림과 실제가 갈리면 Studio 로 한
디버깅이 거짓말이 되므로, 볼 때 `.env` 를 먼저 확인할 것(2026-08-03 리뷰 지적).

⚠️ **`langgraph.json` 은 ASCII 로만 쓴다.** CLI 가 그 파일을 **플랫폼 기본 인코딩**으로
읽어서(윈도우 cp949) 한글 주석을 넣으면 `UnicodeDecodeError` 로 기동이 죽는다 — 실제로 겪었다.
설명은 전부 이 파일에 둔다.
"""

from modi_ai.embeddings import get_embedder
from modi_ai.suggest import _build_graph
from modi_ai.suggest import get_llm as _get_llm


def _inject_dependencies(state) -> dict:  # noqa: ANN001 — SuggestState, 순환 import 회피
    """JSON 으로 못 넣는 의존성을 서버 쪽에서 만들어 상태에 채운다.

    **이 노드는 운영 그래프에 없다.** `suggest()` 는 호출부가 준 것을 그대로 쓴다.
    """
    return {"llm": _get_llm(), "embed": get_embedder()}


graph = _build_graph(prepare=_inject_dependencies)
