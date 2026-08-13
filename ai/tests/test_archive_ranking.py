"""자료 순위 — 가중 순위 정규화.

여기서 지키려는 것은 하나다: **사용자가 고른 가중치 순서(좋아요 3.0 > 핀 2.5 > 유사도 2.0 >
최근성 1.0)가 실제 데이터 분포에서 그대로 나타나는 것.** 확정 설계였던 RRF 가 바로 이걸
못 지켜서 융합 방식을 뒤집었다(`ranking.py` docstring, `docs/EXPERIMENTS.md` #22).
"""

from datetime import UTC, datetime, timedelta

from modi_ai.ranking import (
    competition_ranks,
    rank_archive,
    score_archive,
    select_archive,
)
from modi_ai.schemas import ArchiveItemInput

BASE = datetime(2026, 7, 1, tzinfo=UTC)


def item(
    id: int,
    *,
    likes: int = 0,
    pinned: bool = False,
    embedding: list[float] | None = None,
    age_days: int = 0,
) -> ArchiveItemInput:
    return ArchiveItemInput(
        id=id,
        title=f"자료{id}",
        content="본문",
        like_count=likes,
        pinned=pinned,
        embedding=embedding,
        created_at=BASE - timedelta(days=age_days),
    )


def ids(items: list[ArchiveItemInput]) -> list[int]:
    return [i.id for i in items]


class TestCompetitionRanks:
    """동점 처리. `DECISIONS.md` 가 "이 처리 없이 가중치를 크게 주면 안 된다"고 경고한 지점이다."""

    def test_ties_share_a_rank_and_skip_the_next(self):
        # competition ranking 이다 — dense(1,1,2)가 아니라 1,1,3.
        assert competition_ranks([5.0, 5.0, 3.0]) == [1, 1, 3]

    def test_single_liked_item_leaves_everyone_else_tied(self):
        # 실서버 분포. 좋아요 0인 16건이 서로 다른 등수를 받으면 안 된다.
        values = [1.0] + [0.0] * 16
        assert competition_ranks(values) == [1] + [2] * 16

    def test_missing_values_get_no_rank(self):
        # 꼴찌를 주면 안 된다 — 꼴찌는 중립이 아니라 감점이다(TestMissingValuesAreNeutral).
        assert competition_ranks([1.0, None, None]) == [1, None, None]

    def test_all_missing_get_no_rank(self):
        # 목표 임베딩 실패 → 그 축이 통째로 빠지는 근거.
        assert competition_ranks([None, None, None]) == [None, None, None]


class TestWeightOrderHolds:
    """**이 클래스가 이 티켓의 핵심이다.** RRF 는 여기를 통과하지 못했다."""

    def test_one_like_beats_pin_beats_similarity_beats_recency(self):
        # 네 자료가 각각 한 축에서만 1등이고 나머지 축에서는 꼴찌다.
        # 점수는 정확히 그 축의 가중치가 되므로 순서가 곧 가중치 순서여야 한다.
        goal = [1.0, 0.0]
        items = [
            item(1, likes=1, age_days=9),
            item(2, pinned=True, age_days=9),
            item(3, embedding=[1.0, 0.0], age_days=9),
            item(4, age_days=0),
        ]
        # 유사도 축에 꼴찌를 만들려면 나머지도 벡터가 있어야 한다(없으면 동점 꼴찌).
        items[0].embedding = [0.0, 1.0]
        items[1].embedding = [0.0, 1.0]
        items[3].embedding = [0.0, 1.0]

        assert ids(rank_archive(items, goal)) == [1, 2, 3, 4]

    def test_a_single_like_lifts_the_oldest_item_to_the_front(self):
        """실서버 분포(17건 · 핀 0 · 좋아요 1)에서 좋아요가 실제로 효과가 있어야 한다.

        RRF k=60 에서는 이 자료가 **16등**이었다 — 17등에서 한 칸. 그래서 융합을 바꿨다.
        """
        goal = [1.0, 0.0]
        items = [item(i, age_days=i, embedding=[1.0, i / 100]) for i in range(17)]
        items[16].like_count = 1  # 가장 오래되고 가장 덜 유사한 자료

        assert 16 in ids(rank_archive(items, goal))[:2]

    def test_likes_outrank_pins_at_equal_standing(self):
        goal = [1.0, 0.0]
        liked = item(1, likes=1, embedding=[1.0, 0.0], age_days=1)
        pinned = item(2, pinned=True, embedding=[1.0, 0.0], age_days=1)

        assert ids(rank_archive([pinned, liked], goal)) == [1, 2]


