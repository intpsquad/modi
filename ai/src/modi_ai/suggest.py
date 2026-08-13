"""투두 추천 파이프라인.

LLM 호출 1회 구조다. 순수 함수(`build_payload`/`filter_candidates`)와 LLM 호출을 갈라놓아
크레딧 0으로 로직 전체를 테스트한다.

프롬프트에 들어가는 자료 텍스트는 `ArchiveItemInput.content` 하나뿐이고, 그게 요약인지 본문인지는
**Spring이 이미 골라서 보낸다**(요약·본문 중 짧은 쪽). 이 서버는 구분하지 않는다 — 선택 규칙이
양쪽에 흩어지면 어느 쪽이 이겼는지 추적이 안 되기 때문이다. 근거는 `docs/DECISIONS.md`
(`V5` 마이그레이션).

임베딩은 **두 군데** 쓴다 — 외부 호출이 LLM 1회 + 임베딩 2회다.
  1. 후보 제목의 의미 중복 판정(`drop_semantic_duplicates`) — LLM 뒤
  2. **방 목표 ↔ 자료의 유사도** — 프롬프트에 실을 자료의 순위를 매긴다. LLM 앞이라 합칠 수 없다
     (`_select_archive` → `ranking.py`)

⚠️ **셋째가 있었다** — 후보 주제를 방의 기존 카테고리에 매칭하는 층(
`map_categories`). 2026-08-04 에 **카테고리 배정 자체를 걷어냈다** — AI 는
카테고리를 정하지 않고 후보는 기타로 나간다. 왜 지웠는지와 되살리는 방법은
`docs/RESTORE-category-assignment.md`. `_batching` 이 두 소비자를 묶으려고 만든 것인데 이제
`dedupe` 하나만 쓴다 — 단순화는 `specs/OPEN.md` 의 후속 항목이다.

자료는 **항상 순위대로 정렬해서** 넣고, 누적 길이가 예산을 넘을 때만 뒤쪽을 버린다. 개수 상한은
여전히 없다 — 근거 없는 숫자를 박지 않으려는 것이고, 예산은 튜닝값이 아니라 안전밸브다
(`config.archive_prompt_budget_chars`).
"""

import functools
import logging
import time
from collections.abc import Callable
from datetime import date
from typing import TypedDict

from fastapi import HTTPException, status
from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from langgraph.graph import END, START, StateGraph

from modi_ai.config import get_settings
from modi_ai.embeddings import Embedder
from modi_ai.prompts import CRITIQUE_PROMPT, SYSTEM_PROMPT
from modi_ai.ranking import cosine, select_archive
from modi_ai.schemas import (
    MAX_TITLE_LENGTH,
    ArchiveItemInput,
    CritiqueResponse,
    SuggestionRequest,
    SuggestionResponse,
    TodoCandidate,
)

log = logging.getLogger(__name__)


def get_llm() -> BaseChatModel:
    """FastAPI 의존성. 테스트는 `app.dependency_overrides` 로 이걸 갈아끼운다."""
    settings = get_settings()
    if not settings.openai_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="OPENAI_API_KEY is not configured",
        )
    return ChatOpenAI(
        model=settings.openai_model,
        base_url=settings.openai_base_url,
        api_key=settings.openai_api_key,
        timeout=120,
        max_retries=1,
    )


def _normalize(title: str) -> str:
    """중복 판정용 정규화 — 글자가 같은 것만 잡는다.

    의미가 같고 표현만 다른 것은 이 함수로 못 잡는다. 그 층은 `drop_semantic_duplicates`
    (임베딩 코사인 유사도)가 담당한다.
    """
    return "".join(title.split()).lower()


def _days_left_phrase(today: date, end_date: date) -> str:
    """`오늘:` 줄의 괄호 안. **음수 일수를 프롬프트에 흘리지 않는다.**

    `(종료까지 -5일)` 은 모델이 뭘로 읽을지 알 수 없고, `(종료까지 0일)` 은 마지막 날인데
    "남은 게 없다"로 읽힌다. 종료된 방은 추천을 부르지 않으므로 뒤 두 가지는 실제로 오지
    않는 경로지만, 프롬프트에 뜻이 흐린 문장을 두지 않는다.
    """
    days_left = (end_date - today).days
    if days_left > 0:
        return f"종료까지 {days_left}일"
    return "오늘이 종료일" if days_left == 0 else "종료일 지남"


def build_payload(request: SuggestionRequest) -> str:
    """LLM 에 넘길 사용자 메시지. 전부 신뢰하지 않는 데이터라 system 이 아니라 human 으로 간다."""
    room = request.room
    lines = [
        "# 방 정보",
        f"- 이름: {room.name}",
        f"- 목표: {room.goal}",
    ]
    if room.goal_detail:
        lines.append(f"- 목표 상세: {room.goal_detail}")
    lines.append(f"- 기간: {room.start_date} ~ {room.end_date}")
    # 기간만으로는 모델이 **지금이 언제인지 모른다.** 요청에 실려 왔을 때만 넣는다 —
    # 없으면 줄 자체가 빠져 프롬프트가 이 필드 도입 전과 한 글자도 다르지 않다.
    if request.today is not None:
        lines.append(f"- 오늘: {request.today} ({_days_left_phrase(request.today, room.end_date)})")

    # 방의 기존 카테고리는 **아예 받지 않는다** — AI 가 카테고리를 정하지
    # 않기 때문이다. 그 전에도 프롬프트에는 안 넣었다(#21: 목록을 보여주면 거기 맞추려 한다).
    lines.append("\n# 이미 있는 투두 (같은 것을 다시 만들지 마라)")
    lines.extend(f"- {title}" for title in request.existing_todos or ["(없음)"])

    if request.excluded_todos:
        lines.append("\n# 이미 제안했던 후보 (다시 제안하지 마라)")
        lines.extend(f"- {t}" for t in request.excluded_todos)

    lines.append("\n# 아카이브 자료")
    if not request.archive:
        lines.append("- (없음)")
    lines.extend(render_archive_item(item) for item in request.archive)

    return "\n".join(lines)


