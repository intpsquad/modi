"""검수 판정 누락 재현 프로브.

`suggest._critique` 는 후보에 번호를 붙여 LLM 에 보내고, 돌아온 판정 개수가 후보 수와 다르면
**배치 전체를 통과**시킨다(fail-open — 검수 고장이 추천 장애가 되면 안 된다는 의도된 정책).
그런데 그게 부산 여행 방에서 반복해서 일어났고, 로그가 전부 `후보 N개, 판정 N-1개` 였다 —
**정확히 하나씩** 모자랐다. 그 라운드는 검수를 안 한 것과 같아 반려돼야 할 후보가 그대로 나간다.

이 러너는 **고치기 전에 원인을 재현하기 위한 것**이다. `ai/CLAUDE.md` 가 "프롬프트·계약 변경은
평가셋 실측으로 검증한다"로 막아둔 자리다([`docs/EXPERIMENTS.md`] #6 전례: 규칙 하나를 근거 없이
추가해 정확도가 14/15 → 10/15 로 후퇴했다).

## 무엇을 가르는가

| 조건 | 재는 것 |
|---|---|
| `zero_based` | 운영과 **글자까지 같은** 렌더링. 정말 하나씩 모자란가, 어느 번호가 빠지는가 |
| `one_based` | 번호를 `1.` 부터 매기면 사라지는가 (**가설 A**) |

`near_dup` 묶음은 두 조건 모두에서 함께 돈다 — 뜻이 겹치는 제목이 섞이면 모델이 판정을 하나로
합치는지 본다(**가설 B 의 약한 형태**).

⚠️ **가설 B 의 강한 형태(글자가 같은 제목)는 코드로 이미 기각됐다** — `suggest.filter_candidates`
가 `_normalize`(공백 제거 + 소문자) 기준 중복을 **검수 전에** 버리므로, 글자가 같은 후보 둘이
`_critique` 에 함께 도달할 수 없다. 그래서 여기서는 "뜻이 비슷한 쌍"만 본다.

## ⚠️ 빠진 **번호**와 판정을 못 받은 **후보**는 다른 것이다 (2026-08-03 리뷰 P0)

`missing` 은 "돌아오지 않은 번호 라벨"이다. 개수 검사를 통과한 뒤라면 응답이 `0..n-2` 로
연속인 한 `missing` 은 **반드시** `[n-1]` 이 된다 — 관측이 아니라 산수다. 그걸 "꼬리 후보가
빠졌다"로 읽으면 안 된다.

**어느 후보가 판정을 못 받았는지는 반려 사유를 후보와 대조해야만 알 수 있다**(통과 판정에는
사유가 없어서 그 구간은 확정 불가다). 실측에서 밀림 시작점이 묶음마다 달랐다 — `opic_8` 은
`index=5` 까지 라벨과 맞고 `6` 부터 밀렸는데, `busan_8c` 는 `index=4` 에서 이미 밀렸다.

그래서 이 러너가 답할 수 있는 것은 여기까지다.

- **응답 모양**: 판정이 몇 개 오고 번호가 어떻게 붙는가
- **밀림의 존재**: 반려 사유가 라벨이 가리키는 후보와 어긋나는가

`왜` 모델이 특정 후보를 건너뛰는지는 이 러너로 못 답한다.

## 입력

`data/snapshots/2026-08-03_room_ab_critique0.json` 에 커밋된 **실제 후보 묶음**이다. 검수를 끄고
(`critique_max_attempts=0`) 돌린 실행이라 생성이 낸 것 그대로다. **새로 생성 호출을 하지 않는다** —
재려는 것은 생성이 아니라 검수이고, 생성은 호출당 프롬프트가 100배 비싸다.

## 운영과 같은 것을 재고 있는가

`render_candidates(titles, start=0)` 은 `_critique` 의 렌더링과 **글자까지 같아야 한다.**
`tests/test_probe_critique.py` 가 가짜 LLM 으로 운영 `_critique` 가 실제로 보내는 메시지를 잡아
이 함수의 출력과 비교한다 — 한쪽만 바뀌면 테스트가 깨진다.

## 실행

    PYTHONUTF8=1 uv run python -m evals.probe_critique

`PYTHONUTF8=1` 이 필요하다 — cp949 윈도우에서 출력에 `—` 가 섞이면 `UnicodeEncodeError` 로 죽는다.

크레딧: 조건 2 × 묶음 6 × 반복 5 = **60 회**. 호출당 프롬프트 약 1천 토큰(제목만 보낸다)이라
합계 6만 토큰 수준 — 방 평가 1회(방당 13만 토큰)의 절반 이하다.
"""

