"""러너 출력에서 실행 하나를 골라 **동결 스냅샷**으로 커밋한다.

    uv run python -m evals.freeze_snapshot --list
    uv run python -m evals.freeze_snapshot --run "gpt-5.4-nano_summary_공부" --date 2026-08-01
    uv run python -m evals.freeze_snapshot --room --list                      # 방 러너 쪽
    uv run python -m evals.freeze_snapshot --room --run baseline_clean --date 2026-08-03

**LLM 을 호출하지 않는다 — 크레딧 0.** 이미 받아 둔 결과를 옮겨 적을 뿐이다.

`--room` 은 `run_room_eval` 의 export 를 읽는다. 페이로드 구조가 달라(`rooms`/`rounds` vs
`cases`) 빌더를 따로 둔다 — 억지로 한 모양으로 합치면 이미 얼린 8개 스냅샷의 계약이 깨진다.

## 왜 필요한가

러너의 export 는 `.gitignore` 에 있다(실행마다 덮어써진다). 그래서 `docs/EXPERIMENTS.md` 가
**커밋되지 않는 파일의 수치를 근거로 인용**하면, 나중에 그 숫자를 확인할 방법이 사라진다.
실제로 그 사고가 한 번 있었다 — [#13](../docs/EXPERIMENTS.md) 이 문서 수치와 동결 파일이
어긋난 채로 커밋됐고 리뷰에서 잡혔다.

**규칙: EXPERIMENTS 에 적는 숫자는 커밋된 스냅샷에서 나와야 한다.**

## 왜 실행 하나에 파일 하나인가

`dataset.load_snapshot` 이 `cases` 키 하나를 기대한다(2026-07-30 파일부터의 규약).
여러 실행을 한 파일에 넣으면 로더 계약이 깨지고, 기존 스냅샷도 같이 고쳐야 한다.
"""

import argparse
import hashlib
import json

from evals.dataset import SNAPSHOT_DIR
from evals.rooms import ROOM_DIR, available_slugs
from evals.run_room_eval import OUTPUT_PATH as ROOM_OUTPUT_PATH
from evals.run_suggest_eval import OUTPUT_PATH

# 파일 이름에 쓸 수 없는 글자(공백 포함)를 바꾼다 — `할 일` 같은 카테고리가 실행 이름에 들어간다.
_NAME_REPLACEMENTS = {" ": "-", "/": "-", "\\": "-", ":": "-"}


def slugify(run: str) -> str:
    for bad, good in _NAME_REPLACEMENTS.items():
        run = run.replace(bad, good)
    return run


def build(run_name: str, payload: dict, measured_at: str, note: str | None) -> dict:
    """스냅샷 본문. 조건 필드를 **전부** 옮긴다 — 조건 없는 숫자는 근거가 못 된다."""
    snapshot = {
        "_comment": (
            "동결 스냅샷 — 그때 모델이 실제로 낸 후보를 고정한 것이다. 절대 손으로 고치지 말 것. "
            f"docs/EXPERIMENTS.md 의 수치는 이 파일에서 나온다. 실행 이름: {run_name}"
        ),
        "measured_at": measured_at,
        "run": run_name,
        "model": payload["model"],
        # ⚠️ **전부 `.get()` 이다.** 카테고리 축(`rule4`·`schema_category_hint`·`categories`)은
        # 에서 사라졌지만, **그 조건으로 얼린 옛 스냅샷을 계속 읽어야 하므로**
        # 키를 지우지 않는다. 하드 인덱싱으로 두면 새 실행이 `KeyError` 로 죽는다 —
        # 실제로 그렇게 죽었고 2026-08-04 리뷰(P0-2)에서 잡혔다.
        "rule4": payload.get("rule4"),
        "schema_category_hint": payload.get("schema_category_hint"),
        "rule4_version": payload.get("rule4_version"),
        "schema_hint_version": payload.get("schema_hint_version"),
        "input": payload.get("input"),
        "categories": payload.get("categories"),
        "temperature": payload["temperature"],
        "summary": payload["summary"],
        # `dataset.load_snapshot` 이 읽는 세 키 + **문서가 인용하는 per-case 관측값**.
        # 토큰·시간을 버렸다가 EXPERIMENTS #20 의 응답시간·토큰 절이 커밋되지 않는 export 에만
        # 남는 사고가 났다(리뷰 지적). 로더는 특정 키만 인덱싱하므로 여분 키를 넣어도 안전하다 —
        # 최상위에 이미 `_comment`/`summary` 를 넣고도 로더가 도는 것이 그 증거다.
        "cases": [
            {
                "stem": c["stem"],
                "raw_candidate_count": c["raw_candidate_count"],
                "candidates": c["candidates"],
                # 옛 스냅샷 전용 — `map_categories` **전** 모델 원출력이었다(-243 에서 소멸).
                "raw_categories": c.get("raw_categories", []),
                "prompt_tokens": c["prompt_tokens"],
                "seconds": c["seconds"],
                "dropped_by_filter": c["dropped_by_filter"],
                "error": c["error"],
            }
            for c in payload["cases"]
        ],
    }
    if note:
        snapshot["_note"] = note
    return snapshot