def render_archive_item(item: ArchiveItemInput) -> str:
    """자료 1건이 프롬프트에서 차지하는 텍스트.

    `build_payload` 에서 뽑아낸 이유는 **예산을 세는 문자열과 실제로 보내는 문자열이 같아야
    하기 때문**이다(`ranking.select_archive`). 둘이 갈리면 예산이 거짓말이 된다 — 렌더를
    고치면서 예산 계산을 같이 안 고치는 것이 정확히 그 사고다.

    ⚠️ **여기서 자르지 않는다.** 한 번 여기에 상한을 넣었다가 되돌렸다(2026-08-02).
    상한을 예산값으로 두니 거대한 자료가 **정확히 예산만큼**이 되어 `select_archive` 의
    `used + cost > budget` 을 통과했고, 그 한 건이 예산을 통째로 먹어 **나머지 17건이
    프롬프트에서 사라졌다** — `select_archive` 가 `break` 를 `continue` 로 바꿔 막아둔
    바로 그 문제를 다른 문으로 되살린 것이다. 자르는 일은 **남은 예산을 아는 쪽**,
    즉 `ranking.select_archive` 의 폴백이 한다.
    """
    parts = [f"\n## id={item.id} · {item.title}"]
    if item.tags:
        parts.append(f"태그: {', '.join(item.tags)}")
    if item.content:
        parts.append(item.content)
    return "\n".join(parts)


def filter_candidates(
    candidates: list[TodoCandidate], request: SuggestionRequest
) -> list[TodoCandidate]:
    """LLM 출력을 그대로 믿지 않는 층.

    프롬프트로 "중복 내지 마라"라고 해도 낸다. 근거 자료 id 도 없는 걸 적을 수 있다.
    사용자에게 나가기 전에 코드로 한 번 더 거른다.
    """
    known = {_normalize(t) for t in request.existing_todos + request.excluded_todos}
    known.discard("")
    valid_ids = {item.id for item in request.archive}

    kept: list[TodoCandidate] = []
    for candidate in candidates:
        title = candidate.title.strip()
        if not title or len(title) > MAX_TITLE_LENGTH:
            continue
        # 자료가 하나도 없는 방이면 근거 id 를 요구할 수 없다(목표만 보고 제안하는 경우).
        if valid_ids and candidate.source_item_id not in valid_ids:
            continue
        normalized = _normalize(title)
        if normalized in known:
            continue
        known.add(normalized)
        kept.append(candidate.model_copy(update={"title": title}))
    return kept


SEMANTIC_DUPLICATE_THRESHOLD = 0.65
"""이 값 이상이면 "같은 할 일"로 보고 버린다.

⚠️ **이 층은 문제를 절반도 해결하지 못한다.** 근거와 한계는 [`docs/EXPERIMENTS.md` #17]에
전부 있고, 값을 바꾸기 전에 그걸 먼저 읽어야 한다. 요지만 옮기면:

**단일 코사인 임계값으로는 짧은 한국어 제목의 중복을 깔끔하게 가를 수 없다.** 라이브 실측
(방 "회화 스터디", 6회차 29개)에서 진짜 중복은 `0.578~0.698`, 비중복은 `0.604`까지 올라와
구간이 겹친다. 같은 도메인의 짧은 제목이라 코사인이 좁은 띠에 몰린다.

0.65 를 고른 기준은 **`오탐 0` 을 지키면서 잡을 수 있는 최대**다. 오탐은 쓸 만한 새 후보를
사용자가 존재조차 모르게 지우고, 미탐은 중복이 한 번 더 보이는 것(= 고치기 전 상태)에
그친다. 게다가 "6~7 번 누르면 후보가 마른다"가 이미 관측돼 있어 과하게
거르면 빈 화면이 더 빨리 온다.

    라이브에서 잡는 것   유튜브 모의고사 0.698 · 서베이 주제 선정 0.693 · PDF 내려받기 0.658
    라이브에서 놓치는 것 스픽 어플 0.647 · 유튜브 채널 0.631 · 문제 두 번 듣기 0.630 ·
                        난이도 6-6 0.605 · 롤플레이 0.578  (전부 진짜 중복)
    비중복 최대          0.604(접수·납부 ↔ 환불·할인) → 여유 0.046

**즉 라이브 중복 8건 중 3건만 잡는다.** 처음 0.70 으로 잡았다가 내렸는데, 그 값에서는
**하나도 잡지 못했다**(최대 관측이 0.698). 더 내리면 0.604 를 건드려 오탐이 시작된다.

바이그램 Jaccard 도 재봤다 — **더 낫지 않고 다른 것을 잡는다**(코사인은 단어가 다른
패러프레이즈, Jaccard 는 글자를 공유하는 재표현). 둘을 합치는 안은 미검증이다(#17).
"""


