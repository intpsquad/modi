"""추천 러너 — **실제 LLM 을 호출한다(크레딧 소모).**

케이스마다 자료 1건씩 넣어 독립 호출한다. 자료를 한꺼번에 넣으면 어느 자료가 어떤 후보를
낳았는지 귀속이 흐려진다.

**지금 이 러너는 채점하지 않는다.** 자동 채점을 먼저 만들었다가 지표 셋이 전부 무효로 판명된
전례가 있다(`docs/EXPERIMENTS.md` "다시 하지 말 것"). 순서를 바꿨다 —
**출력을 눈으로 보고 무엇이 실제로 문제인지 찾은 뒤에 지표를 정의한다.**

지금 주는 것: 후보 전문 · 토큰량 · 응답 시간 · `source_item_id` 위반으로 걸러진 개수 ·
제목 길이 분포.

## 입력 — 기본은 **요약**이다 (2026-08-01 변경)

운영에서 추천 프롬프트에 들어가는 자료 텍스트는 요약이다(`V5` — Spring 이
요약·본문 중 짧은 쪽을 고른다). 이 러너는 오래 **원문 캡션**을 넣어서 운영과 다른 입력으로
재고 있었다. 지금은 `--input summary`(기본)가 `data/summaries/` 의 동결 요약을 읽는다.
`--input body` 는 [#13](../docs/EXPERIMENTS.md) 기준선을 재현할 때만 쓴다.

> 그전까지 이 자리에는 **"입력이 곧 바뀐다 — 그 전에 프롬프트를 튜닝하지 말 것"** 이 붙어 있었다.
> 그 조건은 해소됐다. 다만 프롬프트를 고치려면 **먼저 재고 근거를 남긴다**(`ai/CLAUDE.md`).

    uv run python -m evals.summarize_fixtures               # 선행: 요약 동결 (호출 15회)
    uv run python -m evals.run_suggest_eval                 # 자료 15개 (호출 15회)
    uv run python -m evals.run_suggest_eval --limit 3       # 크레딧 아끼며 확인
    uv run python -m evals.run_suggest_eval --input body    # #13 기준선 재현

CI 에서 돌지 않는다(`pyproject.toml` 의 `testpaths` 밖) — 크레딧을 쓰기 때문이다.
순수 로직(`summarize`/`build_request`/`run_name`)은 `tests/test_runner.py` 가
크레딧 0 으로 잰다.
"""

import argparse
import json
import logging
import statistics
import time
from dataclasses import dataclass, field
from pathlib import Path

from evals.dataset import EvalCase, load_cases
from evals.summarize_fixtures import load_summary
from modi_ai.config import get_settings
from modi_ai.prompts import SYSTEM_PROMPT
from modi_ai.schemas import (
    ArchiveItemInput,
    RoomInput,
    SuggestionRequest,
    SuggestionResponse,
    TodoCandidate,
)
from modi_ai.suggest import (
    build_payload,
    filter_candidates,
    get_llm,
)
from modi_ai.tracing import configure_tracing

log = logging.getLogger(__name__)

OUTPUT_PATH = Path(__file__).parent / "data" / "suggest_eval_export.json"

# 방 정보를 하나로 고정한다 — 케이스마다 달라지면 차이가 자료 때문인지 방 때문인지 갈리지 않는다.
FIXED_ROOM = RoomInput(
    name="평가용 방",
    goal="아카이브에 담은 자료를 실제 행동으로 옮기기",
    goal_detail=None,
    start_date="2026-08-01",
    end_date="2026-08-31",
)

# 제목이 "간결한가" 를 가르는 선. [#13](../docs/EXPERIMENTS.md) 이 요약 도입 후 쓰기로 한 세 지표
# 중 **문자열 속성 하나**다(나머지 둘 — 지역명 중복·어미 일관성 — 은 눈으로 본다).
# 20 은 #13 이 관측한 중간값 22.5 자에서 온 관측 기준선이지 합격선이 아니다.
CONCISE_TITLE_LENGTH = 20


