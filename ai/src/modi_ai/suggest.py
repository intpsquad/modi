"""투두 추천 파이프라인 — **LLM 호출 1회**다(2026-10-18, #109).

    자료 고르기(최신순 + 글자 예산, 네트워크 없음) → LLM 1회 → 문자열 필터

순수 함수(`build_payload`/`filter_candidates`)와 LLM 호출을 갈라놓아 크레딧 0으로 로직 전체를
테스트한다.

🔴 **2026-10-18 에 LangGraph 그래프와 그 위의 층들을 걷어냈다**(사용자 확정, #109). 남았던 것은
노드 그래프·꺼져 있던 검수(critique)·재생성 루프·임베딩으로 같은 묶음 안의 비슷한 후보를 거르던
층이다. 검수는 2026-08-14 부터 꺼져 있었고, "이미 제안했던 후보 거르기"(`excluded_todos`)는
Spring 이 2026-08-09 부터 빈 목록을 보낸다 — 그래서 운영에서 실제로 돌던 것은 LLM 1회 + 임베딩
1회였다. 임베딩 층까지 빼서 외부 호출이 LLM 1회뿐이다. 왜 지웠는지·무엇을 잃었는지는
`docs/DECISIONS.md`.

프롬프트에 들어가는 자료 텍스트는 `ArchiveItemInput.content` 하나뿐이고, 그게 요약인지 본문인지는
**Spring이 이미 골라서 보낸다**(요약·본문 중 짧은 쪽). 이 서버는 구분하지 않는다 — 선택 규칙이
양쪽에 흩어지면 어느 쪽이 이겼는지 추적이 안 되기 때문이다. 근거는 `docs/DECISIONS.md`
(`V5` 마이그레이션).

자료는 **정렬해서** 넣고(기본 최신순), 누적 길이가 예산을 넘을 때만 뒤쪽을 버린다. 개수 상한은
없다 — 근거 없는 숫자를 박지 않으려는 것이고, 예산은 튜닝값이 아니라 안전밸브다
(`config.archive_prompt_budget_chars`).
"""

import logging
import time
from datetime import date

from fastapi import HTTPException, status
from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI

from modi_ai.config import get_settings
from modi_ai.prompts import SYSTEM_PROMPT
from modi_ai.ranking import select_archive
from modi_ai.schemas import (
    MAX_TITLE_LENGTH,
    ArchiveItemInput,
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

    의미가 같고 표현만 다른 것은 못 잡는다. 그걸 잡던 임베딩 층(`drop_semantic_duplicates`)은
    2026-10-18 에 걷어냈다(#109) — 같은 묶음에 비슷한 후보 둘이 가끔 같이 나올 수 있다.
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


def _select_archive(request: SuggestionRequest) -> SuggestionRequest:
    """프롬프트에 실을 자료의 순서를 정하고 예산 초과분을 버린다. **네트워크를 부르지 않는다.**

    기본은 최신순이다(`archive_select_by_recency`, 2026-08-09). 순위 모드로 바꿔도 방 목표 임베딩을
    부르지 않으므로 유사도 축은 빠지고 나머지 축(핀·좋아요·최신)으로 줄 세운다 — 목표 임베딩
    왕복은 #109 에서 임베딩 층과 함께 걷어냈다.

    ⚠️ **자료가 1건이어도 `select_archive` 는 태운다.** 예전에 2건 미만이면 건너뛰었더니 요약
    없는 거대한 자료 한 건짜리 방에서 프롬프트가 예산의 1.7배가 됐다(2026-08-02 리뷰).

    갈아끼운 `request` 를 돌려주는 이유: 뒤의 `build_payload`·`filter_candidates` 가 **모델이
    실제로 본 자료**만 보게 하려는 것이다(예산에서 잘린 자료의 id 를 근거로 대면 버린다).
    """
    if not request.archive:
        return request
    settings = get_settings()
    selected = select_archive(
        request.archive,
        None,
        settings.archive_prompt_budget_chars,
        render_archive_item,
        by_recency=settings.archive_select_by_recency,
    )
    return request.model_copy(update={"archive": selected})


def _generate(request: SuggestionRequest, llm: BaseChatModel) -> list[TodoCandidate]:
    """LLM 1회 + 문자열 필터. **파싱 실패는 여기서 502 로 끝난다.**"""
    messages = [
        SystemMessage(content=SYSTEM_PROMPT),
        HumanMessage(content=build_payload(request)),
    ]

    # ChatPromptTemplate 을 쓰지 않는 이유: 프롬프트 안의 `{`/`}` 를 변수 자리로 오해해 깨진다
    # (docs/DECISIONS.md 각주). SystemMessage 객체는 템플릿 처리를 타지 않는다.
    # include_raw=True 라야 토큰 사용량을 볼 수 있고, 파싱 실패도 예외 대신 값으로 돌아온다.
    structured = llm.with_structured_output(SuggestionResponse, include_raw=True)
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
    return filter_candidates(parsed.candidates, request)


def suggest(request: SuggestionRequest, llm: BaseChatModel) -> SuggestionResponse:
    """추천 1회 — 자료 고르기 → LLM 1회 → 문자열 필터. **입력·출력 계약은 그래프 시절과 같다.**

    소요 로그는 지우지 말 것(2026-08-09 에 "운영 26~28초 중 약 20초의 행방을 몰랐다"가 남긴 영구
    관측성). 이제 단계가 하나라 LLM 시간이 거의 전부다.
    """
    started = time.perf_counter()
    selected = _select_archive(request)
    candidates = _generate(selected, llm)
    # 자료는 "받은 것 / 프롬프트에 실린 것" 둘 다 남긴다 — 예산(3,000자)이 상시 걸려서 그 차이가
    # 추천 근거에서 빠진 자료의 양이다(토큰 로그는 실린 쪽만 센다).
    log.info(
        "투두 추천: %.2f초 (자료 %d/%d건 · 후보 %d개)",
        time.perf_counter() - started,
        len(selected.archive),
        len(request.archive),
        len(candidates),
    )
    return SuggestionResponse(candidates=candidates)