def drop_semantic_duplicates(
    kept: list[TodoCandidate],
    excluded: list[str],
    embed: Embedder,
    threshold: float,
) -> list[TodoCandidate]:
    """이미 노출한 후보와 **의미가** 겹치는 것을 버린다.

    `filter_candidates` 의 문자열 정규화는 글자가 같은 것만 잡는다. 2026-07-30 실측에서
    `모바일 유튜브 모의고사를 활용해 주제별 답변 구조 연습하기` / `유튜브 모의고사로 주제별
    답변 구조 연습하고 표현 정리하기` 가 서로 다른 것으로 판정돼 3 회차 내내 반복됐다
    (`docs/EXPERIMENTS.md` #17).

    **`embed` 를 주입받는 순수 함수다.** 이 모듈의 다른 순수 함수들과 같은 이유 —
    API 호출을 안에 박으면 크레딧 0 으로 로직을 검증할 수 없게 된다.

    비교 대상은 둘이다.
      1. `excluded`(이전 회차에 노출한 제목)
      2. **이번 회차에서 이미 살린 후보** — 한 회차 안에서도 근접 중복이 나온다

    **`existing_todos`(방의 기존 투두)는 일부러 보지 않는다.** 문자열 층(`filter_candidates`)은
    그것도 같이 보지만, 여기서 보면 방의 투두 전체가 임베딩 입력에 들어가 배치가 무한정 커진다
    (`excluded` 는 개수 상한이 있는데 투두는 없다 — `TodoSuggestionExposureStore.MAX_EXCLUDED`).

    ⚠️ **이 층의 공백이 2026-08-03 에 넓어졌다.** 원래는 "채택된 후보도 노출 기록에 남아
    `excluded` 로 커버된다"고 적혀 있었는데, 그때 상한이 50에서 **16** 으로 줄었다
    (`docs/EXPERIMENTS.md` #24). 이제 채택한 지 두 회차가 지난 투두는 `excluded` 에서 밀려나므로
    **의미만 같고 표현이 다른 후보가 다시 나올 수 있다.** 문자열이 같으면 `filter_candidates` 가
    여전히 잡는다 — 놓치는 것은 **재표현된 중복**뿐이다. 창을 줄이지 않으면 후보가 마르는 쪽이
    훨씬 크게 아팠으므로(후보 8개 → 1~2개) 이 공백을 받아들였다.

    호출을 아끼는 조건은 **비교할 것이 아예 없을 때**다. `excluded` 가 비어도 후보가 2개 이상이면
    서로 비교해야 하므로 호출한다 — 첫 추천에서도 한 회차 안의 근접 중복은 걸러진다.
    아끼는 실체는 크레딧보다 **지연**이다(제목 배치 1회 실측 2.73초).
    """
    if not kept or (not excluded and len(kept) < 2):
        return kept

    titles = [c.title for c in kept]
    vectors = embed(excluded + titles)
    excluded_vectors = vectors[: len(excluded)]
    candidate_vectors = vectors[len(excluded) :]

    survivors: list[TodoCandidate] = []
    survivor_vectors: list[list[float]] = []
    dropped = 0
    for candidate, vector in zip(kept, candidate_vectors, strict=True):
        rivals = excluded_vectors + survivor_vectors
        nearest = max((cosine(vector, other) for other in rivals), default=0.0)
        if nearest >= threshold:
            # 제목은 사용자 콘텐츠라 DEBUG 로 둔다. 이 모듈의 INFO 는 토큰 수만 남긴다.
            log.debug("의미 중복으로 후보 탈락(유사도 %.3f): %s", nearest, candidate.title)
            dropped += 1
            continue
        survivors.append(candidate)
        survivor_vectors.append(vector)
    if dropped:
        log.info("의미 중복으로 후보 %d개 탈락(임계값 %.2f)", dropped, threshold)
    return survivors


def _batching(embed: Embedder, expected: list[str]) -> Embedder:
    """뒤에 올 문자열을 미리 알고 있다가 **첫 호출 때 한 배치로 묶는** 래퍼.

    ⚠️ **원래 이유는 사라졌다** "중복 제거와 카테고리 매칭이 각각 `embed`
    를 부르면 왕복이 2회가 된다"가 근거였는데, 카테고리 매칭을 걷어내 **소비자가 `dedupe`
    하나**가 됐다. 지금 남은 값은 아래 지연 호출(lazy) 성질뿐이다.

    **그래도 안 지웠다** — 지우면 `git revert` 로 카테고리를 되살리는 길이 반쪽이 된다
    (`_match_categories` 가 없는 `state["batched"]` 를 참조하게 된다). 정리는
    `specs/OPEN.md` 후속 항목이고, 되살릴 일이 없다고 확정되면 그때 한다.

    함수 시그니처를 건드리지 않으려고 캐시로 푼다 — `drop_semantic_duplicates` 는 순수 함수로
    테스트가 붙어 있다.

    ## ⚠️ **미리 부르지 않는다(lazy)** — 여기가 두 번 물린 자리다

    처음엔 이 함수가 생성 시점에 `embed(texts)` 를 **바로** 불렀다. 그러면 그 호출이 두 층의
    `try/except` **밖**에서 일어나 **임베딩 게이트웨이가 죽으면 추천 전체가 500 이 된다** —
    LLM 크레딧을 이미 쓴 후보를 통째로 버리고 사용자는 "AI 추천 서버에 연결하지 못했어요" 만 본다.
    그건 2026-07-30 리뷰에서 P1 으로 잡아 고친 동작이고 `embeddings.py` 주석이 그 결정을
    기록해두고 있는데 에서 **조용히 되돌아갔다**(테스트 196개가 못 잡았다).

    같은 이유로 **아무도 안 쓰면 호출이 0회여야 한다.** 두 층 모두 단축 조건이 있어서
    (새 방·첫 추천·후보 1개면 둘 다 건너뛴다) 미리 부르면 **없던 왕복을 새로 만든다.**

    그래서 첫 조회가 올 때 `expected` 를 함께 실어 한 번에 부른다.
    """
    cache: dict[str, list[float]] = {}
    pending = list(dict.fromkeys(expected))

    def cached(requested: list[str]) -> list[list[float]]:
        nonlocal pending
        missing = [t for t in dict.fromkeys(pending + requested) if t not in cache]
        if missing:
            # ⚠️ **`list()` 를 벗기지 말 것.** `dict.update` 는 이터레이터를 **소비하면서**
            # 넣는데 `strict=True` 는 길이 차이를 **끝에 가서야** 던진다. 바로 넘기면 예외
            # 전에 소비된 쌍이 이미 캐시에 남아, 아래 "같은 배치로 재시도"가 거짓이 된다 —
            # 응답이 길면 재시도가 0회가 되고 **버린 벡터를 그대로 쓴다**(2026-08-02 리뷰).
            pairs = list(zip(missing, embed(missing), strict=True))
            cache.update(pairs)
            # 성공한 뒤에만 비운다 — 첫 호출이 실패하면 다음 층이 같은 배치로 한 번 더 시도한다.
            pending = []
        return [cache[t] for t in requested]

    return cached


def _drop_semantic_duplicates_safely(
    kept: list[TodoCandidate], excluded: list[str], embed: Embedder
) -> list[TodoCandidate]:
    """임베딩 호출이 실패해도 추천을 죽이지 않는다.

    후보는 이미 LLM 이 만들어 놨고 사용자가 봐야 한다 — 나중에 붙인 개선 때문에 그 화면의
    본체를 잃는 것은 손해다(AI 태깅·요약 실패 폴백과 같은 방향).

    다만 **`warning` 이 아니라 `error`** 로 남긴다. 이 층이 조용히 죽으면 증상은 "추천은
    되는데 비슷한 후보가 계속 나온다"로 되돌아가고, 그 조용함이 정확히 을
    필요하게 만든 원인이었다.
    """
    try:
        return drop_semantic_duplicates(kept, excluded, embed, SEMANTIC_DUPLICATE_THRESHOLD)
    except Exception as exc:
        log.error(
            "의미 중복 판정 실패(%s) — 문자열 중복 제거 결과를 그대로 반환한다",
            type(exc).__name__,
            exc_info=True,
        )
        return kept