class TestAxisDropsOutWhenThereIsNoSignal:
    def test_pin_axis_is_silent_when_nothing_is_pinned(self):
        # 핀 0건이 실서버 상태다. 이 축이 점수에 아무 기여도 하면 안 된다.
        goal = [1.0, 0.0]
        items = [
            item(1, age_days=1, embedding=[1.0, 0.0]),
            item(2, age_days=0, embedding=[1.0, 0.0]),
        ]
        without_pins = score_archive(items, goal)

        for i in items:
            i.pinned = True
        with_pins_everywhere = score_archive(items, goal)

        assert without_pins == with_pins_everywhere

    def test_similarity_axis_is_silent_when_the_goal_vector_is_missing(self):
        """목표 임베딩 호출이 실패한 경우. 나머지 세 축으로 순서가 나와야 한다."""
        items = [item(1, age_days=5, embedding=[1.0, 0.0]), item(2, likes=1, age_days=0)]

        assert ids(rank_archive(items, goal=None)) == [2, 1]


class TestMissingValuesAreNeutral:
    """⚠️ **이 클래스는 실제 회귀를 막는다.** 리뷰에서 잡힌 P2 다.

    값이 없는 축을 **꼴찌**로 처리했더니, 벡터가 있는 자료와 없는 자료가 섞인 방에서
    **"벡터가 있다"는 사실 자체가 유사도 등수 차이를 압도**했다. 벡터는 `V7`(2026-08-01)
    이후 등록분에만 있고 백필은 기본 꺼짐이라 **벡터 있음 ≈ 최신**이다 — 유사도 축이
    최근성의 복사본이 되어 실효 최근성 3.0 이 핀 2.5 를 넘었다. **RRF 를 기각한 것과 같은
    종류의 실패**다.
    """

    def test_a_known_bad_similarity_ranks_below_an_unknown_one(self):
        """**이 클래스에서 `NEUTRAL` 을 실제로 고정하는 유일한 테스트다.**

        ⚠️ **순서가 아니라 점수를 단언한다.** 원래 `ids(...) == [1, 2, 3]` 이었는데,
        `NEUTRAL = 0.0` 으로 되돌리면 unknown 과 worst 가 **동점(0.0)** 이 되고 안정 정렬이
        입력 순서를 지켜 **같은 순서가 나온다** — 즉 회귀를 못 잡는다. 점수로 보면
        `[2.0, 0.0, 0.0]` 이라 부등식이 깨진다.
        """
        goal = [1.0, 0.0]
        best = item(1, embedding=[1.0, 0.0])
        unknown = item(2, embedding=None)
        worst = item(3, embedding=[0.0, 1.0])

        scores = score_archive([best, unknown, worst], goal)

        assert scores[0] > scores[1] > scores[2], scores

    def test_an_unknown_similarity_does_not_sink_below_a_known_bad_one(self):
        """위와 같은 회귀를 순서로도 한 번 더 본다 — unknown 을 **입력 맨 뒤**에 둔다.

        맨 뒤에 두어야 동점일 때 안정 정렬이 unknown 을 뒤로 보낸다. 앞에 두면 꼴찌로
        떨어져도 순서가 그대로라 통과해버린다(위 docstring 참고).
        """
        goal = [1.0, 0.0]
        items = [
            item(1, embedding=[1.0, 0.0]),
            item(3, embedding=[0.0, 1.0]),
            item(2, embedding=None),
        ]

        assert ids(rank_archive(items, goal)) == [1, 2, 3]


