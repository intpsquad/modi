"""프롬프트에 실을 자료의 순위 — 가중 순위 정규화.

`suggest.py` 에서 떼어낸 이유는 **여기에 LLM 도 네트워크도 없기 때문**이다. 순수 계산이라
입력을 손으로 만들어 그대로 검증할 수 있고, `suggest.py` 는 이미 600줄이 넘는다.

## 무엇을 하는가

방의 자료를 네 축으로 각각 줄 세우고, 각 축의 등수를 **1등 = 1.0 · 꼴찌 = 0.0** 으로 편 뒤
가중합한다.

    점수 = Σ  wᵢ × (꼴찌등수ᵢ − 등수ᵢ) / (꼴찌등수ᵢ − 1등수ᵢ)

축과 가중치는 사용자가 확정했다(2026-08-01, `docs/DECISIONS.md`):

| 축 | 가중치 | 신호 |
|---|---|---|
| 좋아요 | 3.0 | 팀이 좋다고 한 것 |
| 핀 | 2.5 | 계속 보겠다는 것 |
| 유사도 | 2.0 | 방 목표와 의미가 가까운 것 |
| 최근성 | 1.0 | 방금 담은 것 |

**점수를 직접 가중합하지 않는 이유**는 세 축의 스케일이 전혀 다르기 때문이다(코사인 0~1 ·
경과일수 · 정수 카운트). 등수만 쓰면 정규화 상수가 근거 없이 코드에 남지 않는다 — 여기서 나누는
값은 임의 상수가 아니라 **그 축에서 관측된 등수 범위**다.

## ⚠️ 원래 RRF 였다 — 실측으로 뒤집었다 (2026-08-02, `docs/EXPERIMENTS.md` #22)

확정 설계는 `Σ wᵢ/(k + 등수ᵢ)`, k=60 의 **가중 RRF** 였다. 구현 중에 재보니 **사용자가 고른
가중치 순서를 정반대로 뒤집었다.**

실서버 방(자료 17건, 핀 0건, **좋아요 1건**)에서 가장 오래된 자료에 좋아요를 눌렀을 때:

| 융합 | 그 자료의 등수 |
|---|---|
| RRF k=60 | **16등** (17등에서 한 칸) |
| RRF k=1 | 4등 |
| 순위 정규화 | **2등** |

축별 변별력(1등 점수 − 꼴찌 점수)으로 보면 원인이 분명하다:

| 융합 | 좋아요 | 핀 | 유사도 | 최근성 |
|---|---|---|---|---|
| RRF k=60 | 0.0008 | 0.0007 | **0.0068** | 0.0034 |
| 순위 정규화 | **3.0** | **2.5** | **2.0** | **1.0** |

RRF 의 변별력은 가중치 × **그 축의 단계 수**에 좌우된다. 좋아요·핀은 사실상 2단계(1/0)이고
유사도·최근성은 17단계라, 2단계 축은 17단계 축을 **k 를 아무리 낮춰도 못 이긴다**(k=0 에서도
유사도 1.88 > 좋아요 1.50). 즉 튜닝 문제가 아니라 구조 문제였다.

순위 정규화는 축마다 범위를 [0,1] 로 펴므로 **변별력이 곧 가중치**가 된다. RRF 를 골랐던 원래
근거("스케일이 달라 정규화 상수가 남는다")는 그대로 지켜진다.

## 동점은 반드시 같은 등수다 (competition ranking)

`docs/DECISIONS.md` 가 경고한 지점이다. 실서버 자료 17건 중 **핀 0건 · 좋아요 1건**이라
16건이 전부 0으로 동점인데, 이걸 억지로 1·2·3등으로 줄 세우면 **그 순서는 정렬 방식이 우연히
정한 것**이고 거기에 최대 가중치가 걸린다. 동점으로 묶으면 그 축의 기여가 전원 동일해져
**신호가 없을 때 축이 조용히 빠진다.**

⚠️ **"좋아요가 쌓일수록 축이 세지는" 것은 아니다**(리뷰 지적). 축은 **완전히 꺼지거나(전원
동점) 가중치만큼 완전히 켜지거나** 둘 중 하나다 — 좋아요 1건짜리 방에서 그 1건은 이미 만점
3.0 을 받는다. 데이터가 쌓이면서 변하는 것은 세기가 아니라 **해상도**(그 3.0 이 몇 단계로
나뉘는가)다.

같은 이유로 **크기 차이는 사라진다**: `좋아요 [100, 99, 1, 0]` → 점수 `[3.0, 2.0, 1.0, 0.0]`.
좋아요 1개가 100개의 3분의 1을 받는다. 순위 융합의 본질적 성질이고 RRF 도 마찬가지였다 —
값의 크기를 살리려면 순위가 아니라 점수를 써야 하는데, 그러면 스케일 정규화 문제가 돌아온다.

## 값이 없는 축은 "중립"이다 — 꼴찌가 아니다

임베딩이 없는 자료(`V7` 주석의 정상 4경우)나 `created_at` 이 없는 자료는 그 축에서 **한가운데
(`NEUTRAL` = 0.5)** 를 받는다. `DECISIONS.md`·`V7` 이 약속한 *"유사도 축에서**만** 빠지고 나머지
축으로 후보에 남는다"* 가 이 뜻이다 — 모르는 것에 상도 벌도 주지 않는다.

⚠️ **처음엔 꼴찌를 줬다가 리뷰에서 잡혔다.** 왜 위험한지는 `NEUTRAL` 상수의 주석에 있다.
요지: 벡터가 있는 자료와 없는 자료가 섞이면 "벡터가 있다"는 사실이 유사도 등수 차이를 압도해
유사도 축이 **최근성의 복사본**이 되고, 가중치 순서가 다시 뒤집힌다.

목표 임베딩이 실패하면 전원이 값 없음이 되어 **유사도 축이 통째로 빠진다** — 분기를 따로 두지
않아도 그렇게 된다.
"""