class SuggestState(TypedDict):
    """그래프가 노드 사이로 넘기는 것. **의존성은 읽기 전용, `request` 와 `candidates` 가 흐른다.**

    `request` 가 흐르는 이유는 `select` 노드가 자료를 추려 갈아끼우기 때문이다 — 그래야 뒤의
    `build_payload`·`filter_candidates` 가 **모델이 실제로 본 자료**만 보게 된다.
    """

    request: SuggestionRequest
    llm: BaseChatModel
    embed: Embedder
    candidates: list[TodoCandidate]
    batched: Embedder | None
    """`_batching` 이 만든 임베더. 두 층이 같은 배치를 쓰게 하는 통로다."""

    rejected: list[str]
    """검수가 반려한 후보 — `"제목 → 사유"` 문장. 재생성 프롬프트에 그대로 들어간다.

    **비어 있으면 `_generate` 의 프롬프트가 전환 전과 한 글자도 같아야 한다** 
    1회차가 달라지면 `docs/EXPERIMENTS.md` #26 기준선과의 비교가 통째로 깨진다.
    """

    attempts: int
    """`_generate` 가 몇 번 돌았는가. `config.critique_max_attempts` 와 비교한다."""

    passed: list[TodoCandidate]
    """검수를 통과해 **확정된** 후보의 누적분.

    `candidates` 와 따로 두는 이유는 하나다 — `_generate` 가 매 회차 `candidates` 를 **새
    배치로 덮기 때문**이다. 되돌아왔을 때 앞 회차 통과분이 거기 남아 있으면 검수가 그것까지
    다시 판정하고(중복 비용), 안 남기면 그냥 사라진다. 그래서 누적은 이 키에 두고
    **`_generate` 는 이 키를 절대 건드리지 않는다.**
    """


def _goal_vector(request: SuggestionRequest, embed: Embedder) -> list[float] | None:
    """방 목표를 임베딩한다. **실패해도 예외를 내보내지 않는다.**

    질의로 목표를 쓰는 것은 Spring 쪽 설계와 짝이다 — `ArchiveEmbedder.pickInput` 이 자료를
    본문이 아니라 **요약**으로 임베딩하는 이유가 "질의가 방 목표(짧은 문장)라 긴 본문을 통째로
    넣으면 벡터가 평균화된다"였다. 그래서 여기서도 짧게 목표만 넣는다(방 이름은 라벨에 가까워
    제외).

    `None` 을 돌려주면 유사도 축의 값이 전원 `None` 이 되고, `competition_ranks` 가 전원을
    동점으로 묶어 **그 축이 통째로 조용히 빠진다.** 임베딩 게이트웨이가 죽어도 추천은 나머지
    세 축으로 그대로 나간다 — 임베딩 장애가 추천 장애가 되면 안 된다(2026-07-30 P1 과 같은 규칙).
    """
    goal = " ".join(filter(None, [request.room.goal, request.room.goal_detail])).strip()
    if not goal:
        return None
    try:
        return embed([goal])[0]
    except Exception as exc:
        log.error(
            "방 목표 임베딩 실패(%s) — 유사도 축 없이 순위를 매긴다",
            type(exc).__name__,
            exc_info=True,
        )
        return None


def _select_archive(state: SuggestState) -> dict:
    """프롬프트에 실을 자료의 순서를 정하고 예산 초과분을 버린다.

    ⚠️ **2026-08-09부터 기본 순서는 순위가 아니라 최신순이다**(`archive_select_by_recency`).
    그 모드에서는 유사도 축을 안 쓰므로 **목표 임베딩 왕복이 통째로 빠진다** — 아래 "임베딩
    왕복을 하나 더 만든다" 경고가 기본값에서는 해당하지 않는다.

    **순위 모드에서 목표 임베딩을 건너뛰는 경우가 둘 있다.** 둘 다 결과가 완전히 같아서 왕복만
    아낀다.
      1. 자료가 2건 미만 — 줄 세울 것이 없다. 한 건뿐이면 유사도 축의 `span` 이 0이라
         목표 벡터가 있으나 없으나 순서가 같다.
      2. **자료 중 아무도 벡터가 없을 때** — `V7` 이전 등록분만 있는 방(백필은 기본 꺼짐)이
         그렇다. 유사도 축은 어차피 전원 값 없음으로 빠지므로 목표 벡터를 쓸 데가 없다.

    ⚠️ **건너뛰는 것은 임베딩 왕복뿐이고 `select_archive` 는 항상 태운다.** 원래 자료가 2건
    미만이면 노드 전체를 `return {}` 로 빠져나갔는데, 그러면 **예산이 아예 안 돈다** — 요약이
    없는 거대한 자료 한 건짜리 방에서 프롬프트가 예산의 1.7배가 됐다(2026-08-02 리뷰).
    빠져나가는 것과 태우는 것이 "결과가 같다"는 서술이 거짓이었다.

    ⚠️ **이 노드가 임베딩 왕복을 하나 더 만든다** — 목표 벡터는 LLM 호출 **전에** 필요한데
    뒤의 배치(`_plan_embeddings`)는 후보 제목을 담으므로 LLM **후에**만 만들 수 있다. 합칠 수
    없는 구조다.

    ⚠️ **지연 예산은 이미 최악치 기준으로는 초과 상태다.** `get_llm()` 이 `timeout=120,
    max_retries=1` 이라 LLM 단독 최악이 240초이고, Spring 의 read timeout 은 60초다
    (`AiServerConfig`). 이 노드가 임베딩 최악 20초(10초 x 2회)를 **더해** 합계 최악 300초다
    (LLM 240 + 목표 임베딩 20 + 뒤의 배치 임베딩 40). 게이트웨이가
    죽지 않고 **느리기만 하면** 아래 `try/except` 가 발동하지 않으므로 폴백으로 못 막는다 —
    사용자는 후보 대신 "AI 추천 서버에 연결하지 못했어요"를 본다(`embeddings.py:40` 주석이
    경고한 그 시나리오). 실측 평균은 9.1초라 지금 문제가 되지는 않지만, **"60초 안에 들어온다"고
    말할 수 있는 상태가 아니다.** 제대로 막으려면 유사도 축 전용으로 짧은 데드라인(3~5초,
    재시도 없음)을 주는 것이 맞다 — 이 축은 없어도 추천이 나가므로 포기 비용이 거의 0이다.
    """
    request = state["request"]
    if not request.archive:
        return {}

    settings = get_settings()
    by_recency = settings.archive_select_by_recency

    goal = None
    if (
        not by_recency
        and len(request.archive) >= 2
        and any(item.embedding for item in request.archive)
    ):
        goal = _goal_vector(request, state["embed"])

    selected = select_archive(
        request.archive,
        goal,
        settings.archive_prompt_budget_chars,
        render_archive_item,
        by_recency=by_recency,
    )
    return {"request": request.model_copy(update={"archive": selected})}


