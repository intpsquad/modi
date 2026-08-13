"""동결 스냅샷 검증 — `docs/EXPERIMENTS.md` **#20** 의 수치를 실행 가능하게 만든다.

크레딧 0 · 네트워크 0. `tests/test_snapshot.py`(#13 용)와 같은 역할이고 같은 이유로 있다.

**이 파일이 없어서 실제로 사고가 났다.** #20 초안이 커밋된 파일 어디에도 없는 `47.5%` 를
근거로 "규칙 5를 손대지 않는다" 를 정당화했고, DECISIONS 는 최대 길이를 `30~34` 로 적었는데
실제 값에는 34가 없었다. 둘 다 아래 테스트가 있었으면 못 나갔다.

**스냅샷을 고쳐서 통과시키면 안 된다.** 숫자가 바뀌었다면 문서와 스냅샷을 함께 다시 만든다.
"""

import json
import statistics

import pytest

from evals.dataset import SNAPSHOT_DIR, load_snapshot

PREFIX = "2026-08-01_gpt-5.4-nano_summary_"

# 표의 행 이름 → 파일. #20 의 조건표와 **같은 순서**로 둔다.
RUNS = {
    "할일": f"{PREFIX}할-일.json",
    "할일_repeat": f"{PREFIX}할-일_repeat.json",
    "공부": f"{PREFIX}공부.json",
    "공부_repeat": f"{PREFIX}공부_repeat.json",
    "공부_norule4": f"{PREFIX}공부_norule4.json",
    "공부_nohints": f"{PREFIX}공부_norule4_noschemahint.json",
    "nocat": f"{PREFIX}nocat.json",
    "nocat_nohints": f"{PREFIX}nocat_norule4_noschemahint.json",
}


def _raw(name: str) -> dict:
    return json.loads((SNAPSHOT_DIR / RUNS[name]).read_text(encoding="utf-8"))


def _titles(name: str) -> list[str]:
    return [c.title for case in load_snapshot(RUNS[name]) for c in case.candidates]


def _categories(name: str) -> list[str | None]:
    return [c.category for case in load_snapshot(RUNS[name]) for c in case.candidates]


@pytest.fixture(scope="module")
def every_run() -> dict[str, dict]:
    return {name: _raw(name) for name in RUNS}


class TestAllRunsAreFrozen:
    @pytest.mark.parametrize("name", RUNS)
    def test_fifteen_cases_each(self, name):
        assert len(load_snapshot(RUNS[name])) == 15

    @pytest.mark.parametrize("name", RUNS)
    def test_conditions_are_recorded(self, name):
        """조건 없는 숫자는 근거가 못 된다 — 파일만 보고 조건을 알 수 있어야 한다."""
        raw = _raw(name)

        for field in ("rule4", "schema_category_hint", "input", "categories", "temperature"):
            assert field in raw, field
        assert raw["input"] == "summary"
        assert raw["temperature"] == 0.0
        assert raw["model"] == "gpt-5.4-nano"

    @pytest.mark.parametrize("name", RUNS)
    def test_no_errors_and_nothing_dropped_by_the_filter(self, name):
        """#20 이 "오류 0 · 필터 탈락 0" 이라고 적은 근거."""
        summary = _raw(name)["summary"]

        assert summary["errors"] == 0
        assert summary["dropped_by_filter"] == 0


class TestCategoryAxis:
    """#20 ①② — **결론 전체가 이 값에 기댄다.** 다른 값은 잡음이 커서 못 쓴다."""

    @pytest.mark.parametrize(
        "name",
        ["할일", "할일_repeat", "공부", "공부_repeat", "공부_norule4", "공부_nohints", "nocat"],
    )
    def test_no_new_category_in_seven_conditions(self, name):
        assert _raw(name)["summary"]["new_categories"] == 0

    def test_removing_both_hints_with_no_existing_categories_does_produce_new_ones(self):
        """**이 셀이 결론을 뒤집었다.** 초안은 이 조건을 안 돌리고 "모델이 지어내지 않는다"고 썼다.

        리뷰에서 빠진 셀을 지적받아 돌렸더니 새 카테고리가 15개 나왔다 — 모델은 **지어낼 수 있다.**
        """
        assert _raw("nocat_nohints")["summary"]["new_categories"] == 15

    def test_the_invented_category_names(self):
        """#20 이 인용한 이름이 스냅샷에 실제로 있는지."""
        invented = {c for c in _categories("nocat_nohints") if c}

        assert invented == {
            "여행/식도락",
            "여행/교통",
            "여행/코스",
            "여행 코스",
            "장소 방문",
            "맛집 방문",
            "여행 일정",
        }

    def test_only_four_materials_got_a_new_category(self):
        """15건 중 4건뿐이다 — "된다" 로 읽으면 안 되는 이유."""
        with_new = [
            case.stem
            for case in load_snapshot(RUNS["nocat_nohints"])
            if any(c.category for c in case.candidates)
        ]

        assert (
            with_new
            == [
                "001_gangneung_food",
                "003_busan_hanroro_combine",
                "004_busan_1n2d",
            ]
            or len(with_new) == 3
        ), with_new

    def test_no_categories_with_hints_leaves_every_candidate_empty(self):
        """#20 ② — 40개 전부 `None`. 비우는 것과 짓는 것은 다른 행동이다."""
        categories = _categories("nocat")

        assert len(categories) == 40
        assert set(categories) == {None}

    def test_an_existing_category_swallows_everything(self):
        """여행·맛집 자료까지 전부 `공부` 로 들어갔다 — 편향의 실체."""
        assert set(_categories("공부")) == {"공부"}