class TestAnAxisWithNoSpreadDropsOut:
    """벡터 유무가 순서를 지배하지 않는지.

    ⚠️ **이 클래스는 `NEUTRAL` 값을 고정하지 않는다.** 두 경우 모두 값이 있는 자료들끼리
    **전원 동점**이라 유사도 축의 `span` 이 0이고, 그러면 전원이 같은 값을 받아 축이 통째로
    빠진다 — `NEUTRAL` 이 무엇이든 결과가 같다. 원래 이 두 테스트가
    `TestMissingValuesAreNeutral` 안에 있어서 "회귀를 막는다"고 읽혔는데, 측정해보니
    `NEUTRAL` 을 바꿔도 통과했다(2026-08-02 리뷰). 실제 가드는 그 클래스에 있다.
    """

    def test_having_a_vector_does_not_by_itself_beat_a_pin(self):
        goal = [1.0, 0.0]
        # 목표와 거의 무관한 벡터(코사인 ≈ 0)를 가진 자료 vs 벡터가 없고 핀이 꽂힌 자료.
        has_useless_vector = item(1, embedding=[0.0, 1.0], age_days=0)
        pinned_no_vector = item(2, pinned=True, embedding=None, age_days=0)

        assert ids(rank_archive([has_useless_vector, pinned_no_vector], goal)) == [2, 1]

    def test_a_mostly_unembedded_room_does_not_let_the_vectors_take_the_top(self):
        """`V7` 이후 등록분 5건 + 이전 등록분 12건. 벡터 유무가 순서를 지배하면 안 된다.

        벡터 5건이 **서로 방향이 같아서** 유사도 축이 꺼진다는 점이 이 케이스의 핵심이다.
        방향을 서로 다르게 주면 유사도(2.0)가 최근성(1.0)을 이겨 벡터 있는 자료가 상위에
        올라오는 것이 **정상**이다 — 그건 회귀가 아니다.
        """
        goal = [1.0, 0.0]
        # 벡터 있는 5건을 **가장 오래된 쪽**에 두고, 목표와 무관한 같은 방향을 준다.
        items = [item(i, embedding=None, age_days=i) for i in range(12)]
        items += [item(12 + i, embedding=[0.0, 1.0], age_days=12 + i) for i in range(5)]

        top5 = ids(rank_archive(items, goal))[:5]

        assert all(i < 12 for i in top5), f"벡터 있는 자료가 상위를 먹었다: {top5}"


class TestItemsWithoutAnEmbeddingSurvive:
    """`V7` 주석: NULL 인 자료는 유사도 축에서만 빠지고 나머지 축으로 후보에 남는다."""

    def test_item_without_embedding_is_not_dropped(self):
        goal = [1.0, 0.0]
        items = [item(1, embedding=[1.0, 0.0]), item(2, embedding=None)]

        assert sorted(ids(rank_archive(items, goal))) == [1, 2]

    def test_item_without_embedding_still_wins_on_likes(self):
        goal = [1.0, 0.0]
        items = [item(1, embedding=[1.0, 0.0]), item(2, embedding=None, likes=5)]

        assert ids(rank_archive(items, goal))[0] == 2

    def test_mismatched_dimensions_are_excluded_not_crashed(self):
        # 임베딩 모델을 바꾸면 옛 벡터가 남는다. zip(strict=True) 가 터지면 추천 전체가 죽는다.
        goal = [1.0, 0.0]
        items = [item(1, embedding=[1.0, 0.0, 0.0]), item(2, embedding=[1.0, 0.0])]

        assert sorted(ids(rank_archive(items, goal))) == [1, 2]

    def test_a_nan_vector_does_not_take_first_place(self):
        """`real[]` 는 `'NaN'::real` 을 저장할 수 있고, NaN 은 내림차순 정렬에서 맨 앞으로 간다.

        유사도 축에 실제 폭이 있어야 이 회귀가 드러난다 — 값이 하나뿐이면 전원 중립이라
        NaN 이 앞에 와도 점수가 같아 통과해버린다.
        """
        goal = [1.0, 0.0]
        nan_vector = item(1, embedding=[float("nan"), 0.0])
        best = item(2, embedding=[1.0, 0.0])
        worst = item(3, embedding=[0.0, 1.0])

        # NaN 은 "값 없음"으로 취급돼 중립이므로 진짜 1등과 꼴찌 사이에 놓인다.
        assert ids(rank_archive([nan_vector, best, worst], goal)) == [2, 1, 3]