def _retry_section(rejected: list[str], passed: list[TodoCandidate]) -> str:
    """재생성일 때만 붙는 절 (통과분은 -237).

    **`rejected` 가 비면 빈 문자열을 돌려준다** — 1회차 프롬프트가 전환 전과 완전히 같아야
    기준선(#26)과 비교가 성립한다. `tests/test_critique.py` 가 그걸 지킨다.

    **`passed` 가 비면 -235 때와 한 글자도 같다.** 전부 반려된 경로가 그렇다 — #28 조건 2 의
    프롬프트가 그대로여야 그 측정이 계속 유효하다.

    ## 통과분을 왜 알려주는가

    부분 반려에서 되돌아갈 때 "이미 낸 것"을 안 알려주면 모델이 회당 8칸을 **1회차 승자로 다시
    채운다.** 그러면 재생성이 허수아비가 된다 — 중복은 뒤의 두 층이 걷어내고 남는 게 없다.

    ⚠️ **이것은 프롬프트 변경이라 [#6] 의 전례가 걸린다.** 루프와 따로 재려 했지만 분리할 수
    없어서(위 이유) 한 조건으로 묶어 쟀다. 그 한계는 `docs/EXPERIMENTS.md` #29 에 적는다.
    """
    if not rejected:
        return ""
    lines: list[str] = []
    if passed:
        lines.append("\n\n# 방금 낸 후보 중 아래는 통과했다. 이것과 겹치지 않는 새 후보를 내라.")
        lines.extend(f"- {c.title}" for c in passed)
        lines.append("\n# 아래는 반려됐다. 같은 이유로 반려될 것을 다시 내지 마라.")
    else:
        lines.append(
            "\n\n# 방금 낸 후보 중 아래는 반려됐다. 같은 이유로 반려될 것을 다시 내지 마라."
        )
    lines.extend(f"- {line}" for line in rejected)
    return "\n".join(lines)


def _generate(state: SuggestState) -> dict:
    """LLM 1회 + 문자열 필터. **파싱 실패는 여기서 502 로 끝난다.**"""
    request = state["request"]
    passed = state.get("passed", [])
    messages = [
        SystemMessage(content=SYSTEM_PROMPT),
        HumanMessage(
            content=build_payload(request) + _retry_section(state.get("rejected", []), passed)
        ),
    ]

    # ChatPromptTemplate 을 쓰지 않는 이유: 프롬프트 안의 `{`/`}` 를 변수 자리로 오해해 깨진다
    # (docs/DECISIONS.md 각주). SystemMessage 객체는 템플릿 처리를 타지 않는다.
    # include_raw=True 라야 토큰 사용량을 볼 수 있고, 파싱 실패도 예외 대신 값으로 돌아온다.
    structured = state["llm"].with_structured_output(SuggestionResponse, include_raw=True)
    result = structured.invoke(messages)

    usage = getattr(result.get("raw"), "usage_metadata", None)
    log.info(
        "todo-suggestions: archive=%d items, tokens=%s",
        len(request.archive),
        usage or "unknown",
    )

    parsed = result.get("parsed")
    if parsed is None:
        log.warning("구조화 출력 파싱 실패: %s", result.get("parsing_error"))
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail="LLM response was not parseable"
        )

    kept = filter_candidates(parsed.candidates, request)
    # 앞 회차에 이미 확정한 것과 글자가 같으면 버린다.
    # `filter_candidates` 의 `known` 은 `existing_todos + excluded_todos` 만 보므로 누적분을
    # 모른다. 의미 중복층이 결국 잡기는 하지만(같은 문자열이면 코사인 1.0) 임베딩 왕복에
    # 기대지 않고 여기서 끝낸다. **1회차는 `passed` 가 비어 지금까지와 한 글자도 같다.**
    if passed:
        already = {_normalize(c.title) for c in passed}
        kept = [c for c in kept if _normalize(c.title) not in already]

    if not kept and passed:
        # 🔴 **되돌아온 회차가 빈손이면 누적분을 되돌려줘야 한다** (2026-08-03 리뷰 P0).
        # 안 그러면 `_has_candidates` 가 곧장 END 로 보내 **앞 회차 통과분까지 사라진다** —
        # 재생성을 안 했으면 3개를 보여줬을 자리에 0개가 나간다. `_accept_whole_batch` 가
        # 고친 것과 같은 유형의 구멍이 한 노드 옆에 남아 있었다.
        log.info("재생성이 새 후보를 못 냈다 — 앞 회차 통과분 %d개를 그대로 내보낸다", len(passed))
        return {"candidates": passed, "attempts": state.get("attempts", 0) + 1}

    return {"candidates": kept, "attempts": state.get("attempts", 0) + 1}


