"""임베딩 클라이언트.

용도는 **후보 제목의 의미 중복 판정** 하나다. 자료(아카이브) 임베딩은 이 모듈이 아니라
Spring 이 등록 시점에 만들어 저장하며(RAG 2단계, 별도 티켓) 여기서는 다루지 않는다.

`get_llm`(`suggest.py`)과 같은 모양으로 만든 이유는 둘이다.
  1. 요청마다 `Depends` 로 주입되므로 테스트가 `app.dependency_overrides` 로 갈아끼울 수 있다
     — 실제 API 를 부르지 않아 크레딧이 0 이고 키 없는 CI 에서도 같은 결과가 나온다.
  2. 키 검증 시점이 "빈 생성"이 아니라 "요청"이라, 키가 없어도 서버는 뜨고 헬스체크는 산다
     (`config.py` 주석의 원칙).
"""

import logging
from collections.abc import Callable

from fastapi import HTTPException, status
from langchain_openai import OpenAIEmbeddings

from modi_ai.config import get_settings

log = logging.getLogger(__name__)

# 여러 문자열을 한 번에 넘기고 같은 순서로 벡터를 받는다. 배치로 받는 것이 중요하다 —
# 제목 하나마다 호출하면 추천 1회에 최대 58 번을 부르게 된다.
Embedder = Callable[[list[str]], list[list[float]]]


def get_embedder() -> Embedder:
    """FastAPI 의존성. 테스트는 `app.dependency_overrides` 로 이걸 갈아끼운다."""
    settings = get_settings()
    if not settings.openai_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="OPENAI_API_KEY is not configured",
        )
    client = OpenAIEmbeddings(
        model=settings.openai_embedding_model,
        base_url=settings.openai_base_url,
        api_key=settings.openai_api_key,
        # **Spring 의 예산 안에 들어와야 한다.** AiServerConfig 의 read timeout 이 60초인데
        # 추천 1회는 LLM 8~11초를 이미 쓴다(실측). 여기서 30초 x 2회(재시도) = 60초를 쓰면
        # 합계가 Spring 예산을 넘겨 **Spring 이 먼저 끊는다** — 그러면 아래 폴백이 후보를
        # 살려 반환해도 사용자는 "AI 추천 서버에 연결하지 못했어요"만 본다. 폴백을 둔 이유가
        # 그 구간에서 무의미해진다(2026-07-30 리뷰 P1).
        # 실측은 제목 24개 배치 1회에 2.73초였다 → 10초 x 2회 = 최악 20초로 잡는다.
        timeout=10,
        max_retries=1,
        # tiktoken 으로 토큰을 세어 직접 자르는 경로를 끈다. 우리 입력은 50 자 이내 제목이라
        # 자를 것이 없고, 그 경로가 예상 밖으로 동작하면 원인 찾기가 어렵다.
        check_embedding_ctx_length=False,
    )
    return client.embed_documents