# 러너에서만 샘플링을 고정한다. 운영 `get_llm()` 은 건드리지 않는다 — 차이가 프롬프트 때문인지
# 샘플링 잡음인지 갈라야 하기 때문이다. 값을 고정해도 분산이 0 이 되는 것은 아니므로, 델타를
# 근거로 쓸 때는 같은 설정 반복 실행으로 잡음 범위를 먼저 재야 한다.
EVAL_TEMPERATURE = 0.0


@dataclass
class CaseResult:
    stem: str
    candidates: list[TodoCandidate] = field(default_factory=list)
    raw_candidate_count: int = 0
    """필터 **전** 개수."""

    dropped_by_filter: int = 0

    prompt_tokens: int = 0
    completion_tokens: int = 0
    seconds: float = 0.0
    error: str | None = None


def resolve_content(case: EvalCase, input_mode: str) -> str:
    """자료 텍스트. `summary` 면 동결 요약, `body` 면 원문 캡션.

    요약 파일이 없으면 `load_summary` 가 **죽는다** — 조용히 원문으로 폴백하면 리포트에는
    "요약으로 쟀다" 가 남는데 실제로는 아니게 된다.
    """
    if input_mode == "body":
        return case.text
    return load_summary(case.stem)


def build_request(
    case: EvalCase,
    *,
    content: str | None = None,
) -> SuggestionRequest:
    """`content` 를 주지 않으면 원문 캡션이 들어간다 — 옛 호출부와 테스트의 기본값이다."""
    return SuggestionRequest(
        room=FIXED_ROOM,
        existing_todos=[],
        excluded_todos=[],
        archive=[
            ArchiveItemInput(
                id=1, title=case.title, content=case.text if content is None else content, tags=[]
            )
        ],
    )


def run_case(
    case: EvalCase,
    llm,
    system_prompt: str,
    *,
    content: str | None = None,
    schema=None,
) -> CaseResult:
    from langchain_core.messages import HumanMessage, SystemMessage

    from modi_ai.schemas import SuggestionResponse

    result = CaseResult(stem=case.stem)
    request = build_request(case, content=content)

    # `suggest()` 를 그대로 부르지 않는 이유: 프롬프트를 갈아끼워야 하고, 필터가 몇 개를
    # 버렸는지 세야 하며, 한 케이스가 죽어도 나머지를 계속 돌려야 한다.
    # 프롬프트 조립·필터는 운영과 **같은 함수**를 쓴다.
    messages = [SystemMessage(content=system_prompt), HumanMessage(content=build_payload(request))]
    structured = llm.with_structured_output(schema or SuggestionResponse, include_raw=True)

    started = time.perf_counter()
    try:
        raw_result = structured.invoke(messages)
    except Exception as exc:  # noqa: BLE001 — 한 케이스 실패로 전체를 버리지 않는다
        result.error = f"{type(exc).__name__}: {exc}"
        result.seconds = round(time.perf_counter() - started, 2)
        return result
    result.seconds = round(time.perf_counter() - started, 2)

    usage = getattr(raw_result.get("raw"), "usage_metadata", None) or {}
    result.prompt_tokens = usage.get("input_tokens", 0)
    result.completion_tokens = usage.get("output_tokens", 0)

    parsed = raw_result.get("parsed")
    if parsed is None:
        result.error = f"parsing_error: {raw_result.get('parsing_error')}"
        return result

    kept = filter_candidates(parsed.candidates, request)
    # ⚠️ **이 줄이 본체다.** 러너가 존재하는 이유가 후보 전문이고, 제목 길이 분포도 여기서
    # 나온다. 에서 카테고리 블록을 잘라내며 **같이 지웠다가 리뷰에서 잡혔다** —
    # `kept` 가 아래 `len()` 에 여전히 쓰여 린트도 안 걸렸고, `run_case` 에 테스트가 없어
    # 417개 초록인 채로 모든 케이스가 후보 0개를 보고했다.
    result.candidates = kept
    result.raw_candidate_count = len(parsed.candidates)
    result.dropped_by_filter = len(parsed.candidates) - len(kept)
    return result