CRITIQUE_INDEX_BASE = 1
"""검수 프롬프트에서 후보에 붙이는 **첫 번호** 

`0` 이면 안 된다. **실측이다** — `evals/probe_critique.py` 로 같은 프롬프트·스키마에
번호만 바꿔 60회를 돌렸다(`data/snapshots/2026-08-03_critique_index_probe.json`).

| 첫 번호 | 판정 개수가 맞은 라운드 |
|---|---|
| `0` | 20/30 — **10회(33%)가 후보 8개에 판정 7개** |
| `1` | **30/30** |

⚠️ **개수만 모자란 것이 아니라 번호가 밀렸다.** 반려 사유를 후보와 대조하면 `0` 에서 밀린
판정이 12건이고 `1` 에서는 **0건**이다. 예: `opic_8` 의 `index=6` 사유가 7번 후보(`시험 40분
동안 12~15개 콤보 …`)를 설명했다. 즉 **개수가 우연히 맞으면 fail-open 이 안 걸리고 엉뚱한
후보가 반려된다** — 아래 `_critique` docstring 이 경고해둔 그 시나리오가 실재한다.
**이 처방이 고친 것은 개수가 아니라 짝이다.**

⚠️ **어느 후보가 판정을 못 받았는지는 모른다. 묶음마다 다르다.** `opic_8` 은 `index=1`·`5`
가 라벨과 정확히 맞고 `6` 부터 밀리는데, `busan_8c` 는 `index=4` 에서 이미 밀렸다. 통과
판정에는 사유가 없어 그 구간은 확정할 수 없다.

⚠️ **"꼬리가 빠진다"고 쓰지 말 것**(2026-08-03 리뷰 P0-1 에서 잡힌 오독). 응답은 항상
`0..n-2` 로 연속이라 **빠진 번호**는 산수로 `n-1` 이 되지만, 그건 번호 라벨이지 후보가
아니다 — `opic_8` 에서 **꼬리 후보는 판정을 받았다**(라벨 6을 달고). 같은 이유로 `OPEN.md`
의 가설("모델이 0번을 빼고 답한다")도 `opic_8` 에서 **반증된다**(`index=1` 이 라벨과 맞으니
0번이 빠진 게 아니다). `busan_8c` 는 그 가설과 모순되지 않지만 확정할 수 없다.

**왜 0-based 일 때만 이러는지는 모른다** — 아는 것은 `1` 부터 매기면 30/30 이고 밀림이
0건이라는 것뿐이다.

⚠️ **묶음마다 결정적이다**(5/5 아니면 0/5). 6개 묶음 중 `busan_8c`·`opic_8` 만 걸렸다.
방과 무관하다 — 부산·오픽 양쪽에서 나왔다. 그래서 방 평가에서 한 방에만 몰려 보였던 것은
그 방의 후보 묶음 탓이고, 다른 방이 안전하다는 뜻이 아니다.

**프롬프트(`CRITIQUE_PROMPT`)와 스키마 설명은 일부러 안 건드렸다** — 위 측정이 그것들을
**그대로 둔 채** 번호만 바꿔서 얻은 값이다. 문구를 함께 고치면 재지 않은 조건을 배포하게 된다
(`ai/CLAUDE.md` 의 [#6] 전례).
"""


def _accept_whole_batch(state: SuggestState) -> dict:
    """검수를 못 믿을 때의 결과 — 이번 배치를 **전부 통과**로 친다.

    ⚠️ **`return {}` 이면 안 된다** 되돌아온 회차에서 `candidates` 는 새
    배치뿐이라, 아무것도 안 쓰고 나가면 **앞 회차 통과분이 조용히 사라진다.** -235 때는
    되돌아오는 경우가 전부 반려뿐(= 누적할 것이 없음)이라 드러나지 않던 구멍이다.
    `tests/test_partial_retry.py::test_the_second_critique_fails_open` 이 잡았다.

    `rejected` 는 비운다 — 통과시켰으니 반려가 없다. 안 비우면 앞 회차의 반려 목록이 남아
    `_should_regenerate` 가 그것을 보고 또 되돌아간다(상한 3 이상에서 발동한다).
    """
    passed = state.get("passed", []) + state["candidates"]
    return {"candidates": passed, "passed": passed, "rejected": []}


def _critique(state: SuggestState) -> dict:
    """후보를 **한 번 더 읽고** 바로 실행할 수 없는 것을 반려한다.

    ## 왜 코드가 아니라 LLM 인가

    이 판단은 코드로 안 된다. `등`·`중`·`잡기` 같은 단어로 세면 반드시 헛걸린다 —
    `국제밀면 등`은 걸려야 하고 `짐 챙기기`는 아닌데 어미·조사로 가를 수 없다
    (`docs/EXPERIMENTS.md` #26 ③에서 실제로 확인했다).

    ## 왜 프롬프트 규칙을 늘리지 않았나

    규칙 하나를 더해 정확도가 14/15 → 10/15 로 후퇴한 전례([#6])와, 프롬프트를 네 가지로
    고쳐도 결과가 전부 0개였던 전례([#21])가 있다. **생성하는 모델에게 "이러지 마라"라고
    말하는 대신, 낸 것을 따로 읽고 판정한다.**

    ## 비용

    후보 **제목만** 보낸다 — 자료·방 정보를 다시 보내지 않는다. 생성 프롬프트가 약 3,000 tok
    인 데 비해 여기는 수백 tok 수준이다.

    ## 실패하면 전부 통과시킨다

    `_drop_semantic_duplicates_safely` 와 같은 정책이다. 검수는 나중에 얹은 층이고, 그것 때문에 화면
    본체를 잃으면 안 된다. **판정 개수가 후보 수와 다를 때도 통째로 버린다** — 인덱스가 한 칸
    밀리면 멀쩡한 후보가 반려되고 나쁜 후보가 통과하는데, 그건 조용해서 알아챌 방법이 없다.
    """
    # 후보가 0이면 여기 오지 않는다 — `_has_candidates` 가 먼저 END 로 보낸다.
    # 예전에 `if not kept: return {}` 가드가 있었는데 도달 불가라 지웠다(2026-08-03 리뷰).
    kept = state["candidates"]
    numbered = "\n".join(f"{i}. {c.title}" for i, c in enumerate(kept, start=CRITIQUE_INDEX_BASE))
    messages = [
        SystemMessage(content=CRITIQUE_PROMPT),
        HumanMessage(content=f"# 후보\n{numbered}"),
    ]

    try:
        structured = state["llm"].with_structured_output(CritiqueResponse)
        verdicts = structured.invoke(messages).verdicts
    except Exception as exc:  # noqa: BLE001 — 검수 고장이 추천 장애가 되면 안 된다
        log.error("후보 검수 실패(%s) — 전부 통과시킨다", type(exc).__name__, exc_info=True)
        return _accept_whole_batch(state)

    if len(verdicts) != len(kept):
        log.error(
            "검수 판정 개수가 안 맞는다(후보 %d개, 판정 %d개) — 전부 통과시킨다",
            len(kept),
            len(verdicts),
        )
        return _accept_whole_batch(state)

    by_index = {v.index: v for v in verdicts}
    if set(by_index) != set(range(CRITIQUE_INDEX_BASE, CRITIQUE_INDEX_BASE + len(kept))):
        log.error("검수 판정의 번호가 후보와 안 맞는다(%s) — 전부 통과시킨다", sorted(by_index))
        return _accept_whole_batch(state)

    numbered_kept = list(enumerate(kept, start=CRITIQUE_INDEX_BASE))
    newly_passed = [c for i, c in numbered_kept if by_index[i].ok]
    rejected = [
        f"{c.title} → {by_index[i].reason or '바로 실행할 수 없다'}"
        for i, c in numbered_kept
        if not by_index[i].ok
    ]
    log.info("후보 검수: %d개 중 %d개 통과", len(kept), len(newly_passed))
    # 앞 회차 통과분에 **더한다** 되돌아온 회차에서 `kept` 는 새 배치뿐이라
    # 여기서 누적하지 않으면 1회차 승자가 그대로 사라진다.
    passed = state.get("passed", []) + newly_passed
    # `rejected` 는 **덮어쓴다**(누적 아님). 재생성이 최대 1회뿐이라(기본 설정) 누적과 덮어쓰기의
    # 차이가 드러나지 않는다 — `critique_max_attempts >= 3` 에서만 갈리고, 그 조건을 재본 적이
    # 없어 어느 쪽이 나은지 **모른다.** 테스트도 못 건다(2026-08-03 리뷰에서 변이가 살아남았다).
    return {"candidates": passed, "passed": passed, "rejected": rejected}