import hashlib
import json
import time
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from langchain_core.messages import HumanMessage, SystemMessage

from modi_ai.config import get_settings
from modi_ai.prompts import CRITIQUE_PROMPT
from modi_ai.schemas import CritiqueResponse
from modi_ai.suggest import get_llm

REPEATS = 5

SNAPSHOT_DIR = Path(__file__).parent / "data" / "snapshots"
OUTPUT = SNAPSHOT_DIR / "2026-08-03_critique_index_probe.json"

# 출처: `data/snapshots/2026-08-03_room_ab_critique0.json`. 방·반복·회차를 이름에 남긴다 —
# 나중에 원본을 다시 찾을 수 있어야 한다. 순서·표기 모두 스냅샷 그대로다.
BATCHES: dict[str, list[str]] = {
    # busan_travel repeat 2 round 1 (n=8)
    "busan_8a": [
        "부산 해운대블루라인파크 이용시간 확인하기",
        "감천문화마을 골목 탐방 일정 넣기",
        "씨라이프 부산아쿠아리움 관람 계획하기",
        "부산역 점심 초량해 칼국수 방문하기",
        "동백섬 산책 동선 확보하기",
        "웨이팅 있는 해운대명품호떡 확인해보기",
        "수국축제·센텀맥주축제 일정 확인해보기",
        "부모님과 함께 광안리 야경·바다뷰 카페 여유 있게 배치하기",
    ],
    # busan_travel repeat 2 round 3 (n=8)
    "busan_8b": [
        "부산 서면 돼지국밥 맛집 후보 확인하기",
        "영도 미피카페·모모스커피 방문 후보로 정하기",
        "남포 톤쇼우 방문 일정에 넣기",
        "국제밀면 방문 전 캐치테이블 확인하기",
        "부네치아 등 가볼만한 곳 목록에 추가하기",
        "고래사어묵해운대점 어묵 체험 일정 잡기",
        "런닝맨 부산점 실내 액티비티 체험 일정 넣기",
        "삼진어묵 영도본점 방문 전 영업시간 변동 확인하기",
    ],
    # busan_travel repeat 4 round 1 (n=8)
    "busan_8c": [
        "광안대교 야경 즐기기",
        "감천문화마을 골목 탐방하기",
        "해운대블루라인파크 방문하기",
        "씨라이프 부산아쿠아리움 가보기",
        "부산역 초량해 칼국수 점심 먹기",
        "민락동 첨벙 숙성회 웨이팅 확인 후 방문",
        "부네치아 방문해보기",
        "캐치테이블 가능 여부 표시된 맛집으로 일정 짜기",
    ],
    # opic_study repeat 4 round 1 (n=8) — 부산 방에서만 나던 현상인지 가른다
    "opic_8": [
        "자기소개·경험·비교·미래 템플릿 변형 연습하기",
        "서베이 항목을 개수에 맞춰 미리 정하기",
        "완료시제(현재완료·과거완료)로 답변 마무리 만들기",
        "답변 끝에 결론 마무리 멘트 넣기",
        "빈출 주제별 어휘 예문으로 문장화해 복습하기",
        "사전 점검용 OPIC 평가기준·문제유형 가이드 PDF 훑기",
        "시험 당일 입실용 규정신분증 원본 확인하기",
        "시험 40분 동안 12~15개 콤보 순서대로 말하기 리허설",
    ],
    # busan_travel repeat 1 round 1 (n=7) — 8개일 때만 생기는 일인지 가른다
    "busan_7": [
        "해운대블루라인파크 이용 일정 잡기",
        "씨라이프 부산아쿠아리움 방문 시간 확인하기",
        "감천문화마을 골목 탐방 일정 넣기",
        "대저생태공원-을숙도낙동강하구 코스 경로 짜기",
        "부산역 초량해 칼국수 점심으로 넣기",
        "광안리 해수욕장 광안대교 야경 구경하기",
        "호떡(해운대명품호떡) 웨이팅 감안해 방문하기",
    ],
    # 가설 B(약한 형태) 전용. 앞 세 개는 **서로 다른 회차에서 실제로 나온** 초량해 칼국수
    # 변형이다(repeat 1·2·3). 글자가 다르므로 `filter_candidates` 를 통과해 검수까지 간다 —
    # 실제로 한 회차에 이렇게 모일 수 있는지는 별개고, 여기서는 "모이면 합치는가"만 본다.
    "near_dup": [
        "부산역 초량해 칼국수 점심으로 넣기",
        "부산역 점심 초량해 칼국수 방문하기",
        "부산역에서 초량해 칼국수 점심 먹기",
        "감천문화마을 골목 탐방 일정 넣기",
        "씨라이프 부산아쿠아리움 관람 계획하기",
        "동백섬 산책 동선 확보하기",
        "웨이팅 있는 해운대명품호떡 확인해보기",
        "수국축제·센텀맥주축제 일정 확인해보기",
    ],
}