import logging
import math
from collections import Counter
from collections.abc import Callable
from datetime import UTC, datetime

from modi_ai.schemas import ArchiveItemInput

log = logging.getLogger(__name__)

WEIGHT_LIKES = 3.0
WEIGHT_PINNED = 2.5
WEIGHT_SIMILARITY = 2.0
WEIGHT_RECENCY = 1.0


def cosine(a: list[float], b: list[float]) -> float:
    """코사인 유사도. numpy 를 끌어오지 않는다 — 최대 58x8 쌍이라 순수 파이썬으로 충분하다."""
    dot = sum(x * y for x, y in zip(a, b, strict=True))
    na = sum(x * x for x in a) ** 0.5
    nb = sum(y * y for y in b) ** 0.5
    if na == 0.0 or nb == 0.0:
        return 0.0
    return dot / (na * nb)


def competition_ranks(values: list[float | None]) -> list[int | None]:
    """큰 값이 1등. **동점은 같은 등수**(1·2·2·4 — dense 가 아니라 competition).

    `None`(그 축에 값이 없음)은 **등수를 받지 않는다.** 등수를 안 주는 것과 꼴찌를 주는 것은
    전혀 다르고, 그 차이가 실제로 사고를 냈다 — 모듈 docstring 의 "값이 없는 축" 절 참고.
    """
    counts = Counter(v for v in values if v is not None)
    rank_of: dict[float, int] = {}
    running = 1
    for value in sorted(counts, reverse=True):
        rank_of[value] = running
        running += counts[value]
    return [None if v is None else rank_of[v] for v in values]


def _similarity(embedding: list[float] | None, goal: list[float] | None) -> float | None:
    """`None` 이면 그 자료는 유사도 축에서 **중립**(`NEUTRAL`, 아래 참고)을 받는다.

    ⚠️ **꼴찌가 아니다.** 이 문장이 원래 "꼴찌 동점"이라고 적혀 있었고, 코드도 그랬다가
    리뷰에서 잡혀 고쳤다(2026-08-02). 꼴찌는 중립이 아니라 가중치만큼의 감점이라, 벡터가
    `V7` 이후 등록분에만 있는 방에서 **"벡터 있음 ≈ 최신"** 이 되어 유사도 축이 최근성의
    복사본이 됐다. 이유는 `NEUTRAL` 설명에 있다 — **되돌리기 전에 그것부터 읽을 것.**

    차원이 다르면 계산하지 않는다 — `V7` 주석이 "섞인 차원은 읽는 쪽에서 걸러야 한다"고 적어둔
    그 처리다. 임베딩 모델을 바꾸면 옛 벡터가 남아 실제로 섞인다.
    """
    if embedding is None or goal is None:
        return None
    if len(embedding) != len(goal):
        log.warning("임베딩 차원 불일치 — 유사도 축에서 제외: %d vs %d", len(embedding), len(goal))
        return None
    score = cosine(embedding, goal)
    if not math.isfinite(score):
        # `real[]` 는 'NaN'::real 을 저장할 수 있다. NaN 은 sorted(reverse=True) 에서 맨 앞으로
        # 가버려 **1등을 먹는다** — 값이 없는 것으로 취급하는 편이 안전하다.
        log.warning("유사도가 유한하지 않다 — 축에서 제외: %r", score)
        return None
    return score