def _should_regenerate(state: SuggestState) -> str:
    """검수 뒤 갈림길 — **이 그래프의 두 번째 진짜 분기다**

    하나도 통과하지 못하면 다시 만들고, 시도가 소진되면 **빈 목록으로 끝낸다**
    (2026-08-03 사용자 확정 — 나쁜 후보를 보여주느니 안 보여준다).

    ## 부분 반려에도 되돌아간다 (`regenerate_on_partial_reject`)

    -235 는 "전부 반려"일 때만 돌아왔는데 그 상황이 거의 없어 **루프가 사실상 안 탔다.**
    흔한 것은 "3개 통과 · 4개 반려"이고 그 4개가 아무것도 남기지 않는 것이 후보가 88 → 41개로
    준 주된 원인이다(`docs/EXPERIMENTS.md` #28 ⑤).

    ⚠️ **스위치가 꺼져 있으면 아래 분기는 -235 와 완전히 같다.** 그 동일성이 #28 기준선을
    재사용하는 근거이므로 `tests/test_partial_retry.py` 가 양쪽 경로를 다 고정한다.
    """
    settings = get_settings()
    exhausted = state.get("attempts", 0) >= settings.critique_max_attempts

    if state["candidates"]:
        if not exhausted and settings.regenerate_on_partial_reject and state["rejected"]:
            log.info("부분 반려 %d건 — 반려분만큼 다시 생성한다", len(state["rejected"]))
            return "generate"
        return "batch"
    if not exhausted:
        return "generate"
    log.info("검수를 통과한 후보가 없고 시도가 소진됐다 — 빈 목록을 반환한다")
    return END


def _plan_embeddings(state: SuggestState) -> dict:
    """뒤의 두 층이 쓸 문자열을 모아 **한 배치로 묶을 임베더**를 만든다.

    **여기서 네트워크를 부르지 않는다.** 실제 호출은 두 층의 `try/except` 안에서 일어나야
    폴백이 산다 — 자세한 이유는 `_batching` docstring.
    """
    request, kept = state["request"], state["candidates"]
    texts = request.excluded_todos + [c.title for c in kept]
    return {"batched": _batching(state["embed"], texts)}


def _dedupe(state: SuggestState) -> dict:
    return {
        "candidates": _drop_semantic_duplicates_safely(
            state["candidates"], state["request"].excluded_todos, state["batched"]
        )
    }


def _has_candidates(state: SuggestState) -> str:
    """생성 뒤 갈림길.

    후보가 하나도 없으면 남은 노드를 건너뛴다. `excluded_todos` 가 쌓이면 회차 후반에 후보가
    전부 걸러지는 일이 실제로 있다("후보가 마른다").

    **후보가 0일 때 재생성하지 않는 것이 의도다** — 반려 사유가 없으니
    같은 프롬프트를 한 번 더 던지는 것뿐이고, 그건 동전 던지기지 개선이 아니다.

    `dedupe` 는 이제 마지막 노드라 뒤에 분기를 둘 자리가 없다. 카테고리 매칭이 있던 시절에도
    거기 분기를 **일부러 안 뒀는데**, 후보가 0이어도 아끼는 것이 함수 호출 하나뿐인데 조건부
    엣지를 하나 더 두면 "여기서 뭔가 갈린다"고 읽히기만 하기 때문이었다(리뷰 지적).
    """
    if not state["candidates"]:
        return END
    # `0` 이면 검수 노드를 아예 안 탄다 — 전환 전과 완전히 같은 경로다.
    if not get_settings().critique_max_attempts:
        return "batch"
    # 되돌아온 회차가 빈손이라 `_generate` 가 누적분을 되돌려준 경우.
    # **이미 검수를 통과한 것들이라 다시 판정하지 않는다** — 판정하면 왕복이 한 번 더 들고,
    # 같은 후보가 이번엔 반려될 수도 있다. 1회차에는 `passed` 가 비어 있어 여기 안 걸린다.
    if state["candidates"] == state.get("passed", []):
        return "batch"
    return "critique"


def _timed(name: str) -> Callable:
    """노드 소요를 INFO 로 남긴다 (2026-08-09).

    ⚠️ **임시 디버깅이 아니라 영구 관측성이다 — 지우지 말 것.** 운영에서 추천이 26~28초였는데
    평가 러너가 기록한 라운드는 5.3~6.8초(`docs/EXPERIMENTS.md` #28)라 **약 20초의 행방을
    몰랐다.** 어느 노드가 먹는지 모르면 추측으로 고치게 되고, 그러면 효과 없는 변경에 하루가
    간다.

    노드 함수 자체는 안 건드린다 — `_build_graph` 에서만 감싼다. 테스트가 `_select_archive`
    같은 함수를 직접 부르는데(예: `test_suggest_graph`), 함수에 데코레이터를 달면 그쪽 로그까지
    오염되고 실패 경로가 달라진다.

    `finally` 로 재는 이유는 **예외가 나도 걸린 시간을 남기기 위해서다.** 게이트웨이가 죽지 않고
    느리기만 한 시나리오(`_select_archive` docstring 경고)가 정확히 그 경우다.
    """

    def wrap(node: Callable) -> Callable:
        @functools.wraps(node)
        def run(state):
            started = time.perf_counter()
            try:
                return node(state)
            finally:
                log.info("노드 %s: %.2f초", name, time.perf_counter() - started)

        return run

    return wrap