# `start` 값. 이름이 조건 이름이 된다.
CONDITIONS: dict[str, int] = {"zero_based": 0, "one_based": 1}


def render_candidates(titles: list[str], start: int) -> str:
    """후보 목록을 검수 프롬프트에 실리는 모양으로 만든다.

    ⚠️ `start=0` 은 `suggest._critique` 의 렌더링과 **글자까지 같아야 한다.**
    `tests/test_probe_critique.py` 가 그걸 지킨다 — 안 그러면 이 프로브는 운영이 아니라
    자기 자신을 재게 된다.
    """
    return "\n".join(f"{i}. {title}" for i, title in enumerate(titles, start=start))


def build_messages(titles: list[str], start: int) -> list:
    """`_critique` 가 보내는 것과 같은 메시지 두 개."""
    return [
        SystemMessage(content=CRITIQUE_PROMPT),
        HumanMessage(content=f"# 후보\n{render_candidates(titles, start)}"),
    ]


@dataclass
class ProbeRound:
    """검수 호출 1회의 결과."""

    condition: str
    batch: str
    repeat: int
    candidates: int
    verdict_count: int = 0
    indices: list[int] = field(default_factory=list)
    missing: list[int] = field(default_factory=list)
    extra: list[int] = field(default_factory=list)
    duplicated: list[int] = field(default_factory=list)
    rejected: int = 0
    outcome: str = "error"
    seconds: float = 0.0
    error: str | None = None
    # 판정 내용. `0.` 과 `1.` 이 같은 묶음에 같은 판단을 내리는지 눈으로 보려고 남긴다.
    verdicts: list[dict] = field(default_factory=list)


def classify(indices: list[int], candidates: int, start: int) -> str:
    """운영 `_critique` 의 두 검사를 **같은 순서로** 흉내낸다.

    개수를 먼저 보고 그다음 번호 집합을 본다 — 운영이 그 순서라, 로그에 어느 쪽이 찍히는지가
    이 순서에 달려 있다.
    """
    if len(indices) != candidates:
        return "count_mismatch"
    if set(indices) != set(range(start, start + candidates)):
        return "index_mismatch"
    return "ok"


def run_round(llm, *, condition: str, batch: str, titles: list[str], repeat: int) -> ProbeRound:
    """검수 1회. **실패해도 죽지 않는다** — 한 호출이 죽어도 나머지 표를 채운다."""
    start = CONDITIONS[condition]
    result = ProbeRound(condition=condition, batch=batch, repeat=repeat, candidates=len(titles))

    began = time.perf_counter()
    try:
        structured = llm.with_structured_output(CritiqueResponse)
        verdicts = structured.invoke(build_messages(titles, start)).verdicts
    except Exception as exc:  # noqa: BLE001 — 한 호출이 죽어도 나머지를 계속 돈다
        result.seconds = round(time.perf_counter() - began, 2)
        result.error = f"{type(exc).__name__}: {exc}"
        return result

    result.seconds = round(time.perf_counter() - began, 2)
    indices = [v.index for v in verdicts]
    expected = set(range(start, start + len(titles)))
    counted = Counter(indices)

    result.verdict_count = len(verdicts)
    result.indices = indices
    result.missing = sorted(expected - set(indices))
    result.extra = sorted(set(indices) - expected)
    result.duplicated = sorted(i for i, n in counted.items() if n > 1)
    result.rejected = sum(1 for v in verdicts if not v.ok)
    result.outcome = classify(indices, len(titles), start)
    result.verdicts = [{"index": v.index, "ok": v.ok, "reason": v.reason} for v in verdicts]
    return result