def fixture_digests() -> dict[str, str]:
    """방 픽스처 `request` 블록의 해시.

    **이게 스냅샷의 핵심이다.** 수치만 얼려두면 나중에 "그때 입력이 뭐였나"를 알 수 없다.
    픽스처를 다시 뜨면 해시가 바뀌고, 그 순간 이 스냅샷의 수치는 다른 입력에 대한 것이 된다.
    `tests/test_room_runner.py` 가 픽스처 쪽에서 같은 해시를 지킨다.
    """
    digests = {}
    for slug in available_slugs():
        payload = json.loads((ROOM_DIR / f"{slug}.json").read_text(encoding="utf-8"))
        digests[slug] = hashlib.sha256(
            json.dumps(payload["request"], ensure_ascii=False, sort_keys=True).encode()
        ).hexdigest()[:16]
    return digests


# 방 러너 export 에서 **결과**인 키. 나머지는 전부 조건으로 취급해 스냅샷에 옮긴다.
_ROOM_RESULT_KEYS = frozenset({"rooms"})

# 스냅샷이 스스로 채우는 키. export 에 같은 이름이 있어도 조건이 이것을 덮어쓰면 안 된다.
_ROOM_RESERVED_KEYS = frozenset({"_comment", "_note", "measured_at", "run", "fixture_digests"})

# **이게 없는 export 는 옛 러너 것이다.** 조건이 빠진 채 얼리면 근거가 못 된다 — 조용히
# 넘기지 않고 죽인다. 조건을 *추가*할 때는 이 목록을 안 건드려도 된다.
_ROOM_REQUIRED_CONDITIONS = (
    "model",
    "rounds",
    "repeats",
    "start_excluded",
    "critique_max_attempts",
    "regenerate_on_partial_reject",
    "temperature",
)


def room_conditions(payload: dict) -> dict:
    """방 러너 export 에서 조건 블록을 뽑는다 — **나열하지 않고 결과만 뺀다.**

    ## 왜 나열을 버렸나

    조건을 손으로 하나씩 베끼던 탓에 **같은 결함이 두 번 났다**: -235(리뷰 P8)에서
    `critique_max_attempts` 를, 2026-08-03 리뷰에서 또 하나를 빠뜨렸다. 그때마다 필드를
    하나 더 적어 막았지만, 나열이 남아 있는 한 **다음 조건에서 또 난다**(`specs/OPEN.md`).
    러너에 `--exclusion-window`·`--today` 를 붙이는 지금이 정확히 그 "다음"이다.

    그래서 방향을 뒤집는다 — **빼야 할 것(결과)만 알고, 나머지는 다 옮긴다.** 러너가 조건을
    추가하면 이 함수를 고치지 않아도 따라온다.

    필수 조건 검사는 남긴다. 통째로 옮기는 것만으로는 "조건이 애초에 없는 옛 export" 를
    잡지 못하는데, 그건 조용히 근거 없는 스냅샷을 만드는 사고다.
    """
    missing = [key for key in _ROOM_REQUIRED_CONDITIONS if key not in payload]
    if missing:
        raise KeyError(
            f"조건 필드가 없는 옛 export 다({', '.join(missing)}) — 동결하지 않는다. 다시 돌릴 것"
        )
    return {
        key: value
        for key, value in payload.items()
        if key not in _ROOM_RESULT_KEYS and key not in _ROOM_RESERVED_KEYS
    }


