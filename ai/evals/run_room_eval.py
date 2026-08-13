"""방 단위 추천 러너 — **실제 LLM 을 호출한다(크레딧 소모).**

`run_suggest_eval.py` 와 나란히 두고 **둘 다 유지한다.** 재는 질문이 다르다.

|              | `run_suggest_eval`  | 이 러너                    |
|--------------|---------------------|----------------------------|
| 단위         | 자료 1건 독립 호출  | **방 전체 한꺼번에**       |
| 답하는 질문  | 이 자료가 뭘 낳나   | 사용자가 버튼을 누르면 뭘 보나 |
| 파이프라인   | LLM 호출만          | **운영 `suggest()` 그래프 전부** |
| 실행         | 1회                 | **반복 → 평균 ± 표준편차** |

## 왜 방 단위여야 하는가

사용자 불만 중 **"여러 개 중 하나 고르기"** 류(`맛집 10곳 중 1곳 체크하기`,
`서면-남포동-흰여울문화마을 코스로 묶기`)는 **자료 여러 건이 한 프롬프트에 같이 들어갈 때**
나온다. 자료 1건씩 넣는 기존 러너로는 증상 자체가 재현되지 않는다.
**"후보가 마른다"** 도 제외 목록이 쌓여야 나오는데 기존 러너는 그 목록이 늘 비어 있다.

## 왜 반복해야 하는가

같은 조건 재실행에서 후보 수가 31↔35 · 28↔25 로 갈린다([`docs/DECISIONS.md`] 미확정
"추천 후보의 제목 길이"). **편차를 모르면 "3개 늘었다" 가 개선인지 잡음인지 못 가른다.**

## 채점하지 않는다

라벨 없이 셀 수 있는 것만 센다. 오늘 불만을 재는 지표(`대상 없음`/`여러 개 중 고르기`/
`메타 행위`)는 **여기서 만들지 않는다** — `등`·`중`·`잡기` 같은 단어로 세면 반드시 헛걸린다
(`국제밀면 등`은 걸려야 하고 `짐 챙기기`는 아니다). 출력을 눈으로 분류해 경계를 본 다음
정의한다. 순서를 뒤집었다가 이틀을 버린 전례가 [`ai/CLAUDE.md`] 에 있다.

    uv run python -m evals.run_room_eval                        # 2방 × 3라운드 × 5반복
    uv run python -m evals.run_room_eval --rooms busan_travel --repeats 1   # 크레딧 아끼며 확인
    uv run python -m evals.run_room_eval --start-excluded captured  # 캡처 당시 제외 목록에서 시작

CI 에서 돌지 않는다(`pyproject.toml` 의 `testpaths` 밖) — 크레딧을 쓴다.
순수 로직은 `tests/test_room_runner.py` 가 크레딧 0 으로 잰다.
"""

import argparse
import json
import logging
import os
import statistics
import time
from contextlib import contextmanager
from dataclasses import asdict, dataclass, field
from datetime import date
from pathlib import Path

from langchain_core.callbacks import get_usage_metadata_callback

from evals.rooms import RoomFixture, available_slugs, load_rooms
from modi_ai.config import get_settings
from modi_ai.embeddings import get_embedder
from modi_ai.schemas import SuggestionRequest, TodoCandidate
from modi_ai.suggest import _normalize, get_llm, suggest
from modi_ai.tracing import configure_tracing

log = logging.getLogger(__name__)

OUTPUT_PATH = Path(__file__).parent / "data" / "room_eval_export.json"

# 서버 `TodoSuggestionExposureStore.MAX_EXCLUDED` 를 미러링한다.
# ⚠️ **여기가 어긋나면 "후보가 마른다" 측정이 통째로 틀린다.** 숫자는 그럴듯하게 나오므로
# 증상이 안 보인다 — `tests/test_room_runner.py` 가 유일한 방어선이다.
MAX_EXCLUDED = 16

# [#13](../docs/EXPERIMENTS.md) 이 쓰기로 한 관측 기준선. **합격선이 아니다.**
CONCISE_TITLE_LENGTH = 20