def title_length_stats(results: list[CaseResult]) -> dict:
    """후보 제목 길이 분포. **채점이 아니라 관측이다** — 합격선을 두지 않는다.

    [#13](../docs/EXPERIMENTS.md) 이 "요약 도입 후 지표로 쓴다" 고 명시한 셋 중 라벨 없이 잴 수
    있는 하나다(나머지 둘은 눈으로 본다). 그때 본문 입력 기준선은 중간값 22.5 · 최대 40 ·
    50개 중 30개가 20자 초과였다.
    """
    lengths = sorted(len(c.title) for r in results for c in r.candidates)
    if not lengths:
        return {"min": 0, "median": 0, "max": 0, f"over_{CONCISE_TITLE_LENGTH}": 0}
    return {
        "min": lengths[0],
        "median": round(statistics.median(lengths), 1),
        "max": lengths[-1],
        f"over_{CONCISE_TITLE_LENGTH}": sum(1 for n in lengths if n > CONCISE_TITLE_LENGTH),
    }


def summarize(results: list[CaseResult]) -> dict:
    """비용·형식 관측만 한다. **품질 지표는 아직 없다** — 위 모듈 docstring 참고."""
    return {
        "cases": len(results),
        "candidates": sum(len(r.candidates) for r in results),
        "dropped_by_filter": sum(r.dropped_by_filter for r in results),
        "title_length": title_length_stats(results),
        "prompt_tokens": sum(r.prompt_tokens for r in results),
        "completion_tokens": sum(r.completion_tokens for r in results),
        "seconds": round(sum(r.seconds for r in results), 1),
        "errors": sum(1 for r in results if r.error),
    }


def print_report(results: list[CaseResult], summary: dict) -> None:
    for r in results:
        print(f"\n=== {r.stem} ===")
        if r.error:
            print(f"  ERROR {r.error}")
            continue
        print(f"  {r.seconds:.1f}초 · prompt {r.prompt_tokens:,} tok · 후보 {len(r.candidates)}개")
        for c in r.candidates:
            print(f"    {c.title}")
        if r.dropped_by_filter:
            print(f"    (필터로 {r.dropped_by_filter}개 탈락 — source_item_id 위반·중복)")

    print("\n" + "-" * 70)
    print(
        f"자료 {summary['cases']}건 · 후보 {summary['candidates']}개 · 오류 {summary['errors']}건"
    )
    print(f"필터 탈락 {summary['dropped_by_filter']}개")
    lengths = summary["title_length"]
    print(
        f"제목 길이 최소 {lengths['min']} / 중간값 {lengths['median']} / 최대 {lengths['max']}"
        f" · {CONCISE_TITLE_LENGTH}자 초과 {lengths[f'over_{CONCISE_TITLE_LENGTH}']}개"
    )
    print(
        f"토큰 prompt {summary['prompt_tokens']:,} / completion {summary['completion_tokens']:,}"
        f" · {summary['seconds']}초"
    )
    print("제목 길이는 관측이지 합격선이 아니다 — 나머지는 출력을 눈으로 본다.")


def run_name(
    model: str,
    *,
    input_mode: str,
) -> str:
    """`export` 의 키. **조건이 다르면 반드시 달라야 한다.**

    예전에는 `f"{model}{'-norule4'}"` 뿐이라 입력 모드나 카테고리만 바꿔 돌리면 **앞 실행을
    조용히 덮어썼다** — A/B 두 짝 중 하나가 사라지는데 파일만 봐서는 알 수 없다.

    ⚠️ **축이 둘로 줄었다** 카테고리·규칙4·스키마힌트 축이 사라져서 이 함수는
    이제 `norule4`/`noschemahint`/`nocat` 이 붙은 **옛 이름을 만들 수 없다.** 그 이름으로 얼린
    스냅샷 8개는 파일로 남아 있고 `tests/test_snapshot_2026_08_01.py` 가 그대로 읽는다 —
    다시 만들 일이 없으므로 문제가 되지 않는다.
    """
    parts = [model, input_mode]
    return "_".join(parts)