def _batch_digest(titles: list[str]) -> str:
    """묶음 내용의 지문 — **스냅샷이 어떤 입력으로 만들어졌는지** 파일에 남기려는 것이다.

    2026-08-03 리뷰(P1-2): 첫 판에는 묶음 **이름과 개수**만 남겼다. 그래서 `BATCHES` 의
    제목을 통째로 바꿔도 커밋된 스냅샷과 모순이 안 생겼고, 스냅샷을 근거로 쓴 논증(어느
    사유가 어느 후보를 가리켰는가)이 조용히 무효가 될 수 있었다.
    """
    return hashlib.sha256("\n".join(titles).encode("utf-8")).hexdigest()[:16]


def summarize(rounds: list[ProbeRound]) -> dict:
    """조건별 결과 분류 + **빠진 번호의 히스토그램**.

    히스토그램이 이 프로브의 핵심 산출물이다 — 항상 가장 작은 번호가 빠지면 가설 A 가 맞고,
    마지막이 빠지면 잘림이다.
    """
    summary: dict[str, dict] = {}
    for condition in CONDITIONS:
        picked = [r for r in rounds if r.condition == condition]
        outcomes = Counter(r.outcome for r in picked)
        missing_positions: Counter[str] = Counter()
        for r in picked:
            for index in r.missing:
                # 번호 자체가 아니라 **위치**로 센다 — 조건마다 시작 번호가 달라 그대로 세면
                # `0.` 과 `1.` 을 나란히 못 놓는다.
                offset = index - CONDITIONS[condition]
                if offset == 0:
                    missing_positions["first"] += 1
                elif offset == r.candidates - 1:
                    missing_positions["last"] += 1
                else:
                    missing_positions[f"middle({offset})"] += 1
        summary[condition] = {
            "rounds": len(picked),
            "outcomes": dict(outcomes),
            "missing_positions": dict(missing_positions),
            "rejected_mean": (
                round(sum(r.rejected for r in picked if not r.error) / max(1, len(picked)), 2)
            ),
            "seconds_mean": round(sum(r.seconds for r in picked) / max(1, len(picked)), 2),
        }
    return summary


def main() -> None:
    settings = get_settings()
    llm = get_llm()
    rounds: list[ProbeRound] = []

    total = len(CONDITIONS) * len(BATCHES) * REPEATS
    done = 0
    for condition in CONDITIONS:
        for batch, titles in BATCHES.items():
            for repeat in range(1, REPEATS + 1):
                result = run_round(
                    llm, condition=condition, batch=batch, titles=titles, repeat=repeat
                )
                rounds.append(result)
                done += 1
                mark = {"ok": "  ", "count_mismatch": "❌", "index_mismatch": "⚠️ "}.get(
                    result.outcome, "💥"
                )
                print(
                    f"[{done:>3}/{total}] {mark} {condition:<11} {batch:<10} "
                    f"#{repeat} 후보 {result.candidates} 판정 {result.verdict_count} "
                    f"빠짐 {result.missing or '-'} 반려 {result.rejected} "
                    f"{result.seconds}s{' ' + result.error if result.error else ''}",
                    flush=True,
                )

    summary = summarize(rounds)

    print("\n=== 조건별 요약 ===")
    for condition, values in summary.items():
        print(f"{condition:<11} {values['outcomes']}  빠진 위치 {values['missing_positions']}")

    payload = {
        "_comment": (
            "검수 판정 누락 재현 프로브. 운영 `_critique` 와 같은 프롬프트·"
            "스키마로 검수만 떼어 부른 결과다. 후보 묶음은 "
            "`2026-08-03_room_ab_critique0.json` 에서 가져온 실측값이고 새 생성 호출은 없다."
        ),
        "measured_at": datetime.now().strftime("%Y-%m-%d"),
        "run": "critique_index_probe",
        "model": settings.openai_model,
        "repeats": REPEATS,
        "conditions": CONDITIONS,
        "batch_sizes": {name: len(titles) for name, titles in BATCHES.items()},
        # 무엇을 보냈는지 **파일 안에** 남긴다 (2026-08-03 리뷰 P1-2). 개수만으로는
        # `BATCHES` 가 나중에 바뀌어도 스냅샷이 모순을 안 낸다.
        "batches": BATCHES,
        "batch_digests": {name: _batch_digest(titles) for name, titles in BATCHES.items()},
        "summary": summary,
        "rounds": [r.__dict__ for r in rounds],
    }
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n저장: {OUTPUT}")


if __name__ == "__main__":
    main()