class ExposureWindow:
    """'이미 보여준 후보' 창 — 서버 `TodoSuggestionExposureStore` 의 동작을 그대로 흉내낸다.

    서버는 행을 지우지 않고 **조회를 최근 N개로 제한**해서 상한을 지킨다. 여기서는 DB 가
    없으므로 리스트를 뒤에서 자른다 — **조회 결과는 같다.**

    중복 판정은 운영 `suggest._normalize` 를 **그대로 가져다 쓴다.** 복사하면 드리프트한다
    (서버 Java 쪽이 이미 이 함수를 손으로 미러링하고 있고, 그쪽은 테스트로 고정돼 있다).

    ## ⚠️ 한 회차 안의 순서는 **뒤집어야** 서버와 같다 (2026-08-03 리뷰 지적)

    서버 `record()` 는 후보 순서대로 `saveAll` 하고, 조회는
    `order by e.createdAt desc, e.id desc` 다(`TodoSuggestionExposureRepository`).
    같은 `saveAll` 안의 행들은 `createdAt` 이 같아 **`id desc` 가 순서를 정하므로 그 회차의
    마지막 후보가 맨 앞(최신)** 이 된다. 처음에는 `fresh + titles` 로 넣어 **첫 후보가 맨 앞**
    이었다 — 정반대다.

    실사용(회당 최대 8개, `prompts.py` 규칙 6)에서는 창을 안 넘겨 **남는 집합은 같았지만**,
    `build_payload` 가 `excluded_todos` 를 **리스트 순서 그대로** 프롬프트에 렌더하므로 러너가
    보내는 문자열이 운영과 달랐다. "운영 재현"이 이 러너의 존재 이유라 맞춘다.

    **서버 `truncate` 의 255자 절단은 미러링하지 않는다** — `filter_candidates` 가 50자 초과를
    이미 버려서(`schemas.MAX_TITLE_LENGTH`) 여기까지 오지 않는다.
    """

    def __init__(self, initial: list[str], *, limit: int = MAX_EXCLUDED) -> None:
        # `limit` 기본값은 **운영값**이다(`MAX_EXCLUDED`). 인자를 안 주면 지금까지 얼린
        # 스냅샷과 같은 조건이라 비교가 성립한다 — 기본값을 바꾸면 옛 기준선이 거짓이 된다.
        self._limit = limit
        # 최신이 앞이다 — 서버 `findRecentTitles` 가 최신순으로 준다.
        self._titles = list(initial[:limit])

    def add(self, candidates: list[TodoCandidate]) -> None:
        known = {_normalize(t) for t in self._titles}
        fresh = []
        for candidate in candidates:
            title = candidate.title.strip()
            # 빈 제목은 넣지 않는다 — 정규화하면 빈 문자열이 되어 이후 전부를 제외해버린다
            # (서버 `truncate` 와 같은 이유).
            if not title or _normalize(title) in known:
                continue
            known.add(_normalize(title))
            fresh.append(title)
        # `reversed` 가 위 docstring 의 `id desc` 다. 빼면 회차 내부 순서가 서버와 뒤집힌다.
        self._titles = (list(reversed(fresh)) + self._titles)[: self._limit]

    @property
    def titles(self) -> list[str]:
        return list(self._titles)


class UsageCollector:
    """LLM 토큰을 모은다. **운영 코드를 건드리지 않는다.**

    `suggest()` 는 사용량을 돌려주지 않는다(계약이 그렇다).

    ⚠️ **`llm.with_config(callbacks=[...])` 로는 안 잡힌다** — 실측으로 확인했다.
    `suggest._generate` 가 그 위에 `with_structured_output()` 을 다시 얹으면서 새 시퀀스를
    만들어 config 가 떨어져 나간다(`on_chat_model_start` 조차 안 불렸다). 그래서
    `get_usage_metadata_callback()` 컨텍스트 매니저를 쓴다 — configure hook 으로 걸려
    **러너블을 어떻게 조립하든** 잡힌다.
    """

    def __init__(self) -> None:
        self.prompt_tokens = 0
        self.completion_tokens = 0

    def absorb(self, usage_metadata: dict) -> None:
        """`get_usage_metadata_callback()` 이 준 `{모델명: {…}}` 를 합친다."""
        for usage in usage_metadata.values():
            self.prompt_tokens += usage.get("input_tokens", 0)
            self.completion_tokens += usage.get("output_tokens", 0)


