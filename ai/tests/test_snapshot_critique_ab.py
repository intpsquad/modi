"""`docs/EXPERIMENTS.md` #28 이 인용하는 A/B 수치 — 커밋된 스냅샷에서 단언한다. 크레딧 0.

## 여기서 세는 것은 **나쁜 모양**이다

#26 은 "실제로 하는 일"(좋은 동사)의 비율을 셌다. **#28 에서 그 지표가 무너졌다** —
검수를 켜니 `탐방하기`·`체험하기`·`방문해보기`·`가기` 같은 동사가 새로 나왔는데, 목록을
검수 **없는** 출력에서만 뽑았던 탓에 그것들이 전부 "계획·확인"으로 세어졌다. 그래서 눈으로는
확실히 좋아진 실행이 9% 로 찍혔다.

**좋은 동사를 열거하는 방식 자체가 틀렸다.** 좋은 동사는 열린 집합이고 조건마다 새로 생긴다.
반대로 사용자가 지목한 **나쁜 모양은 닫힌 집합**이다 — `동선 짜기` · `코스로 묶기` ·
`일정에 넣기` · `후보 고르기`. 그걸 센다.

⚠️ **지표를 데이터에 맞춘 것 아닌가?** 순서는 이랬다 — 재현이 안 돼서 → 출력을 눈으로 나란히
보고 → 무엇이 사라졌는지 확인하고 → 그걸 셌다. `ai/CLAUDE.md` 가 정한 순서 그대로다.
목록 17개 중 **3개**(`짜기`·`묶기`·`고르기`)는 사용자가 직접 든 불만 예시에서 왔고 나머지는
출력을 보고 골랐다(초안에 "전부 사용자 예시에서 나왔다"고 적었는데 과장이었다 — 2026-08-03 리뷰).

**출력에 맞춰 고른 것이 아니라는 증거 셋**(리뷰가 직접 확인했다).
  1. 17개 중 **4개**(`뽑기`·`선정하기`·`추리기`·`만들어두기`)는 5개 스냅샷 어디에도 안 나온다.
     출력을 보고 골랐다면 나올 수 없는 항목이다.
  2. `포함하기` 는 **처치군에만** 나오고 기준선에는 없다 — `DOING_VERBS` 를 죽인 결함
     ("기준선 출력에서만 뽑았다")이 여기엔 없다.
  3. 적대적 변형에서도 방향이 안 바뀐다. 사용자 예시 3개만으로 부산 9% → 0%·0%,
     `확인*` 을 전부 더한 최대 집합으로 70% → 31%·44%.

## ⚠️ `확인하기` 를 왜 뺐나 — **이 제외가 결과를 좌우한다**

`확인하기` 는 기준선 부산의 최빈 끝동사고(20/82 = 24%) `CRITIQUE_PROMPT` 규칙 3도 "가능 여부
확인하기"를 반려 예시로 든다. **넣으면 조건 1(평균 37.5%)과 2(37.0%)가 구분 불가가 된다.**

뺀 이유는 **대상이 특정된 확인은 실행 가능한 일**이기 때문이다 — `더웨이브펜션 체크인 3시
확인하기` 는 바로 할 수 있고, 사용자가 든 불만 예시에도 없다. 끝동사만으로는 "대상이
특정됐는가"를 가릴 수 없어서 이 동사 하나를 통째로 뺐다.

**대가**: 그래서 이 지표는 `캐치테이블 가능 여부 확인해 맛집 예약하기`(대상 없는 확인)를
못 잡는다. 그건 눈으로 봐야 한다(#28 ②).
"""

import json

import pytest

from evals.dataset import SNAPSHOT_DIR

# 사용자가 지목한 계획·선별 행위. **닫힌 집합이다** — 늘려서 결과를 바꾸지 말 것.
META_VERBS = frozenset(
    {
        "짜기",
        "묶기",
        "넣기",
        "잡기",
        "정하기",
        "추가하기",
        "확보하기",
        "재정리하기",
        "계획하기",
        "뽑기",
        "고르기",
        "선정하기",
        "추리기",
        "체크하기",
        "배치하기",
        "포함하기",
        "만들어두기",
    }
)

RUNS = {
    0: ["2026-08-03_room_ab_critique0.json"],
    1: ["2026-08-03_room_ab_critique1.json", "2026-08-03_room_ab2_critique1.json"],
    2: ["2026-08-03_room_ab_critique2.json", "2026-08-03_room_ab2_critique2.json"],
}


