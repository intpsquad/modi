"""modi AI 서버 진입점.

앱(Flutter) → 서버(Spring) → **AI 서버(FastAPI)** → OpenAI 의 3층 구조에서 맨 오른쪽.
앱이 직접 호출하지 않으며, 도메인 DB의 주인도 아니다(원본은 Spring + PostgreSQL).

담당 범위는 **투두 추천(S-16-B) 하나**다. 아카이브 자동 태깅(S-25-C)은 Spring이
게이트웨이를 직접 호출해 처리하며 이 서버를 거치지 않는다(docs/DECISIONS.md 확정, 2026-07-28).
"""

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI
from langchain_core.language_models import BaseChatModel
from pydantic import BaseModel

from modi_ai import __version__
from modi_ai.embeddings import Embedder, get_embedder
from modi_ai.schemas import SuggestionRequest, SuggestionResponse
from modi_ai.security import verify_internal_key
from modi_ai.suggest import get_llm, suggest
from modi_ai.tracing import configure_tracing

# uvicorn 은 자기 로거만 설정하므로 앱 로거(`modi_ai.*`)는 기본값(WARNING)에 머문다.
# 추천 호출의 토큰 사용량을 남기는 것이 목적이라 INFO 까지 열어둔다.
logging.basicConfig(level=logging.INFO, format="%(levelname)s:%(name)s:%(message)s")


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    """LangSmith 배선을 **기동 시점에** 한다 — import 시점에 하면 안 된다.

    `configure_tracing()` 은 `os.environ` 을 건드린다. 모듈 import 만으로 그게 돌면
    **이 모듈을 import 하는 모든 것**(테스트 수집 포함)이 개발자 `.env` 의 실제 키로 추적을
    켜버린다. 실제로 pytest 가 그 상태로 돌던 것이 리뷰에서 잡혔다.

    LLM 클라이언트는 요청마다 `Depends(get_llm)` 로 만들어지므로 기동 시점이면 충분히 이르다.
    """
    configure_tracing()
    yield


app = FastAPI(
    title="modi AI server",
    description="투두 추천(S-16-B)",
    version=__version__,
    docs_url="/docs",
    lifespan=lifespan,
)


class HealthResponse(BaseModel):
    status: str


@app.get("/v1/health", response_model=HealthResponse, tags=["system"])
async def health() -> HealthResponse:
    """기동 확인용. 외부 의존(OpenAI·DB)을 타지 않는다 —
    이 엔드포인트가 외부 API 상태까지 확인하면 컨테이너 헬스체크가
    남의 장애로 실패하게 된다.

    ⚠️ **`async` 여야 한다.** `def` 로 두면 starlette 가 `todo_suggestions` 와 **같은
    스레드풀**(기본 40)로 보낸다. 추천 1회는 최악 300초(LLM 120x2 + 임베딩 10x2 x 2배치)라
    인플라이트가 풀을 채우면 헬스체크가 굶고, `deploy/docker-compose.app.yml` 의
    `timeout: 5s / retries: 6` 이 걸려 **멀쩡한 컨테이너가 unhealthy 로 뒤집힌다.**
    여기는 외부 의존이 없는 순수 함수라 이벤트 루프에서 직접 돌아도 안전하다.
    """
    return HealthResponse(status="ok")


@app.post(
    "/v1/todo-suggestions",
    response_model=SuggestionResponse,
    tags=["suggestions"],
    dependencies=[Depends(verify_internal_key)],
)
def todo_suggestions(
    request: SuggestionRequest,
    llm: Annotated[BaseChatModel, Depends(get_llm)],
    embed: Annotated[Embedder, Depends(get_embedder)],
) -> SuggestionResponse:
    """S-16-B 투두 후보 생성. 앱이 아니라 Spring 만 호출한다.

     채택된 후보의 담당자는 미지정으로 남는다(`full_spec.md` S-16-B) — 이 서버는 관여하지 않는다.

     `embed` 는 이미 노출한 후보와 **의미가** 겹치는 것을 걸러내는 데만 쓴다
    . 자료 임베딩(RAG 2단계)은 이 서버가 만들지 않는다.
    """
    return suggest(request, llm, embed)