@dataclass
class RoundResult:
    """추천 버튼 1회분."""

    room: str
    repeat: int
    round_index: int
    """1부터. 1회차 = 사용자가 처음 누른 것."""

    excluded_before: int
    candidates: list[dict] = field(default_factory=list)
    prompt_tokens: int = 0
    completion_tokens: int = 0
    seconds: float = 0.0
    error: str | None = None
    critique_failed_open: bool = False
    """검수가 판정을 못 맞춰 **후보를 통째로 통과**시켰는가.

    ⚠️ **이 필드가 없어서 #29 ④의 수치(부산 27~40%)에 커밋된 근거가 없다.** 콘솔 로그로만
    관측했고 스냅샷 어디에도 안 남았다 — 다른 사람이 검산할 수 없는 숫자로 별도 티켓의
    심각도를 정한 셈이다(2026-08-03 리뷰 P1-1). 다음 측정부터는 파일에 남는다.
    """

    @property
    def count(self) -> int:
        return len(self.candidates)


@contextmanager
def _watch_critique_fail_open():
    """`_critique` 의 fail-open 을 **로그로** 잡는다 — 세 갈래가 전부 `log.error` 를 남긴다.

    왜 로그인가: `suggest()` 는 후보만 돌려주고 검수가 걸렸는지는 안 알려준다. 그걸 알려면
    운영 반환 계약을 바꿔야 하는데, 러너 하나 때문에 그걸 바꾸지 않는다(`run_round` 가
    **운영 그래프를 그대로** 부르는 것이 이 러너의 전제다).

    ⚠️ **로그 문구에 묶여 있다.** `_critique` 의 `log.error` 문구가 바뀌면 조용히 0을 센다 —
    `tests/test_room_runner.py` 가 실제 fail-open 을 흘려 그 결합을 고정한다.
    """
    seen: list[bool] = []

    class _Catch(logging.Handler):
        def emit(self, record: logging.LogRecord) -> None:
            if record.levelno >= logging.ERROR and "전부 통과시킨다" in record.getMessage():
                seen.append(True)

    logger = logging.getLogger("modi_ai.suggest")
    handler = _Catch()
    logger.addHandler(handler)
    try:
        yield seen
    finally:
        logger.removeHandler(handler)


def run_round(
    request: SuggestionRequest, llm, embed, *, room: str, repeat: int, round_index: int
) -> RoundResult:
    """추천 1회. **운영 `suggest()` 그래프를 그대로 부른다.**

    앱이 보여주는 것은 필터·의미중복제거·카테고리매칭을 다 거친 결과다. LLM 출력만 보면
    사용자가 본 것과 **다른 것**을 재게 된다.
    """
    usage = UsageCollector()
    result = RoundResult(
        room=room,
        repeat=repeat,
        round_index=round_index,
        excluded_before=len(request.excluded_todos),
    )

    started = time.perf_counter()
    try:
        with get_usage_metadata_callback() as collected, _watch_critique_fail_open() as bypassed:
            response = suggest(request, llm, embed)
        usage.absorb(collected.usage_metadata)
        result.critique_failed_open = bool(bypassed)
    except Exception as exc:  # noqa: BLE001 — 한 라운드가 죽어도 나머지를 계속 돌린다
        result.error = f"{type(exc).__name__}: {exc}"
        result.seconds = round(time.perf_counter() - started, 2)
        return result

    result.seconds = round(time.perf_counter() - started, 2)
    result.candidates = [c.model_dump() for c in response.candidates]
    result.prompt_tokens = usage.prompt_tokens
    result.completion_tokens = usage.completion_tokens
    return result