def build_room(run_name: str, payload: dict, measured_at: str, note: str | None) -> dict:
    """방 러너 스냅샷. `build` 와 나눈 이유는 페이로드 구조가 다르기 때문이다.

    후보 **전문**을 남긴다 — 지표를 나중에 새로 정의했을 때(2단계, `run_room_eval` 모듈
    docstring) 그때 모델이 실제로 뭘 냈는지 크레딧 0 으로 다시 채점하려면 이게 있어야 한다.
    """
    snapshot = {
        "_comment": (
            "동결 스냅샷(방 단위 러너) — 그때 모델이 실제로 낸 후보를 고정한 것이다. "
            "절대 손으로 고치지 말 것. docs/EXPERIMENTS.md 의 수치는 이 파일에서 나온다. "
            f"실행 이름: {run_name}"
        ),
        "measured_at": measured_at,
        "run": run_name,
        # ⚠️ **조건 필드를 빠뜨리면 A/B 두 짝이 파일만 봐서 구분되지 않는다.**
        **room_conditions(payload),
        # 입력을 못 박는다 — 수치만 있고 입력이 없으면 근거가 못 된다.
        "fixture_digests": fixture_digests(),
        "rooms": {
            slug: {
                "summary": room["summary"],
                "rounds": [
                    {
                        "repeat": r["repeat"],
                        "round_index": r["round_index"],
                        "excluded_before": r["excluded_before"],
                        "candidates": r["candidates"],
                        "prompt_tokens": r["prompt_tokens"],
                        "completion_tokens": r["completion_tokens"],
                        "seconds": r["seconds"],
                        "error": r["error"],
                        # 이 라운드가 검수를 **안 탔는가**. 없으면 조건이 같아 보이는데 실제로는
                        # 다르다 — #29 ④ 가 이걸 못 세서 근거 없는 숫자를 문서에 적었다.
                        "critique_failed_open": r["critique_failed_open"],
                    }
                    for r in room["rounds"]
                ],
            }
            for slug, room in payload["rooms"].items()
        },
    }
    if note:
        snapshot["_note"] = note
    return snapshot


def main() -> None:
    parser = argparse.ArgumentParser(description="러너 결과를 동결 스냅샷으로 (크레딧 0)")
    parser.add_argument(
        "--room", action="store_true", help="방 단위 러너(run_room_eval)의 export 를 읽는다"
    )
    parser.add_argument("--run", action="append", default=[], help="동결할 실행 이름. 여러 번 가능")
    parser.add_argument("--all", action="store_true", help="export 의 실행을 전부 동결한다")
    parser.add_argument("--date", help="파일 이름과 measured_at 에 쓸 날짜 (YYYY-MM-DD)")
    parser.add_argument("--note", default=None, help="이 실행에만 붙일 메모")
    parser.add_argument("--list", action="store_true", help="export 의 실행 이름만 출력하고 끝")
    args = parser.parse_args()

    export_path = ROOM_OUTPUT_PATH if args.room else OUTPUT_PATH
    if not export_path.exists():
        raise SystemExit(f"러너 결과가 없다: {export_path}")
    export = json.loads(export_path.read_text(encoding="utf-8"))

    if args.list:
        for name in export:
            print(name)
        return

    targets = list(export) if args.all else args.run
    if not targets:
        raise SystemExit("--run 이나 --all 중 하나가 필요하다 (--list 로 이름 확인)")
    if not args.date:
        raise SystemExit("--date 가 필요하다 (예: --date 2026-08-01)")

    for run_name in targets:
        if run_name not in export:
            raise SystemExit(f"export 에 '{run_name}' 이 없다. --list 로 확인할 것")
        payload = export[run_name]
        if args.room:
            path = SNAPSHOT_DIR / f"{args.date}_room_{slugify(run_name)}.json"
            snapshot = build_room(run_name, payload, args.date, args.note)
            path.write_text(
                json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            for slug, room in snapshot["rooms"].items():
                # 카테고리 종수는 -243 에서 사라졌다. 옛 스냅샷을 다시 얼릴 때만 있다.
                cats = room["summary"].get("categories")
                extra = (
                    f" · 카테고리 {cats['kinds']}종(안 접힌 것 {cats['new_kinds']})" if cats else ""
                )
                print(f"{path.name}  {slug}: 후보 {room['summary']['total_candidates']}{extra}")
            continue

        if "input" not in payload:
            # 러너에 --input 이 생기기 전 실행이다. 조건을 모르는 채 동결하면 근거가 못 된다.
            raise SystemExit(
                f"'{run_name}' 은 조건 필드(input)가 없는 옛 실행이다. 동결하지 않는다."
            )
        path = SNAPSHOT_DIR / f"{args.date}_{slugify(run_name)}.json"
        snapshot = build(run_name, payload, args.date, args.note)
        path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        s = snapshot["summary"]
        print(f"{path.name}  후보 {s['candidates']} · 새 카테고리 {s['new_categories']}")


if __name__ == "__main__":
    main()
