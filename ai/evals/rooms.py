"""얼린 방 픽스처 로더 — **운영이 실제로 보내는 요청 그대로다.**

`dataset.py` 가 자료 1건짜리 케이스를 읽는다면 이쪽은 **방 하나 전체**를 읽는다. 둘을 나눈
이유는 재는 질문이 다르기 때문이다 — 저쪽은 "이 자료가 어떤 후보를 낳나"(귀속), 이쪽은
"사용자가 추천 버튼을 눌렀을 때 무엇을 보나"(운영 재현).

## 픽스처는 캡처한 것이지 만든 것이 아니다

`data/rooms/*.json` 의 `request` 는 Spring 이 `POST /v1/todo-suggestions` 로 보낸 본문을
프록시로 받아 적은 것이다. **SQL 로 다시 뽑지 않았다** —
`TodoSuggestionPayloadLoader.pickContent`(요약·본문 중 짧은 쪽)와 태그·좋아요 조인을
파이썬으로 재구현하면 그 재구현이 어긋나는 순간 측정 전체가 조용히 틀어진다.

스냅샷(`data/snapshots/`)과 같은 취급이다 — **손으로 고치지 않는다.**
"""

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from modi_ai.schemas import SuggestionRequest

ROOM_DIR = Path(__file__).parent / "data" / "rooms"


@dataclass(frozen=True)
class RoomFixture:
    """방 하나의 캡처본. `request` 는 파싱된 것이고 나머지는 출처 기록이다."""

    slug: str
    room_label: str
    captured_at: str
    request: SuggestionRequest

    @property
    def summary(self) -> str:
        r = self.request
        return (
            f"{self.slug}({self.room_label}) — 자료 {len(r.archive)}건 · "
            f"기존 투두 {len(r.existing_todos)}개 · "
            f"캡처 당시 제외 {len(r.excluded_todos)}개"
        )


def available_slugs() -> list[str]:
    return sorted(path.stem for path in ROOM_DIR.glob("*.json"))


@lru_cache
def load_room(slug: str) -> RoomFixture:
    """픽스처 하나. **없으면 조용히 넘어가지 않고 죽는다.**

    `run_suggest_eval.resolve_content` 가 요약 파일에 대해 그렇게 하는 것과 같은 이유다 —
    폴백하면 리포트에는 "방 데이터로 쟀다" 가 남는데 실제로는 아니게 된다. 크레딧을 쓰고
    나서 그걸 깨닫는 것이 최악이라 **호출 전에** 죽어야 한다.
    """
    path = ROOM_DIR / f"{slug}.json"
    if not path.exists():
        raise SystemExit(
            f"방 픽스처가 없다: {path}. 있는 것: {available_slugs() or '(하나도 없음)'}"
        )
    payload = json.loads(path.read_text(encoding="utf-8"))
    return RoomFixture(
        slug=slug,
        room_label=payload["room_label"],
        captured_at=payload["captured_at"],
        request=SuggestionRequest.model_validate(payload["request"]),
    )


def load_rooms(slugs: list[str] | None = None) -> list[RoomFixture]:
    return [load_room(slug) for slug in (slugs if slugs is not None else available_slugs())]