def captured_date(fixture: RoomFixture) -> date:
    """픽스처를 캡처한 날 — 그 방을 **그때 봤을 때의 '오늘'** 이다.

    `date.today()` 를 쓰면 안 된다. 픽스처는 과거 캡처(부산 방은 2026-08-03 캡처에 종료일이
    2026-08-05)라 실행 시점 날짜를 쓰면 **같은 스냅샷이 날마다 다른 값**을 내고 곧 음수가
    된다. 캡처일로 고정하면 크레딧 0 으로 재현되고, 픽스처를 다시 뜨면 `fixture_digests` 가
    바뀌어 그 사실이 스냅샷에 남는다.
    """
    return date.fromisoformat(fixture.captured_at[:10])


def run_repeat(
    fixture: RoomFixture,
    llm,
    embed,
    *,
    repeat: int,
    rounds: int,
    start_excluded: str,
    exclusion_window: int = MAX_EXCLUDED,
    today: str = "none",
) -> list[RoundResult]:
    """'방에 들어가 추천을 `rounds` 번 연속으로 누른다' 한 벌.

    **`fresh`(기본)는 제외 목록을 비우고 시작한다.** 캡처 당시 창은 이미 16개가 차 있어서,
    그대로 두면 1회차가 이미 '4회차 이후' 처럼 보인다 — 마름을 재려면 1회차가 **처음 누른
    것**이어야 한다. 캡처값에서 시작하고 싶으면 `--start-excluded captured`.

    `exclusion_window` 는 창 크기 팔이다. 기본값이 운영값(`MAX_EXCLUDED`)이라 안 주면
    기존 측정과 같다 — 근거는 `--exclusion-window` 인자 설명 참고.

    `today` 는 프롬프트에 '오늘'을 넣는 팔이다. 기본 `none` 이 **지금 운영**이라 안 주면
    기존 측정과 같다. `captured` 면 픽스처 캡처일을 쓴다(`captured_date`).
    """
    base = fixture.request
    window = ExposureWindow(
        list(base.excluded_todos) if start_excluded == "captured" else [],
        limit=exclusion_window,
    )
    today_value = captured_date(fixture) if today == "captured" else None

    results: list[RoundResult] = []
    for round_index in range(1, rounds + 1):
        request = base.model_copy(update={"excluded_todos": window.titles, "today": today_value})
        result = run_round(
            request, llm, embed, room=fixture.slug, repeat=repeat, round_index=round_index
        )
        results.append(result)
        if result.error:
            # 이 반복의 남은 라운드는 의미가 없다 — 제외 목록이 안 쌓여 다음 라운드가
            # 같은 조건의 재실행이 되어버린다.
            print(f"    !! {result.error} — 이 반복의 남은 라운드는 건너뛴다")
            break
        window.add([TodoCandidate.model_validate(c) for c in result.candidates])
    return results


def run_name(
    model: str,
    *,
    rounds: int,
    repeats: int,
    start_excluded: str,
    critique: int,
    partial_retry: bool,
    exclusion_window: int,
    today: str,
) -> str:
    """`export` 의 키. **조건이 다르면 반드시 달라야 한다.**

    이름이 겹치면 A/B 두 짝 중 하나가 **조용히 덮인다** — 파일만 봐서는 사라진 걸 알 수 없다.
    `run_suggest_eval.run_name` 이 같은 이유로 조건을 이름에 넣는다.

    ⚠️ `main()` 안에 인라인으로 두면 조건을 추가할 때 여기를 빠뜨렸는지 테스트할 수 없다.
    실제로 `freeze_snapshot` 이 같은 이유(나열을 손으로 관리)로 두 번 결함을 냈다.
    """
    return (
        f"{model}_r{rounds}x{repeats}_{start_excluded}_critique{critique}"
        f"{'_partial' if partial_retry else ''}_win{exclusion_window}_today-{today}"
    )