def main() -> None:
    parser = argparse.ArgumentParser(description="추천 러너 (실제 LLM 호출)")
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        # `if args.limit:` 로 쓰면 0 이 falsy 라 15건 전부 돈다 — 크레딧 절약이 존재 이유인
        # 플래그에서 정확히 반대로 작동한다. 음수도 조용히 뒤에서 잘린다. 그래서 검증한다.
        help="앞에서 N개만 (크레딧 절약). 1 이상이어야 한다",
    )
    # 옛 이름. 이미 얼린 스냅샷을 낸 명령이라 문서·기록에 남아 있다 — 죽이지 않고 매핑한다.
    parser.add_argument(
        "--input",
        choices=("summary", "body"),
        default="summary",
        help="자료 텍스트로 무엇을 넣을지. summary(기본)=운영과 같은 조건, body=#13 기준선 재현",
    )
    parser.add_argument("--label", default=None, help="export 파일에 남길 실행 이름")
    args = parser.parse_args()

    logging.basicConfig(level=logging.WARNING, format="%(levelname)s:%(name)s:%(message)s")
    configure_tracing(get_settings())

    # 호출 **전에** 만든다 — 형식이 어긋나면 크레딧을 쓰기 전에 죽는다.
    system_prompt = SYSTEM_PROMPT
    schema = SuggestionResponse

    if args.limit is not None and args.limit < 1:
        raise SystemExit(f"--limit 은 1 이상이어야 한다(받은 값: {args.limit})")
    cases = load_cases()
    if args.limit is not None:
        cases = cases[: args.limit]

    # 요약도 호출 **전에** 전부 읽는다 — 12번째에서 파일이 없어 죽으면 앞 11건의 크레딧이 날아간다.
    contents = [resolve_content(case, args.input) for case in cases]

    model = get_settings().openai_model
    # export 도 호출 **전에** 읽는다. 다 쓴 뒤에 읽다가 파일이 손상돼 있으면 크레딧이 날아간다.
    export = json.loads(OUTPUT_PATH.read_text(encoding="utf-8")) if OUTPUT_PATH.exists() else {}
    name = args.label or run_name(
        model,
        input_mode=args.input,
    )
    if name in export:
        print(f"주의: export 의 기존 실행 '{name}' 을 덮어쓴다")

    print(
        f"자료 {len(cases)}건 · 모델 {model} · 입력 {args.input} · temperature {EVAL_TEMPERATURE}"
    )

    llm = get_llm().bind(temperature=EVAL_TEMPERATURE)
    # 임베딩을 쓰는 층이 이 러너에는 없다(카테고리 매칭이 걷혔다).
    embedder = None
    results: list[CaseResult] = []
    try:
        for case, content in zip(cases, contents, strict=True):
            results.append(
                run_case(
                    case,
                    llm,
                    system_prompt,
                    content=content,
                    schema=schema,
                    embed=embedder,
                )
            )
    except KeyboardInterrupt:
        # 유료 호출을 이미 태웠으므로 지금까지 받은 것은 저장한다. 러너가 export 를 호출
        # **전에** 읽는 것과 같은 이유다 — 크레딧을 쓴 뒤 결과를 잃는 경로를 만들지 않는다.
        print(f"\n중단됨 — {len(results)}건까지 저장한다")
    summary = summarize(results)
    print_report(results, summary)

    export[name] = {
        "model": model,
        "input": args.input,
        "temperature": EVAL_TEMPERATURE,
        "summary": summary,
        "cases": [
            {
                "stem": r.stem,
                "candidates": [c.model_dump() for c in r.candidates],
                "raw_candidate_count": r.raw_candidate_count,
                "dropped_by_filter": r.dropped_by_filter,
                "prompt_tokens": r.prompt_tokens,
                "seconds": r.seconds,
                "error": r.error,
            }
            for r in results
        ],
    }
    OUTPUT_PATH.write_text(json.dumps(export, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n결과 저장: {OUTPUT_PATH} (run={name})")


if __name__ == "__main__":
    main()