def _recency(created_at: datetime | None) -> float | None:
    """정렬 가능한 수로 바꾼다. naive datetime 은 UTC 로 본다 — 섞이면 비교가 터진다."""
    if created_at is None:
        return None
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=UTC)
    return created_at.timestamp()


NEUTRAL = 0.5
"""값이 없는 자료가 그 축에서 받는 위치. **1등도 꼴찌도 아닌 한가운데다.**

⚠️ 원래 꼴찌를 줬다가 **리뷰에서 잡혀 고쳤다**(2026-08-02). 꼴찌는 중립이 아니라 가중치만큼의
감점이라, 임베딩이 있는 자료와 없는 자료가 섞인 방에서 **"벡터가 있다"는 사실 자체가 유사도
등수 차이보다 큰 이득**이 됐다. 벡터는 `V7`(2026-08-01) 이후 등록분에만 있고 백필은 기본
꺼짐이라 **"벡터 있음 ≈ 최신"** 이다 — 유사도 축이 최근성의 복사본이 되어 실효 최근성 3.0 이
핀 2.5 를 넘었다. **RRF 를 기각한 것과 정확히 같은 종류의 실패**를 다시 낼 뻔했다.
"""


def _axes(
    items: list[ArchiveItemInput], goal: list[float] | None
) -> list[tuple[float, list[int | None]]]:
    return [
        (WEIGHT_LIKES, competition_ranks([float(i.like_count) for i in items])),
        (WEIGHT_PINNED, competition_ranks([float(i.pinned) for i in items])),
        (WEIGHT_SIMILARITY, competition_ranks([_similarity(i.embedding, goal) for i in items])),
        (WEIGHT_RECENCY, competition_ranks([_recency(i.created_at) for i in items])),
    ]


def score_archive(items: list[ArchiveItemInput], goal: list[float] | None) -> list[float]:
    """자료마다 점수. 순서는 입력 그대로 — 정렬은 `rank_archive` 가 한다."""
    if not items:
        # 자료가 없는 방은 정상이다(목표만 보고 제안하는 경로).
        # 아래 min/max 가 빈 리스트에서 터진다.
        return []
    scores = [0.0] * len(items)
    for weight, ranks in _axes(items, goal):
        ranked = [r for r in ranks if r is not None]
        if not ranked:
            # 그 축에 값을 가진 자료가 하나도 없다(예: 목표 임베딩 실패). 축이 통째로 빠진다.
            continue
        best, worst = min(ranked), max(ranked)
        # 값을 가진 것들이 전부 동점이면 신호가 없다 — 전원 중립을 주면 상수라 순서가 안 바뀐다.
        # (0으로 나누는 것도 여기서 막힌다.)
        span = worst - best
        for index, rank in enumerate(ranks):
            if rank is None or span == 0:
                position = NEUTRAL
            else:
                position = (worst - rank) / span
            scores[index] += weight * position
    return scores


def rank_archive(items: list[ArchiveItemInput], goal: list[float] | None) -> list[ArchiveItemInput]:
    """점수 내림차순. **동점이면 입력 순서를 지킨다**(Spring 이 최신순으로 보낸다).

    `sorted` 의 key 에 자료를 넣지 않는 이유는 pydantic 모델에 순서가 없어서다 — 점수가 같으면
    비교하다 `TypeError` 가 난다. 인덱스로 정렬해 안정성을 그대로 쓴다.
    """
    scores = score_archive(items, goal)
    order = sorted(range(len(items)), key=lambda index: -scores[index])
    return [items[index] for index in order]


def _trimmed_to_fit(
    item: ArchiveItemInput,
    budget: int,
    render: Callable[[ArchiveItemInput], str],
) -> ArchiveItemInput:
    """혼자서도 예산을 넘는 자료의 **본문만** 깎아 예산에 맞춘다.

    렌더 내부 구조를 알 필요가 없다 — 본문에서 N자를 빼면 렌더도 정확히 N자 줄기 때문에
    초과분을 그대로 빼면 된다. 본문이 초과분보다 짧으면(= 머리만으로 예산을 넘으면) 본문을
    비우고 머리는 남긴다. **머리를 자르지 않는 것이 중요하다** — `## id=` 가 깨지면 모델이
    근거 자료 id 를 인용할 수 없고, `filter_candidates` 가 후보를 전부 버려 추천이 조용히
    빈 목록이 된다.
    """
    overflow = len(render(item)) - budget
    if overflow <= 0 or not item.content:
        return item
    return item.model_copy(update={"content": item.content[: max(len(item.content) - overflow, 0)]})