def export_conditions(
    model: str,
    *,
    rounds: int,
    repeats: int,
    start_excluded: str,
    critique: int,
    partial_retry: bool,
    exclusion_window: int,
    today: str,
) -> dict:
    """`export[name]` 의 조건 블록. **`run_name` 과 같은 축을 담아야 한다.**

    이름과 파일 내용이 갈리면, 이름으로는 구분되는 두 실행이 파일에서는 같아 보인다.
    `freeze_snapshot.room_conditions` 가 여기서 나온 키를 **통째로** 스냅샷에 옮기므로
    이 딕셔너리가 "그 측정의 조건"의 단일 진실이다.
    """
    return {
        "model": model,
        "rounds": rounds,
        "repeats": repeats,
        "start_excluded": start_excluded,
        "exclusion_window": exclusion_window,
        "today": today,
        "critique_max_attempts": critique,
        "regenerate_on_partial_reject": partial_retry,
        "temperature": "운영 기본값",
    }


def mean_sd(values: list[float]) -> tuple[float, float]:
    """평균과 표준편차. **표본 1개면 편차는 0 이 아니라 잴 수 없는 것**이지만, 리포트에서
    `0.0` 으로 찍고 표본 수를 함께 적어 구분한다(`--repeats 1` 은 편차를 재려는 실행이 아니다).
    """
    if not values:
        return 0.0, 0.0
    if len(values) == 1:
        return round(values[0], 2), 0.0
    return round(statistics.fmean(values), 2), round(statistics.stdev(values), 2)


def round_stats(results: list[RoundResult], round_index: int) -> dict:
    """한 회차를 반복들 사이에서 집계한다 — 3회차가 몇 개를 내는지가 '마름' 축이다."""
    picked = [r for r in results if r.round_index == round_index and not r.error]
    counts = [float(r.count) for r in picked]
    mean, sd = mean_sd(counts)
    return {
        "round": round_index,
        "samples": len(picked),
        "count_mean": mean,
        "count_sd": sd,
        "count_min": int(min(counts)) if counts else 0,
        "count_max": int(max(counts)) if counts else 0,
    }


def title_length_stats(results: list[RoundResult]) -> dict:
    """제목 길이 분포. **관측이지 합격선이 아니다**(`run_suggest_eval` 과 같은 규약)."""
    lengths = sorted(len(c["title"]) for r in results for c in r.candidates)
    if not lengths:
        return {"min": 0, "median": 0.0, "max": 0, f"over_{CONCISE_TITLE_LENGTH}": 0}
    return {
        "min": lengths[0],
        "median": round(statistics.median(lengths), 1),
        "max": lengths[-1],
        f"over_{CONCISE_TITLE_LENGTH}": sum(1 for n in lengths if n > CONCISE_TITLE_LENGTH),
    }


def summarize_room(fixture: RoomFixture, results: list[RoundResult], rounds: int) -> dict:
    ok = [r for r in results if not r.error]
    return {
        "room_label": fixture.room_label,
        "captured_at": fixture.captured_at,
        "archive_items": len(fixture.request.archive),
        "repeats": len({r.repeat for r in results}),
        "rounds": rounds,
        "errors": sum(1 for r in results if r.error),
        "per_round": [round_stats(results, i) for i in range(1, rounds + 1)],
        "total_candidates": sum(r.count for r in ok),
        "title_length": title_length_stats(ok),
        "prompt_tokens": sum(r.prompt_tokens for r in ok),
        "completion_tokens": sum(r.completion_tokens for r in ok),
        "seconds_mean": mean_sd([r.seconds for r in ok])[0],
        "critique_failed_open": sum(1 for r in ok if r.critique_failed_open),
    }