def load(name: str) -> dict:
    return json.loads((SNAPSHOT_DIR / name).read_text(encoding="utf-8"))


def meta_ratio(snapshot: dict, slug: str) -> float:
    titles = sorted(
        {c["title"] for r in snapshot["rooms"][slug]["rounds"] for c in r["candidates"]}
    )
    return sum(1 for t in titles if t.split()[-1] in META_VERBS) / len(titles)


def round_seconds(snapshot: dict) -> list[float]:
    return [
        r["seconds"]
        for room in snapshot["rooms"].values()
        for r in room["rounds"]
        if not r["error"]
    ]


class TestConditionsAreDistinct:
    """조건이 스냅샷에 안 박혀 있으면 A/B 가 성립하지 않는다."""

    @pytest.mark.parametrize("attempts", [0, 1, 2])
    def test_each_snapshot_records_its_setting(self, attempts):
        """⚠️ **처음에는 `rounds == 3` · `repeats == 5` 만 단언했다** — 5개 파일이 전부 같은
        값이라 조건을 하나도 구분하지 못했다. 이름은 "조건이 구분된다"인데 실제로는 아무것도
        안 지켰다(2026-08-03 리뷰). `freeze_snapshot` 이 조건을 안 옮기고 있던 것도 같이 나왔다.
        """
        for name in RUNS[attempts]:
            snapshot = load(name)

            assert snapshot["critique_max_attempts"] == attempts
            assert (snapshot["rounds"], snapshot["repeats"]) == (3, 5)

    def test_all_five_runs_used_the_same_fixtures(self):
        """입력이 다르면 조건 비교가 아니라 입력 비교가 된다."""
        digests = {
            tuple(sorted(load(n)["fixture_digests"].items())) for r in RUNS.values() for n in r
        }

        assert len(digests) == 1


class TestTheMetaShapeDisappears:
    """#28 의 핵심 — **이것만 재현됐다.**"""

    def test_the_baseline_is_full_of_them(self):
        assert meta_ratio(load(RUNS[0][0]), "busan_travel") == pytest.approx(0.40, abs=0.01)

    @pytest.mark.parametrize("name", RUNS[1])
    def test_critique_removes_almost_all_of_them(self, name):
        """0% 와 6% 가 나왔다 — 기준선 40% 와 겹치지 않는다."""
        assert meta_ratio(load(name), "busan_travel") <= 0.10

    def test_the_effect_is_far_bigger_than_the_run_to_run_swing(self):
        """두 실행의 차이(0%↔6%)가 효과(40%→6%)보다 훨씬 작아야 결론이 선다."""
        ratios = [meta_ratio(load(n), "busan_travel") for n in RUNS[1]]
        baseline = meta_ratio(load(RUNS[0][0]), "busan_travel")

        assert max(ratios) - min(ratios) < (baseline - max(ratios))

    def test_the_study_room_was_already_clean(self):
        """학습 방은 원래 메타 행위가 적다 — 개선 여지가 작았다는 것도 기록해둔다."""
        assert meta_ratio(load(RUNS[0][0]), "opic_study") == pytest.approx(0.12, abs=0.01)


class TestOneVersusTwoDoesNotSeparate:
    """`critique_max_attempts` 를 1 로 정한 **진짜** 근거.

    ⚠️ **처음에는 "2 가 나쁘다"로 적었고 그건 틀렸다**(2026-08-03 리뷰).
    - 오픽 메타 행위는 **2 가 두 실행 모두 더 낫다.**
    - 지연 평균도 **2 가 두 방 모두 더 빠르다** — "2 는 지연만 더 든다"고 쓴 것이 정반대였다.
    - 후보 수도 2 가 많다.
    - "2 기각" 은 사실상 **부산 1차의 22% 하나**에 걸려 있었다(2차는 3.0%).

    그때 이걸 가린 테스트가 `min(조건1) >= max(조건2)` 비교였다 — **결론에 유리한 쪽으로만
    기울 수 있는 비대칭 비교**다. 평균 대 평균으로 바꾸면 뒤집힌다.

    그래서 근거를 바꿔 적는다: **데이터로는 둘을 구분할 수 없다. 그래서 싼 쪽인 1 을 쓴다.**
    """

    def test_neither_wins_on_the_metric(self):
        """군간 차이가 군내 흔들림보다 작다 — #28 이 스스로 세운 기준을 통과하지 못한다."""
        one = [meta_ratio(load(n), "busan_travel") for n in RUNS[1]]
        two = [meta_ratio(load(n), "busan_travel") for n in RUNS[2]]
        between = abs(sum(two) / len(two) - sum(one) / len(one))
        within = max(max(two) - min(two), max(one) - min(one))

        assert between < within, "구분이 되기 시작했다면 #28 ④ 를 다시 써야 한다"

    def test_two_is_not_slower_on_average(self):
        """**"2 는 지연만 더 든다"가 틀렸다는 것을 고정한다.** 같은 실수를 다시 하지 않도록."""
        for slug in ("busan_travel", "opic_study"):
            one = [load(n)["rooms"][slug]["summary"]["seconds_mean"] for n in RUNS[1]]
            two = [load(n)["rooms"][slug]["summary"]["seconds_mean"] for n in RUNS[2]]

            assert sum(two) / len(two) <= sum(one) / len(one)

    def test_one_is_chosen_for_simplicity_not_superiority(self):
        """1 은 LLM 호출이 라운드당 정확히 2회다 — 2 는 최악 4회. 그게 고른 이유의 전부다."""
        assert all(load(n)["critique_max_attempts"] == 1 for n in RUNS[1])