class TestNoiseFloor:
    """#20 잡음 절 — **후보 개수·제목 길이를 조건 비교의 근거로 쓰지 말라**는 것의 근거."""

    @pytest.mark.parametrize(("a", "b"), [("할일", "할일_repeat"), ("공부", "공부_repeat")])
    def test_the_same_condition_gives_different_counts(self, a, b):
        counts = {_raw(a)["summary"]["candidates"], _raw(b)["summary"]["candidates"]}

        assert len(counts) == 2, counts

    def test_candidate_counts_are_frozen(self, every_run):
        assert {n: r["summary"]["candidates"] for n, r in every_run.items()} == {
            "할일": 31,
            "할일_repeat": 35,
            "공부": 28,
            "공부_repeat": 25,
            "공부_norule4": 36,
            "공부_nohints": 35,
            "nocat": 40,
            "nocat_nohints": 42,
        }


class TestTitleLength:
    """#20 ③ — 요약 도입 **후** 관측값. #13(본문) 과 나란히 보는 짝이다."""

    def test_minimum_length_range(self, every_run):
        mins = [r["summary"]["title_length"]["min"] for r in every_run.values()]

        assert (min(mins), max(mins)) == (12, 16)

    def test_maximum_length_range(self, every_run):
        """`30~34` 로 적혔다가 리뷰에서 잡혔다 — 34인 실행은 없다."""
        maxs = sorted(r["summary"]["title_length"]["max"] for r in every_run.values())

        assert maxs == [30, 30, 30, 31, 31, 33, 33, 40]

    def test_the_only_forty_char_title_is_the_runner_artifact(self):
        """픽스처는 크롤링을 안 거쳐 `EvalCase.title` 이 **파일 이름**을 넘긴다."""
        longest = max((t for name in RUNS for t in _titles(name)), key=len)

        assert len(longest) == 40
        assert "009_fashion_promtome" in longest

    def test_over_twenty_ratio_range(self, every_run):
        """`47.5%` 를 근거로 쓴 초안이 리뷰에서 잡혔다 — 그런 값은 없다."""
        ratios = [
            r["summary"]["title_length"]["over_20"] / r["summary"]["candidates"]
            for r in every_run.values()
        ]

        assert round(min(ratios) * 100, 1) == 58.3
        assert round(max(ratios) * 100, 1) == 74.2
        assert all(0.58 <= r <= 0.75 for r in ratios), ratios


class TestLatencyAndTokens:
    """#20 ⑤⑥ — per-case 값을 스냅샷이 안 들고 있어 export 에만 있던 것을 옮겨왔다."""

    def _seconds(self) -> list[float]:
        return [c["seconds"] for name in RUNS for c in _raw(name)["cases"]]

    def _prompt_tokens(self, *names: str) -> list[int]:
        return [c["prompt_tokens"] for name in names for c in _raw(name)["cases"]]

    def test_the_bulk_is_under_three_seconds(self):
        """#20 ⑤ — 120회 중 117회가 2.8초 이하다."""
        seconds = self._seconds()

        assert len(seconds) == 120
        assert min(seconds) == 1.1
        assert sum(1 for s in seconds if s <= 2.8) == 117
        assert statistics.median(seconds) < 2.0

    def test_two_outliers_and_the_worst_is_six_seconds(self):
        """**"항상 3초 안" 으로 읽으면 안 된다.** 초안은 이상치를 1건으로 적었다."""
        assert sorted(s for s in self._seconds() if s > 3.0) == [3.32, 6.1]

    def test_the_six_second_case_is_fast_in_other_runs(self):
        """자료 탓이 아니라 게이트웨이 흔들림이라는 근거."""
        elsewhere = [
            case["seconds"]
            for name in RUNS
            for case in _raw(name)["cases"]
            if case["stem"] == "001_gangneung_food"
        ]

        assert max(elsewhere) == 6.1
        assert sorted(elsewhere)[-2] <= 3.4

    def test_prompt_tokens_with_the_hint_present(self):
        """#20 ⑥ — 자료 1건짜리 프롬프트가 이 대역이다(고정비가 대부분)."""
        tokens = self._prompt_tokens("할일", "할일_repeat", "공부", "공부_repeat", "nocat")

        assert (min(tokens), max(tokens)) == (869, 948)

    def test_dropping_the_schema_hint_saves_a_fixed_amount(self):
        """`913→713` 은 3변수 차이였다 — 규칙4를 고정하고 힌트만 뺀 순수 효과는 155 tok."""
        with_hint = self._prompt_tokens("공부_norule4")
        without = self._prompt_tokens("공부_nohints")

        assert {a - b for a, b in zip(with_hint, without, strict=True)} == {155}