def print_room_report(fixture: RoomFixture, results: list[RoundResult], summary: dict) -> None:
    print(f"\n{'=' * 78}\n{fixture.summary}\n{'=' * 78}")

    for stats in summary["per_round"]:
        note = "" if stats["samples"] else "  (표본 없음)"
        spread = f"최소 {stats['count_min']} / 최대 {stats['count_max']}"
        print(
            f"  {stats['round']}회차 · 후보 {stats['count_mean']:5.2f} ± {stats['count_sd']:.2f}"
            f"  ({spread}, 표본 {stats['samples']}){note}"
        )

    lengths = summary["title_length"]
    print(
        f"  제목 길이 최소 {lengths['min']} / 중간값 {lengths['median']} / 최대 {lengths['max']}"
        f" · {CONCISE_TITLE_LENGTH}자 초과 {lengths[f'over_{CONCISE_TITLE_LENGTH}']}개"
    )
    print(
        f"  토큰 prompt {summary['prompt_tokens']:,} / completion "
        f"{summary['completion_tokens']:,} · 라운드 평균 {summary['seconds_mean']}초"
        f" · 오류 {summary['errors']}건"
    )
    bypassed = summary["critique_failed_open"]
    if bypassed:
        # 조용히 넘어가면 안 된다 — 이 라운드들은 **검수를 안 탄** 것이라 조건이 다르다.
        # 이걸 안 세서 #28 이 "검수가 매번 걸렸다"는 전제로 쓰였다(#29 ④).
        total = len(results) - summary["errors"]
        print(
            f"  ⚠️ 검수 fail-open {bypassed}/{total} 라운드 — 그만큼은 검수 없이 나갔다"
            f" (docs/EXPERIMENTS.md #29 ④)"
        )
    if summary["total_candidates"] and not summary["prompt_tokens"]:
        # 후보는 나왔는데 토큰이 0이면 **수집이 고장난 것**이지 공짜로 돈 것이 아니다.
        # 실제로 한 번 그랬다(`UsageCollector` docstring) — 조용히 넘어가면 안 된다.
        print("  ⚠️ 토큰이 0이다 — UsageCollector 가 못 잡고 있다(수치를 믿지 말 것)")

    # ★ 이 덤프가 2단계(눈으로 분류)의 입력이다. 첫 반복만 찍는다 — 전부 찍으면 못 읽는다.
    print("\n  [1번째 반복 후보 전문 — 나머지는 export 파일]")
    for result in [r for r in results if r.repeat == 1]:
        if result.error:
            print(f"    {result.round_index}회차: ERROR {result.error}")
            continue
        print(f"    {result.round_index}회차 (제외 {result.excluded_before}개):")
        for candidate in result.candidates:
            print(f"      {candidate['title']}")