class TestTheCostIsReal:
    """#28 이 숨기지 않는 대가 — 후보가 절반 이하로 준다."""

    def test_candidate_count_roughly_halves(self):
        baseline = load(RUNS[0][0])["rooms"]["busan_travel"]["summary"]["total_candidates"]

        for name in RUNS[1]:
            assert (
                load(name)["rooms"]["busan_travel"]["summary"]["total_candidates"] < baseline / 1.5
            )

    def test_the_third_round_can_come_back_empty(self):
        """빈 화면을 허용한 결과다(2026-08-03 사용자 확정). 실제로 0 이 나왔다."""
        third = [
            load(n)["rooms"]["busan_travel"]["summary"]["per_round"][2]["count_min"]
            for n in RUNS[1]
        ]

        assert min(third) == 0

    def test_the_seven_second_ceiling_is_breached_in_about_one_round_in_eight(self):
        """⚠️ **처음에는 `seconds_mean < 7.0` 만 단언했고 그건 사실을 가렸다**(2026-08-03 리뷰).

        평균으로는 상한 안이지만 **라운드 단위로는 13%가 7초를 넘고 최악이 10.88초**다.
        사용자가 받은 거래는 "후보가 준다 / 빈 화면이 나온다" 였지 "8번에 1번은 7초를 넘는다"가
        아니었다 — 알리고 다시 확정받았다(2026-08-03, 검수 유지).

        여기서 **비율이 크게 나빠지면** 그 확정의 전제가 바뀐 것이므로 다시 물어야 한다.
        """
        seconds = [s for name in RUNS[1] for s in round_seconds(load(name))]
        over = [s for s in seconds if s >= 7.0]

        assert len(seconds) == 60
        assert 0.10 <= len(over) / len(seconds) <= 0.20, f"{len(over)}/60 — 전제가 바뀌었다"
        assert max(seconds) < 12.0, f"최악 {max(seconds):.2f}초 — 10.88 이었다"

    def test_the_mean_still_sits_under_the_ceiling(self):
        """평균은 상한 안이다 — 위 테스트와 **둘 다** 있어야 사실을 온전히 말한다."""
        for name in RUNS[1]:
            for room in load(name)["rooms"].values():
                assert room["summary"]["seconds_mean"] < 7.0

    def test_critique_roughly_doubles_the_worst_case(self):
        """기준선 최악 5.05초 → 검수 켬 10.88초. 평균(+1.8초)만 보면 안 보이는 사실이다."""
        assert max(round_seconds(load(RUNS[0][0]))) < 6.0
        assert max(s for n in RUNS[1] for s in round_seconds(load(n))) > 9.0


class TestCategoryDropWasJustAByproduct:
    """**이득으로 착각했던 것.** 카테고리 종수는 줄었지만 후보당 비율은 그대로다."""

    def test_the_ratio_is_unchanged(self):
        def ratio(snapshot, slug):
            titles = {
                c["title"] for r in snapshot["rooms"][slug]["rounds"] for c in r["candidates"]
            }
            return snapshot["rooms"][slug]["summary"]["categories"]["kinds"] / len(titles)

        baseline = ratio(load(RUNS[0][0]), "opic_study")

        for name in RUNS[1]:
            assert ratio(load(name), "opic_study") == pytest.approx(baseline, abs=0.06)