class TestStableOrder:
    def test_equal_scores_keep_the_incoming_order(self):
        # Spring 이 최신순으로 보낸다. 점수가 같으면 그 순서가 유지돼야 한다.
        goal = None
        items = [item(1), item(2), item(3)]

        assert ids(rank_archive(items, goal)) == [1, 2, 3]

    def test_empty_input(self):
        assert rank_archive([], goal=None) == []


class TestSelectArchive:
    """예산 자르기 자체. 순서는 **순위 모드**(기본 인자)로 고정해서 본다.

    ⚠️ 2026-08-09 이전에는 이 클래스 설명이 "예산은 안전밸브다 — 지금 규모에서는 발동하지
    않아야 한다"였다. 예산이 3,000 으로 내려오며 상시 발동으로 성격이 바뀌어 지웠다.
    최신순 선별은 `TestRecencySelection` 이 본다.
    """

    def test_nothing_is_dropped_when_everything_fits(self):
        items = [item(i, age_days=i) for i in range(17)]

        kept = select_archive(items, goal=None, budget=100_000, render=lambda i: i.title)

        assert len(kept) == 17

    def test_tail_is_dropped_when_over_budget(self):
        items = [item(i, likes=17 - i, age_days=i) for i in range(17)]

        # 자료 1건당 10자로 렌더한다고 치면 예산 35자에는 3건만 들어간다.
        kept = select_archive(items, goal=None, budget=35, render=lambda i: "x" * 10)

        assert len(kept) == 3

    def test_the_dropped_ones_are_the_lowest_ranked(self):
        items = [item(1, age_days=0), item(2, likes=9, age_days=1)]

        kept = select_archive(items, goal=None, budget=10, render=lambda i: "x" * 10)

        assert ids(kept) == [2]

    def test_the_first_item_survives_even_if_it_alone_blows_the_budget(self):
        # 자료가 하나도 없는 프롬프트는 추천을 통째로 무의미하게 만든다.
        items = [item(1)]

        kept = select_archive(items, goal=None, budget=1, render=lambda i: "x" * 999)

        assert ids(kept) == [1]

    def test_one_huge_item_does_not_silence_everything_after_it(self):
        """⚠️ 리뷰에서 잡힌 P2. 원래 `break` 라 거대한 1건이 나머지를 전부 지웠다.

        요약이 없는 자료는 본문 전체가 실린다(`pickContent` — 요약 `null`이 정상인 경우가 셋).
        그런 자료가 좋아요를 받아 1등이 되면 프롬프트에 자료가 그것 하나만 남았다.
        """
        huge = item(1, likes=9)
        small_a = item(2)
        small_b = item(3)
        render = {1: "x" * 5_000, 2: "y" * 10, 3: "z" * 10}

        kept = select_archive(
            [huge, small_a, small_b], goal=None, budget=100, render=lambda i: render[i.id]
        )

        assert ids(kept) == [2, 3]

    def test_budget_counts_the_string_that_is_actually_sent(self):
        """예산을 세는 렌더와 프롬프트에 들어가는 렌더가 같은 함수여야 한다.

        가짜 렌더로 재면 둘 다 예산 안에 들어간다 — 진짜 렌더를 써야만 500자짜리가 걸린다.
        """
        from modi_ai.suggest import render_archive_item

        long_item = item(1)
        long_item.content = "가" * 500
        small_item = item(2)

        assert len(select_archive([long_item, small_item], None, 100, lambda i: "x")) == 2

        kept = select_archive([long_item, small_item], None, 100, render_archive_item)

        assert ids(kept) == [2]

    def test_the_lone_survivor_is_trimmed_to_fit(self):
        """혼자서도 예산을 넘는 자료는 **본문을 깎아서** 넣는다 — 통째로 통과시키지 않는다.

        예전에는 폴백이 `ranked[:1]` 을 그대로 반환해 프롬프트가 예산의 1.7배가 됐다
        (DB 상한 20,000자 자료 1건 -> 20,369자, 2026-08-02 실측).
        """
        from modi_ai.suggest import render_archive_item

        oversized = item(1)
        oversized.content = "가" * 20_000  # ArchiveTextLimits.MAX_BODY_TEXT

        kept = select_archive([oversized], None, 5_000, render_archive_item)

        assert len(kept) == 1
        assert len(render_archive_item(kept[0])) == 5_000

    def test_the_render_itself_never_truncates(self):
        """⚠️ **`render_archive_item` 에 상한을 넣으면 안 된다.** 한 번 넣었다가 되돌렸다.

        상한을 예산값으로 두면 거대한 자료가 **정확히 예산만큼**이 되어 `select_archive` 의
        `used + cost > budget` 을 통과하고, 그 한 건이 예산을 통째로 먹어 나머지가 전부
        사라진다(자료 18건 -> 1건, 2026-08-02 리뷰). 자르는 일은 남은 예산을 아는
        `_trimmed_to_fit` 이 한다.

        앞서 이 자리에 있던 `test_trimming_keeps_the_id_header` 는 **어떤 변이에도 실패하지
        않았다** — 예산을 `select_archive` 인자로 낮췄는데 막으려는 버그는 설정값을 읽었기
        때문이다. 그래서 렌더를 직접 겨눈다.
        """
        from modi_ai.suggest import render_archive_item

        big = item(42)
        big.content = "가" * 20_000  # ArchiveTextLimits.MAX_BODY_TEXT

        rendered = render_archive_item(big)

        assert rendered.endswith("가" * 20_000), "렌더가 본문을 잘랐다"
        assert "## id=42" in rendered

    def test_a_huge_item_does_not_eat_the_budget_with_the_real_render(self):
        """⚠️ `test_one_huge_item_does_not_silence_everything_after_it` 의 **진짜 렌더** 판.

        그 테스트는 가짜 render 를 주입해서, `render_archive_item` 쪽에 상한을 넣었을 때
        생긴 회귀를 못 잡았다. 상한이 예산값이면 거대한 자료가 **정확히 예산만큼**이 되어
        `used + cost > budget` 을 통과하고, 그 한 건이 예산을 다 먹어 나머지가 전부
        사라진다(실측: 자료 18건 -> 1건, 2026-08-02 리뷰).
        """
        from modi_ai.suggest import render_archive_item

        budget = 12_000
        huge = item(99, likes=1, age_days=99)  # 좋아요로 1등, 하지만 거대하다
        huge.content = "가" * 13_000
        others = [item(i, age_days=i) for i in range(17)]
        for other in others:
            other.content = "나" * 180

        kept = select_archive([huge, *others], None, budget, render_archive_item)

        assert 99 not in ids(kept), "거대한 자료가 예산을 통째로 먹었다"
        assert len(kept) == 17
        assert sum(len(render_archive_item(i)) for i in kept) <= budget