def build_parser() -> argparse.ArgumentParser:
    """CLI 정의. `main()` 에서 뽑아낸 이유는 **테스트가 도달해야 하기 때문**이다.

    ⚠️ **help 문구에 cp949 로 못 쓰는 글자(em dash `—`, 이모지)를 넣지 말 것.** Windows 콘솔
    기본 코드페이지가 cp949 라 `--help` 자체가 `UnicodeEncodeError` 로 죽는다. 실제로 이 커밋
    작업 중 **두 번** 냈다 — 주석만으로는 안 막혀서 `tests/test_room_runner.py` 가 검사한다.
    """
    parser = argparse.ArgumentParser(description="방 단위 추천 러너 (실제 LLM 호출)")
    parser.add_argument(
        "--rooms",
        default=None,
        help=f"쉼표 구분. 기본은 전부. 있는 것: {','.join(available_slugs()) or '(없음)'}",
    )
    parser.add_argument(
        "--rounds",
        type=int,
        default=3,
        help="'추천' 버튼을 연속으로 몇 번 누르는가. 회차마다 앞 회차 후보가 제외 목록에 쌓인다",
    )
    parser.add_argument(
        "--repeats",
        type=int,
        default=5,
        help="라운드 열을 몇 번 독립 반복하는가. **편차를 재려면 2 이상이어야 한다**",
    )
    parser.add_argument(
        "--start-excluded",
        choices=("fresh", "captured"),
        default="fresh",
        help="1회차의 제외 목록. fresh(기본)=비우고 시작, captured=캡처 당시 그대로",
    )
    parser.add_argument(
        "--exclusion-window",
        type=int,
        default=MAX_EXCLUDED,
        # ⚠️ **help 문구에 cp949 로 못 쓰는 글자를 넣지 말 것**(em dash, 이모지). Windows 콘솔
        # 기본 코드페이지가 cp949 라 `--help` 자체가 UnicodeEncodeError 로 죽는다. 이 파일의
        # 다른 help 문구가 전부 그것을 피하고 있다.
        help=f"'이미 보여준 후보' 창 크기. 기본 {MAX_EXCLUDED}=운영값(서버 "
        "TodoSuggestionExposureStore.MAX_EXCLUDED). #24 가 같은 방 데이터로 3회씩 재보니 후보 "
        "평균이 50:2.0 / 24:5.3 / 16:6.0 / 8:7.3 / 0:7.0 이었다. **8 이 최선이었는데 16 을 "
        "골랐고 그 근거가 남아 있지 않다.** 0 이면 제외를 아예 안 보낸다",
    )
    parser.add_argument(
        "--today",
        choices=("none", "captured"),
        default="none",
        # cp949 로 못 쓰는 글자(em dash, 이모지) 금지 — 위 --exclusion-window 주석 참고.
        help="프롬프트에 '오늘'과 종료까지 남은 일수를 넣는가. none(기본)=지금 운영과 같다 "
        "· captured=픽스처 캡처일을 쓴다. **실행 시점 날짜를 쓰지 않는다**: 픽스처가 과거 "
        "캡처라 날마다 결과가 달라지고 종료일을 지나면 음수가 된다",
    )
    parser.add_argument(
        "--critique",
        type=int,
        default=None,
        help="후보 생성 최대 횟수. 0=검수 안 함 · 1=검수만 · 2=재생성 1회. "
        "기본은 설정값. **A/B 두 짝이 구분되게 실행 이름과 export 에 남는다**",
    )
    parser.add_argument(
        "--partial-retry",
        type=int,
        choices=(0, 1),
        default=None,
        help="검수가 후보를 일부만 반려해도 재생성하는가. 0=끔(-235 와 같음) · "
        "1=켬. `--critique 2` 이상과 같이 줘야 실제로 돈다. 기본은 설정값",
    )
    parser.add_argument("--label", default=None, help="export 파일에 남길 실행 이름")
    return parser


