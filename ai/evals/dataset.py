"""평가용 자료 로더.

`data/archives/*.txt` 는 실제 인스타/블로그 캡션 15개다(Mattermost 공유 덤프에서 수집).
**정답 라벨은 없다** — 프로토타입에서 딸려 온 라벨은 태깅용이었고, 추천 평가에 갖다 쓰다가
잘못된 결론을 냈다(`docs/EXPERIMENTS.md` "다시 하지 말 것"). 무엇을 재야 할지 정한 뒤에
추천 전용 라벨을 새로 만든다.

지금 이 자료들의 용도는 **"실제 모델이 뭘 내는지 눈으로 보는 것"** 이다.
"""

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

DATA_DIR = Path(__file__).parent / "data"
ARCHIVE_DIR = DATA_DIR / "archives"
SNAPSHOT_DIR = DATA_DIR / "snapshots"


@dataclass(frozen=True)
class EvalCase:
    """자료 1건. 파일 이름과 본문뿐이다."""

    stem: str
    text: str

    @property
    def title(self) -> str:
        """자료 제목 대용. 평가셋은 크롤링을 거치지 않아 og:title 이 없다."""
        return self.stem


@lru_cache
def load_cases() -> tuple[EvalCase, ...]:
    return tuple(
        EvalCase(stem=path.stem, text=path.read_text(encoding="utf-8"))
        for path in sorted(ARCHIVE_DIR.glob("*.txt"))
    )


@dataclass(frozen=True)
class SnapshotCandidate:
    title: str
    source_item_id: int | None

    category: str | None = None
    """옛 스냅샷 전용 — AI 가 카테고리를 정하던 시절의 값이다(에서 소멸).

    **기본값을 둔 이유**: 로더가 옛 스냅샷과 새 스냅샷을 **둘 다** 읽어야 한다. 필수 키로
    두면 -243 이후에 얼린 파일이 `KeyError` 로 안 읽힌다.
    """


@dataclass(frozen=True)
class SnapshotCase:
    stem: str
    raw_candidate_count: int
    """필터 **전** 후보 개수."""

    candidates: tuple[SnapshotCandidate, ...]


@lru_cache
def load_snapshot(name: str) -> tuple[SnapshotCase, ...]:
    """동결 스냅샷 로더 — 특정 시점 모델 출력을 고정해둔 것.

    가변 `suggest_eval_export.json` 은 커밋하지 않으므로(실행마다 덮어써진다), 나중에 지표를
    새로 정의했을 때 **"그때 모델이 실제로 뭘 냈는가"** 를 다시 채점할 방법이 필요하다.
    그래서 후보 텍스트만 날짜·모델이 박힌 파일로 동결해 커밋한다.

    스냅샷은 **손으로 고치지 않는다.**
    """
    payload = json.loads((SNAPSHOT_DIR / name).read_text(encoding="utf-8"))
    return tuple(
        SnapshotCase(
            stem=case["stem"],
            raw_candidate_count=case["raw_candidate_count"],
            candidates=tuple(
                SnapshotCandidate(
                    title=c["title"],
                    source_item_id=c["source_item_id"],
                    category=c.get("category"),
                )
                for c in case["candidates"]
            ),
        )
        for case in payload["cases"]
    )