def _build_graph(prepare=None):
    """추천 파이프라인 그래프. **모듈 로드 때 한 번만 컴파일한다.**

    `prepare` 는 **LangGraph Studio 전용**이다(`modi_ai/studio.py`). 운영은 항상 `None` 이고,
    배선을 여기 한 군데에만 두려고 인자로 받는다 — Studio 쪽에서 엣지를 다시 선언하면
    그림과 실제 파이프라인이 조용히 갈린다.

    ## 왜 LangGraph 인가 — 솔직한 기록

    오늘 이 그래프가 주는 **기능 이득은 0 이다.** 직선 파이프라인을 노드로 나눈 것뿐이고,
    `langchain-core` 채택 때와 **같은 근거**(팀 역량·포트폴리오)로 사용자가 결정했다
    (`docs/DECISIONS.md`). 그 판단을 감추지 않으려고 여기 적는다.

    다만 `ai/CLAUDE.md` 가 금지 근거로 삼던 **"LLM 호출 1회 구조"는 이미 사실이 아니다** —
    이후 외부 호출이 2회(LLM + 임베딩)이고, 폴백도 둘(파싱 실패 → 502,
    임베딩 실패 → 그대로 통과) 있다. 같은 문서가 적어둔 재검토 조건에 닿아 있었다.
    **2026-08-02 정정: 지금은 3회다** 의 `select` 노드가 방 목표
    임베딩을 LLM **앞에서** 한 번 더 부른다(합칠 수 없는 이유는 `_select_archive` 참고).

    ## 이 그래프가 **표현하지 않는 것**

    폴백 둘은 여전히 `_..._safely` 안의 `try/except` 다. 엣지로 옮기지 않은 이유는 성공·실패가
    **같은 다음 노드로 가기 때문**이다 — 조건부 엣지로 쓰면 분기처럼 보이지만 실제로는 갈리는
    곳이 없어 그림만 복잡해진다.

    ## 2026-08-03 — 되돌아가는 엣지가 생겼다. **그래도 기능 이득은 0 이다**

    `critique → generate` 엣지가 생겼고 진짜 분기가 둘이 됐다(`_has_candidates` 생성 뒤 ·
    `_should_regenerate` 검수 뒤).

    ⚠️ **초안에 "이제는 기능 이득이 있다"라고 적었다가 지운다**(2026-08-03).
    거짓이었다 — **그 엣지는 운영에서 안 탄다.** "후보가 전부 반려"일 때만 도는데 그게 거의
    안 일어난다. 같은 날 `ai/CLAUDE.md` 는 이미 "①은 재보고 껐다"라고 적어뒀는데 이 docstring 만
    반대로 남아 있었다. 두 문서가 서로 다른 말을 하고 있었다.

    -237 이 그 엣지를 **부분 반려에도 타게** 만들어봤다. 후보는 회복됐지만 지연이 상한을
    37~40% 깨서 **기각했다**(`docs/EXPERIMENTS.md` #29). 즉 지금도 이 루프는 기본 설정에서
    돌지 않는다.

    **그래서 발표·문서에서 "LangGraph 덕분에 좋아졌다"고 말하면 안 된다.** 품질을 올린 것은
    검수라는 아이디어이고, 그건 직선 코드로도 된다. 사실은 "루프를 두 번 만들고, 두 번 재보고,
    데이터가 아니라고 해서 둘 다 껐다"이며 그쪽이 더 나은 이야기다.

    ## 계약은 여전히 한 글자도 안 바뀌었다

    `suggest()` 의 입력·출력·예외·로그가 그대로다. `critique_max_attempts=0` 이면 경로까지
    전환 전과 완전히 같다.
    """
    graph = StateGraph(SuggestState)
    graph.add_node("select", _timed("select")(_select_archive))
    graph.add_node("generate", _timed("generate")(_generate))
    graph.add_node("critique", _timed("critique")(_critique))
    graph.add_node("batch", _timed("batch")(_plan_embeddings))
    graph.add_node("dedupe", _timed("dedupe")(_dedupe))

    if prepare is None:
        graph.add_edge(START, "select")
    else:
        # LangGraph Studio 전용 진입점. **운영 경로에는 없다** — `SUGGEST_GRAPH` 는
        # `prepare=None` 으로 만든다. 자세한 이유는 `modi_ai/studio.py`.
        graph.add_node("prepare", prepare)
        graph.add_edge(START, "prepare")
        graph.add_edge("prepare", "select")

    graph.add_edge("select", "generate")
    graph.add_conditional_edges(
        "generate", _has_candidates, {"critique": "critique", "batch": "batch", END: END}
    )
    graph.add_conditional_edges(
        "critique", _should_regenerate, {"batch": "batch", "generate": "generate", END: END}
    )
    graph.add_edge("batch", "dedupe")
    graph.add_edge("dedupe", END)
    return graph.compile()


SUGGEST_GRAPH = _build_graph()


def suggest(request: SuggestionRequest, llm: BaseChatModel, embed: Embedder) -> SuggestionResponse:
    """추천 1회. 그래프를 돌리고 후보만 꺼낸다 — **호출부 계약은 전환 전과 같다.**

    ⚠️ 예전에는 중복 제거 **뒤에** 카테고리 매칭이 붙어 있었다. 그 층은 에서
    걷어냈다 — `docs/RESTORE-category-assignment.md`. 지금 마지막 노드는 `dedupe` 다.
    """
    started = time.perf_counter()
    final = SUGGEST_GRAPH.invoke(
        SuggestState(
            request=request,
            llm=llm,
            embed=embed,
            candidates=[],
            batched=None,
            rejected=[],
            attempts=0,
            passed=[],
        )
    )
    # 노드 합계와 이 값의 차이가 그래프 바깥 오버헤드다. 둘 다 찍어야 "어디에도 없는 시간"을
    # 발견할 수 있다 — 노드만 재면 합계가 전체와 같다고 착각한다(`_timed` 참고).
    log.info(
        "추천 그래프 전체: %.2f초 (자료 %d건 · 후보 %d개)",
        time.perf_counter() - started,
        len(request.archive),
        len(final["candidates"]),
    )
    return SuggestionResponse(candidates=final["candidates"])