def order_by_recency(items: list[ArchiveItemInput]) -> list[ArchiveItemInput]:
    """최신순(`created_at` 내림차순). 값이 없는 자료는 **뒤로** 보낸다.

    **Spring 이 이미 최신순으로 보낸다는 사실에 기대지 않고 여기서 다시 정렬한다.**
    `rank_archive` 는 동점 처리에서만 그 순서에 기댔지만(안정 정렬), 최신순이 **선별 기준**이
    되는 순간 얘기가 다르다 — 상류가 정렬을 바꾸면 프롬프트에서 조용히 엉뚱한 자료가 잘린다.
    여기서 정렬하면 그 계약이 이 파일 안에서 닫힌다.

    `sorted` 의 key 로 자료가 아니라 인덱스를 쓰는 이유는 `rank_archive` 와 같다 — pydantic
    모델에는 순서가 없어 값이 같으면 비교하다 `TypeError` 가 난다.
    """
    stamps = [_recency(item.created_at) for item in items]
    order = sorted(
        range(len(items)),
        # None 은 정렬 키가 될 수 없다. (있음=0, 없음=1) 를 앞에 둬 없는 것을 뒤로 보낸다.
        key=lambda index: (stamps[index] is None, -(stamps[index] or 0.0)),
    )
    return [items[index] for index in order]


def select_archive(
    items: list[ArchiveItemInput],
    goal: list[float] | None,
    budget: int,
    render: Callable[[ArchiveItemInput], str],
    by_recency: bool = False,
) -> list[ArchiveItemInput]:
    """순서를 정하고, 누적 렌더 길이가 `budget` 을 넘는 **뒤쪽만** 버린다.

    순서는 둘 중 하나다(`config.archive_select_by_recency`):
      · `by_recency=True` — 최신순. **운영 기본값**(2026-08-09). `goal` 을 쓰지 않으므로
        호출부가 목표 임베딩 왕복을 통째로 건너뛸 수 있다(`suggest._select_archive`).
      · `by_recency=False` — 4축 가중 순위(`rank_archive`). 이전 동작.

    ⚠️ **예산이 이제 상시 발동한다.** 원래 12,000 자는 "발동하지 않는 크기"였는데 3,000 으로
    내려오면서(시연 지연 목표) 자료 15건 넘는 방에서는 항상 뒤쪽이 잘린다. 그래서 **무엇이
    먼저 오는가**가 처음으로 결과를 바꾼다 — `by_recency` 가 생긴 이유다.

    `render` 를 주입받는 이유는 **예산을 세는 문자열이 실제로 보내는 문자열과 같아야 하기
    때문**이다(`suggest.render_archive_item`). 여기서 따로 세면 렌더를 고칠 때 갈라진다.

    **안 들어가는 자료를 만나도 멈추지 않고 계속 본다.** ⚠️ 원래 "예산을 넘는 첫 자료에서
    `break`" 였는데 리뷰에서 잡혔다: 요약이 없는 자료는 본문 전체가 실리므로
    (`TodoSuggestionPayloadLoader.pickContent` — 요약이 `null` 인 정상 경우가 셋 있다)
    **거대한 자료 1건이 1등을 하면 나머지 전부가 프롬프트에서 사라졌다.**

    **하나도 안 들어가면 1등 하나만 남긴다.** 자료가 없는 프롬프트는 추천을 통째로 무의미하게
    만들고 그 경우 사용자가 할 수 있는 일이 없다. 이 폴백을 루프 안이 아니라 **루프 뒤**에
    두는 것이 중요하다 — 안에 두면 예산을 넘긴 그 1건이 남은 자리를 다 먹어 위 문제가 그대로다.

    **자르는 일은 그 폴백 안에서만 한다.** 여기가 남은 예산을 아는 유일한 자리다. `render` 쪽에
    상한을 두면 거대한 자료가 정확히 예산만큼이 되어 위 `continue` 를 **통과해버린다**(실측:
    자료 18건 중 1건만 남았다 — 2026-08-02 리뷰). 자르는 양은 렌더 길이의 초과분 그대로다:
    본문에서 N자를 빼면 렌더도 정확히 N자 준다. 머리(`## id=`)는 남는다 — 그게 없으면 모델이
    근거 id 를 인용할 수 없어 `filter_candidates` 가 후보를 전부 버린다.
    """
    ranked = order_by_recency(items) if by_recency else rank_archive(items, goal)
    kept: list[ArchiveItemInput] = []
    used = 0
    for item in ranked:
        cost = len(render(item))
        if used + cost > budget:
            continue
        kept.append(item)
        used += cost

    if not kept and ranked:
        kept = [_trimmed_to_fit(ranked[0], budget, render)]
        used = len(render(kept[0]))

    if len(kept) < len(ranked):
        log.info(
            "자료 선별: %d건 중 %d건만 싣는다 (누적 %d자 / 예산 %d자)",
            len(items),
            len(kept),
            used,
            budget,
        )
    return kept