def main() -> None:
    args = build_parser().parse_args()

    logging.basicConfig(level=logging.WARNING, format="%(levelname)s:%(name)s:%(message)s")
    configure_tracing(get_settings())

    if args.rounds < 1:
        raise SystemExit(f"--rounds 는 1 이상이어야 한다(받은 값: {args.rounds})")
    if args.repeats < 1:
        raise SystemExit(f"--repeats 는 1 이상이어야 한다(받은 값: {args.repeats})")
    # 0 은 막지 않는다 — #24 가 실제로 잰 값이다("제외를 아예 안 보낸다").
    if args.exclusion_window < 0:
        raise SystemExit(
            f"--exclusion-window 는 0 이상이어야 한다(받은 값: {args.exclusion_window})"
        )

    if args.critique is not None:
        if args.critique < 0:
            raise SystemExit(f"--critique 는 0 이상이어야 한다(받은 값: {args.critique})")
        # `get_settings` 가 `lru_cache` 라 값을 바꾸려면 캐시를 비워야 한다. 환경변수로 넣는
        # 이유는 **운영과 같은 경로**로 읽히게 하기 위해서다 — 여기서 객체를 만들어 주입하면
        # 러너만 다른 길을 타게 된다.
        os.environ["CRITIQUE_MAX_ATTEMPTS"] = str(args.critique)
        get_settings.cache_clear()

    if args.partial_retry is not None:
        os.environ["REGENERATE_ON_PARTIAL_REJECT"] = str(bool(args.partial_retry))
        get_settings.cache_clear()

    slugs = [s.strip() for s in args.rooms.split(",") if s.strip()] if args.rooms else None
    # 호출 **전에** 전부 읽는다 — 두 번째 방 픽스처가 없어 죽으면 첫 방의 크레딧이 날아간다.
    fixtures = load_rooms(slugs)
    if not fixtures:
        raise SystemExit("방 픽스처가 하나도 없다. evals/data/rooms/ 를 확인할 것.")

    settings = get_settings()
    model = settings.openai_model
    critique = settings.critique_max_attempts
    partial_retry = settings.regenerate_on_partial_reject
    calls = len(fixtures) * args.rounds * args.repeats
    print(
        f"방 {len(fixtures)}개 × {args.rounds}라운드 × {args.repeats}반복 = 최대 {calls}회 호출 · "
        f"모델 {model} · 제외 시작 {args.start_excluded} · 오늘 {args.today}"
        f" · 제외 창 {args.exclusion_window}"
        f"{' (운영값)' if args.exclusion_window == MAX_EXCLUDED else ' (운영과 다름!)'} · "
        f"검수 상한 {critique}{' (검수 안 함)' if not critique else ''} · "
        f"부분 반려 재생성 {'켬' if partial_retry else '끔'}"
    )
    if partial_retry and critique < 2:
        # 조용히 아무 일도 안 일어나는 조합이다 — 재생성할 시도가 남아 있지 않다.
        print(f"⚠️ --partial-retry 1 인데 검수 상한이 {critique} 라 재생성이 **안 돈다**")
    # ⚠️ temperature 를 고정하지 않는다 — `run_suggest_eval` 은 0.0 으로 박지만 그건 프롬프트
    # 효과를 분리하려는 것이고, 여기서 재려는 것은 **사용자가 실제로 보는 것**이다.
    print("temperature: 운영 기본값(고정 안 함) — 잡음은 반복으로 처리한다\n")
    for fixture in fixtures:
        print(f"  · {fixture.summary}")

    # export 도 호출 **전에** 읽는다. 다 쓴 뒤에 읽다가 파일이 손상돼 있으면 크레딧이 날아간다.
    export = json.loads(OUTPUT_PATH.read_text(encoding="utf-8")) if OUTPUT_PATH.exists() else {}
    # **조건이 다르면 이름도 달라야 한다** — 안 그러면 A/B 두 짝 중 하나가 조용히 덮인다
    # (`run_suggest_eval.run_name` 이 같은 이유로 조건을 이름에 넣는다).
    name = args.label or run_name(
        model,
        rounds=args.rounds,
        repeats=args.repeats,
        start_excluded=args.start_excluded,
        critique=critique,
        partial_retry=partial_retry,
        exclusion_window=args.exclusion_window,
        today=args.today,
    )
    if name in export:
        print(f"주의: export 의 기존 실행 '{name}' 을 덮어쓴다")

    llm = get_llm()
    embed = get_embedder()
    rooms_payload: dict[str, dict] = {}
    try:
        for fixture in fixtures:
            results: list[RoundResult] = []
            for repeat in range(1, args.repeats + 1):
                print(f"\n[{fixture.slug}] 반복 {repeat}/{args.repeats}", flush=True)
                results.extend(
                    run_repeat(
                        fixture,
                        llm,
                        embed,
                        repeat=repeat,
                        rounds=args.rounds,
                        start_excluded=args.start_excluded,
                        exclusion_window=args.exclusion_window,
                        today=args.today,
                    )
                )
            summary = summarize_room(fixture, results, args.rounds)
            print_room_report(fixture, results, summary)
            rooms_payload[fixture.slug] = {
                "summary": summary,
                "rounds": [asdict(r) for r in results],
            }
    except KeyboardInterrupt:
        # 유료 호출을 이미 태웠으므로 지금까지 받은 것은 저장한다.
        print(f"\n중단됨 — 방 {len(rooms_payload)}개까지 저장한다")

    export[name] = export_conditions(
        model,
        rounds=args.rounds,
        repeats=args.repeats,
        start_excluded=args.start_excluded,
        critique=critique,
        partial_retry=partial_retry,
        exclusion_window=args.exclusion_window,
        today=args.today,
    ) | {"rooms": rooms_payload}
    OUTPUT_PATH.write_text(json.dumps(export, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n결과 저장: {OUTPUT_PATH} (run={name})")


if __name__ == "__main__":
    main()