class TestRecencySelection:
    """최신순 선별 (2026-08-09, `config.archive_select_by_recency`).

    예산이 12,000 -> 3,000 으로 내려와 **상시 발동**하게 되면서 "무엇이 먼저 오는가"가 처음으로
    결과를 바꿨다. 시연에서는 직전에 추가한 자료가 반드시 프롬프트에 들어가야 한다.
    """

    def test_newest_first(self):
        # age_days 가 클수록 오래된 자료다.
        items = [item(1, age_days=5), item(2, age_days=0), item(3, age_days=2)]

        kept = select_archive(items, None, 100_000, lambda i: i.title, by_recency=True)

        assert ids(kept) == [2, 3, 1]

    def test_likes_and_pins_no_longer_decide_the_order(self):
        """⚠️ 이번 변경이 **버리는 것**을 명시적으로 못 박는다.

        순위 모드에서는 좋아요 9 + 핀이 1등이지만, 최신순에서는 오래됐다는 이유로 뒤로 간다.
        되돌리고 싶으면 `archive_select_by_recency=False` 다.
        """
        loved_but_old = item(1, likes=9, pinned=True, age_days=30)
        plain_but_new = item(2, age_days=0)

        by_rank = select_archive([loved_but_old, plain_but_new], None, 100_000, lambda i: i.title)
        by_recent = select_archive(
            [loved_but_old, plain_but_new], None, 100_000, lambda i: i.title, by_recency=True
        )

        assert ids(by_rank) == [1, 2]
        assert ids(by_recent) == [2, 1]

    def test_the_oldest_are_the_ones_dropped(self):
        """예산이 모자라면 **오래된 쪽**이 잘린다 — 시연에서 노리는 동작 그대로다."""
        items = [item(i, age_days=i) for i in range(10)]

        # 1건당 10자, 예산 35자 -> 3건.
        kept = select_archive(items, None, 35, lambda i: "x" * 10, by_recency=True)

        assert ids(kept) == [0, 1, 2]

    def test_items_without_a_timestamp_go_last(self):
        """`created_at` 이 없는 자료는 뒤로 — 없는 값이 1등을 먹으면 안 된다.

        `NEUTRAL` 이 순위 축에서 막으려던 것과 같은 종류의 사고다(값 없음이 이득이 되는 것).
        여기서는 정렬 키가 `None` 이라 그냥 두면 `TypeError` 로 터지기까지 한다.
        """
        undated = item(1)
        undated.created_at = None
        items = [undated, item(2, age_days=10)]

        kept = select_archive(items, None, 100_000, lambda i: i.title, by_recency=True)

        assert ids(kept) == [2, 1]

    def test_the_budget_still_rescues_a_single_oversized_item(self):
        """최신순에서도 "하나도 안 들어가면 1등만 남기고 자른다" 폴백이 살아 있어야 한다."""
        items = [item(1, age_days=0)]

        kept = select_archive(items, None, 1, lambda i: "x" * 999, by_recency=True)

        assert ids(kept) == [1]


class TestProductionBudget:
    """운영 기본값 자체를 못 박는다 — 시연 응답시간의 근거값이라 조용히 되돌아가면 안 된다."""

    def test_the_default_budget_is_three_thousand(self):
        from modi_ai.config import Settings

        assert Settings().archive_prompt_budget_chars == 3_000

    def test_recency_selection_is_the_default(self):
        from modi_ai.config import Settings

        assert Settings().archive_select_by_recency is True

    def test_the_default_budget_actually_cuts_a_thirty_five_item_room(self):
        """춘천여행 방(자료 35건) 기준으로 **실제로 잘리는지**를 본다.

        2026-08-09 운영 실측의 대상이던 방이다. 206자/건(2026-08-02 실측 평균)으로 채우면
        35건은 약 7,200자 — 예전 예산 12,000 에서는 전부 실렸고 3,000 에서는 잘린다.
        """
        from modi_ai.config import Settings
        from modi_ai.suggest import render_archive_item

        budget = Settings().archive_prompt_budget_chars
        items = [item(i, age_days=i) for i in range(35)]
        for each in items:
            each.content = "나" * 180  # 렌더 합계가 건당 약 206자가 된다

        kept = select_archive(items, None, budget, render_archive_item, by_recency=True)

        assert len(kept) < 35, "예산이 발동하지 않았다 — 지연 개선의 전제가 깨진다"
        assert ids(kept) == list(range(len(kept))), "잘린 것이 최신이 아니라 오래된 쪽이어야 한다"
        assert sum(len(render_archive_item(i)) for i in kept) <= budget
