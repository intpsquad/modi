"""`docs/EXPERIMENTS.md` #30 이 인용하는 수치 — 커밋된 스냅샷에서 단언한다. 크레딧 0.

**의 근거가 이 파일이다.** 검수 번호를 `0` 에서 `1` 로 바꾼 유일한 이유가
아래 수치이므로, 문서의 숫자와 스냅샷이 갈리면 그 결정의 근거가 사라진다.

⚠️ **리터럴 임계값을 쓰지 않는다.** -237 리뷰에서 표의 반올림 값(`6.6%`)을 그대로 `< 0.066`
으로 썼다가 기준선(6.5574%)도 통과하는 단언을 만든 전례가 있다(P1-3). 여기서는 두 조건의
실측을 **서로 직접 비교**한다.
"""

import json
import pathlib
import statistics

import pytest

from evals.probe_critique import BATCHES, CONDITIONS, classify
from tests.test_snapshot_critique_ab import load, meta_ratio, round_seconds

SNAPSHOT = (
    pathlib.Path(__file__).parent.parent
    / "evals"
    / "data"
    / "snapshots"
    / "2026-08-03_critique_index_probe.json"
)


@pytest.fixture(scope="module")
def probe() -> dict:
    return json.loads(SNAPSHOT.read_text(encoding="utf-8"))


def rounds(probe: dict, condition: str) -> list[dict]:
    return [r for r in probe["rounds"] if r["condition"] == condition]


def mismatches(probe: dict, condition: str) -> list[dict]:
    return [r for r in rounds(probe, condition) if r["outcome"] != "ok"]


def _grams(text: str, n: int = 2) -> set[str]:
    squashed = "".join(text.split())
    return {squashed[i : i + n] for i in range(len(squashed) - n + 1)}


def best_match(reason: str, titles: list[str]) -> tuple[float, int]:
    """사유가 **어느 후보를 설명하는지** 글자 2-gram 겹침으로 추정한다.

    ⚠️ **완벽한 판별기가 아니다.** 동결된 데이터에 대해서만 돌리므로 결과는 결정적이지만,
    사유가 짧고 일반적이면(`'일정 넣기'는 계획 행위다`) 엉뚱한 후보를 고른다. 그래서
    아래 단언들은 **점수 문턱을 넘은 `라벨+1` 짝**, 즉 밀림의 서명만 센다. 잡음 2건은
    `TestTheShiftDetectorIsHonest` 가 이름을 대고 남겨둔다.
    """
    scored = [
        (len(_grams(reason) & _grams(t)) / max(1, len(_grams(t))), i) for i, t in enumerate(titles)
    ]
    return max(scored)


SHIFT_SCORE_FLOOR = 0.25
"""이 점수 아래는 판별기 잡음으로 보고 안 센다.

실측 분포에서 밀림 12건은 0.26~0.93 이고, 오탐 2건은 0.12·0.27 이다. 0.27 짜리는 `라벨+1`
이 아니라서 어차피 안 걸린다 — 문턱이 거르는 것은 `near_dup` 의 0.12 하나다.
"""


def shifted_rejections(probe: dict, condition: str) -> list[tuple]:
    """반려 사유가 **바로 다음 후보**를 설명하는 건수 — 번호 밀림의 서명."""
    base = CONDITIONS[condition]
    found = []
    for r in rounds(probe, condition):
        titles = BATCHES[r["batch"]]
        for v in r["verdicts"]:
            if v["ok"] or not v["reason"]:
                continue
            score, guess = best_match(v["reason"], titles)
            if guess == (v["index"] - base) + 1 and score >= SHIFT_SCORE_FLOOR:
                found.append((r["batch"], r["repeat"], v["index"], round(score, 2)))
    return found


class TestTheExperimentIsSound:
    """수치를 읽기 전에 **실험이 성립했는지** 먼저 본다."""

    def test_the_model_is_the_production_one(self, probe: dict):
        """다른 모델로 잰 값으로 운영을 고칠 수 없다."""
        assert probe["model"] == "gpt-5.4-nano"

    def test_both_numbering_schemes_were_measured(self, probe: dict):
        assert set(probe["conditions"]) == set(CONDITIONS)
        assert probe["conditions"] == CONDITIONS

    def test_every_batch_ran_in_both_conditions(self, probe: dict):
        expected = probe["repeats"] * len(BATCHES)
        for condition in CONDITIONS:
            assert len(rounds(probe, condition)) == expected

    def test_no_round_died(self, probe: dict):
        """호출 실패가 섞이면 "판정 개수가 맞았다"를 못 센다."""
        dead = [r for r in probe["rounds"] if r["error"]]
        assert dead == [], f"에러 라운드가 있다: {dead}"

    def test_every_outcome_is_recomputed_from_the_raw_fields(self, probe: dict):
        """🔴 **저장된 `outcome` 문자열을 믿지 않는다** (2026-08-03 리뷰 P1-1).

        처음에는 처치군 단언이 `outcome` 만 읽어서, 판정을 잘라내고 `"ok"` 만 남긴 위조가
        **466 green 을 유지한 채 통과했다**(리뷰가 실제로 해봤다). 대조군은 원시 필드로
        재계산하고 있었으니 방어가 비대칭이었다.
        """
        for r in probe["rounds"]:
            assert r["verdict_count"] == len(r["verdicts"]) == len(r["indices"]), r
            expected = classify(r["indices"], r["candidates"], CONDITIONS[r["condition"]])
            assert r["outcome"] == expected, r

    def test_the_batches_on_file_match_the_ones_in_code(self, probe: dict):
        """🔴 **입력이 드리프트하면 이 파일의 논증이 통째로 무효다** (리뷰 P1-2).

        `BATCHES` 의 제목을 전부 무의미한 문자열로 바꿔도 스냅샷과 모순이 안 났다 — 개수만
        기록돼 있었기 때문이다. 아래 단언들이 사유↔후보 대조의 전제를 지킨다.
        """
        assert probe["batch_sizes"] == {n: len(t) for n, t in BATCHES.items()}
        for r in probe["rounds"]:
            assert r["candidates"] == len(BATCHES[r["batch"]]), r

    def test_the_titles_the_argument_leans_on_are_still_in_place(self, probe: dict):
        """밀림 논증이 **이 제목들의 위치**에 의존한다. 움직이면 논증도 다시 써야 한다."""
        assert "캐치테이블" in BATCHES["busan_8c"][7]
        assert "민락동" in BATCHES["busan_8c"][5]
        assert "부네치아" in BATCHES["busan_8c"][6]
        assert "콤보" in BATCHES["opic_8"][7]
        assert BATCHES["opic_8"][1].startswith("서베이 항목")
        assert "PDF" in BATCHES["opic_8"][5]


class TestZeroBasedIsBroken:
    """`0.` 에서 판정이 실제로 모자랐다 — 이 티켓이 존재하는 이유."""

    def test_a_third_of_the_rounds_mismatched(self, probe: dict):
        bad = mismatches(probe, "zero_based")
        total = len(rounds(probe, "zero_based"))
        assert len(bad) == 10, f"불일치가 10회가 아니다: {len(bad)}"
        assert total == 30
        assert len(bad) / total == pytest.approx(1 / 3, abs=0.01)

    def test_every_mismatch_was_exactly_one_verdict_short(self, probe: dict):
        """콘솔 로그가 전부 `후보 N개, 판정 N-1개` 였다는 관찰과 같아야 한다."""
        for r in mismatches(probe, "zero_based"):
            assert r["verdict_count"] == r["candidates"] - 1, r

    def test_the_response_was_always_a_contiguous_run_from_zero(self, probe: dict):
        """**진짜 관측은 응답 모양이다** — 번호가 `0..n-2` 로 빠짐없이 이어져 왔다.

        ⚠️ **원래 여기에 `missing == [n-1]` 을 걸어두고 "꼬리가 빠졌다는 근거"라고 적었다.
        항진명제였다**(2026-08-03 리뷰 P0-1). 개수 검사를 통과한 뒤이므로, 응답이 `0` 부터
        연속인 한 빠진 번호는 **반드시** `n-1` 이다 — 어떤 가설에서도 참이라 아무것도 못 가른다.
        """
        for r in mismatches(probe, "zero_based"):
            assert r["indices"] == list(range(r["candidates"] - 1)), r

    def test_the_missing_label_is_arithmetic_not_evidence(self, probe: dict):
        """위 모양에서 `missing` 이 자동으로 따라온다는 것을 **명시적으로** 남긴다.

        다음 사람이 `missing` 히스토그램을 "꼬리 후보가 판정을 못 받았다"로 읽지 않게 하려는
        것이다. `missing` 은 **번호 라벨**이지 후보가 아니다.
        """
        for r in mismatches(probe, "zero_based"):
            assert r["missing"] == [r["candidates"] - 1] == [max(r["indices"]) + 1], r

    def test_it_is_deterministic_per_batch_not_random(self, probe: dict):
        """묶음마다 5/5 아니면 0/5 다 — 무작위가 아니라 입력에 달렸다.

        이게 방 평가에서 한 방에만 몰려 보인 이유다. **다른 방이 안전하다는 뜻이 아니다.**
        """
        for batch in BATCHES:
            bad = [r for r in mismatches(probe, "zero_based") if r["batch"] == batch]
            assert len(bad) in (0, probe["repeats"]), f"{batch}: {len(bad)}"

    def test_it_hit_both_rooms(self, probe: dict):
        """부산 방 전용 현상이 아니다 — 오픽 묶음도 걸렸다."""
        hit = {r["batch"] for r in mismatches(probe, "zero_based")}
        assert hit == {"busan_8c", "opic_8"}


class TestTheVerdictsPointedAtTheWrongCandidates:
    """🔴 **이 티켓이 낼 수 있는 가장 강한 증거** (2026-08-03 리뷰 P1-4).

    개수가 맞는지는 곁가지다. 진짜 위험은 **판정이 엉뚱한 후보에 붙는 것**이고, 그건 개수가
    우연히 맞으면 fail-open 도 안 걸려 조용히 지나간다. 커밋된 스냅샷에 반려 사유가 다 있으니
    크레딧 0 으로 확인할 수 있는데, 처음엔 안 했다.
    """

    def test_zero_based_shifted_verdicts_onto_the_next_candidate(self, probe: dict):
        found = shifted_rejections(probe, "zero_based")
        assert len(found) >= 10, f"밀림이 관측돼야 한다: {found}"

    def test_one_based_never_shifted(self, probe: dict):
        """**처방이 고친 것은 개수가 아니라 짝이다.**"""
        found = shifted_rejections(probe, "one_based")
        assert found == [], f"1-based 인데 밀린 판정이 있다: {found}"

    def test_the_shift_begins_at_a_different_place_per_batch(self, probe: dict):
        """⚠️ **"꼬리가 빠진다"고 쓰면 안 되는 근거.**

        `opic_8` 은 `index=5` 까지 라벨과 맞고 `6` 부터 밀리는데, `busan_8c` 는 `index=4`
        에서 이미 밀렸다. 그래서 **어느 후보가 판정을 못 받았는지는 묶음마다 다르고**,
        통과 판정에는 사유가 없어 확정할 수도 없다.
        """
        onsets = {}
        for batch, _repeat, index, _score in shifted_rejections(probe, "zero_based"):
            onsets[batch] = min(onsets.get(batch, index), index)
        assert onsets["opic_8"] == 6
        assert onsets["busan_8c"] == 4, "busan_8c 는 6 보다 앞에서 이미 밀렸다"

    def test_an_aligned_verdict_exists_before_the_onset(self, probe: dict):
        """밀림이 **전면적이 아니라 어느 지점부터**라는 것 — 위 주장의 반쪽이다.

        `opic_8` 의 `index=1` 사유는 라벨 1 후보(`서베이 항목을 …`)를 정확히 설명한다.
        """
        aligned = [
            v
            for r in rounds(probe, "zero_based")
            if r["batch"] == "opic_8"
            for v in r["verdicts"]
            if not v["ok"] and v["index"] == 1
        ]
        assert aligned, "opic_8 의 index=1 반려를 못 찾았다"
        for v in aligned:
            score, guess = best_match(v["reason"], BATCHES["opic_8"])
            assert guess == 1, (v, score)


class TestTheShiftDetectorIsHonest:
    """판별기가 완벽하지 않다는 것을 **이름을 대고** 남긴다.

    숨기면 다음 사람이 이걸 정밀한 도구로 오해한다.
    """

    def test_the_two_known_false_positives_are_still_just_noise(self, probe: dict):
        """`one_based` 에서 판별기가 틀린 2건 — 눈으로 보면 사유가 라벨 후보를 정확히 설명한다.

        - `busan_8b` `index=7` → `‘일정 넣기’는 계획·확인(구성) 행위에 해당한다`
          (라벨 후보 `런닝맨 부산점 실내 액티비티 체험 **일정 넣기**` — 맞다)
        - `opic_8` `index=6` → `PDF를 ‘훑기’ 전에 …`
          (라벨 후보 `… 가이드 **PDF 훑기**` — 맞다)

        둘 다 `라벨+1` 이 아니라서 `shifted_rejections` 에 안 잡힌다. 그 성질이 이 파일의
        결론을 떠받치므로 여기서 고정한다.
        """
        base = CONDITIONS["one_based"]
        misses = []
        for r in rounds(probe, "one_based"):
            titles = BATCHES[r["batch"]]
            for v in r["verdicts"]:
                if v["ok"] or not v["reason"]:
                    continue
                _score, guess = best_match(v["reason"], titles)
                if guess != v["index"] - base:
                    misses.append((r["batch"], v["index"], guess))
        assert len(misses) == 2, f"오탐 개수가 변했다: {misses}"
        assert all(guess != (index - base) + 1 for _batch, index, guess in misses), misses


class TestOneBasedIsClean:
    """`1.` 이 고친다 — 이 티켓의 처방."""

    def test_not_a_single_round_mismatched(self, probe: dict):
        assert mismatches(probe, "one_based") == []

    def test_it_is_strictly_better_than_zero_based(self, probe: dict):
        """리터럴이 아니라 **두 조건을 직접 비교**한다."""
        assert len(mismatches(probe, "one_based")) < len(mismatches(probe, "zero_based"))

    def test_it_still_rejects_candidates(self, probe: dict):
        """⚠️ 판정 개수가 맞는다고 검수가 일하는 것은 아니다.

        "전부 통과"로 답해도 개수는 맞는다 — 그러면 fail-open 과 결과가 같다. 반려가 실제로
        나오는지 봐야 이 처방이 검수를 살렸다고 말할 수 있다.
        """
        rejected = [r["rejected"] for r in rounds(probe, "one_based")]
        assert all(n > 0 for n in rejected), f"반려가 0인 라운드가 있다: {rejected}"


BASELINE = ["2026-08-03_room_ab_critique1.json", "2026-08-03_room_ab2_critique1.json"]
"""고치기 **전**의 같은 설정(`critique_max_attempts=1`, 0-based). #28 에서 얼린 것이다."""

TREATMENT = ["2026-08-03_room_index1_run1.json", "2026-08-03_room_index1_run2.json"]

CEILING = 10.0
"""사용자 확정 응답 상한 (2026-08-03). -237 을 기각한 자다."""


class TestTheRoomEvalConfirmsTheFix:
    """방 평가 2회 — **이 티켓의 목적이 달성됐는지.**

    지표는 새로 만들지 않는다. `test_snapshot_critique_ab.py` 의 `META_VERBS`·`meta_ratio`·
    `round_seconds` 를 그대로 쓴다(#28·#29 와 같은 자로 재야 비교가 성립한다).
    """

    @pytest.mark.parametrize("name", TREATMENT)
    def test_fail_open_never_fired(self, name: str):
        """**이 티켓의 목적.** 30라운드 전부에서 검수가 실제로 걸려야 한다.

        ⚠️ `is False` 로 본다. `.get()` 의 falsy 검사는 **필드가 없거나 `null` 이어도**
        통과해서 "안 걸렸다"와 "기록이 없다"를 구분 못 한다(2026-08-03 리뷰 P2-1: `null`
        위조가 466 green 을 유지했다).
        """
        snapshot = load(name)
        for room in snapshot["rooms"].values():
            for r in room["rounds"]:
                assert r["critique_failed_open"] is False, f"{name}: {r['repeat']}회 {r}"

    @pytest.mark.parametrize("name", TREATMENT)
    def test_the_thirty_rounds_are_all_there_and_alive(self, name: str):
        """문서가 "0/30"·"1/30" 이라 쓰는데 **분모를 아무도 안 박고 있었다**(리뷰 P2-2).

        게다가 `round_seconds()` 가 error 라운드를 걸러내므로, 느린 라운드를 error 로 표시하면
        지연 주장이 통째로 무력화된다.
        """
        snapshot = load(name)
        rounds_ = [r for room in snapshot["rooms"].values() for r in room["rounds"]]
        assert len(rounds_) == 30, f"{name}: 라운드가 {len(rounds_)}개다"
        assert [r for r in rounds_ if r["error"]] == [], f"{name}: 에러 라운드가 있다"

    @pytest.mark.parametrize("name", TREATMENT)
    def test_it_used_the_same_fixtures_as_the_baseline(self, name: str):
        """픽스처가 다르면 기준선과 비교가 성립하지 않는다(리뷰 P2-3)."""
        assert load(name)["fixture_digests"] == load(BASELINE[0])["fixture_digests"]

    def test_the_baseline_has_no_counter_so_it_cannot_be_compared(self):
        """기준선에는 그 값이 **없다**. "0 → 0" 이라고 쓰면 안 된다는 근거."""
        for name in BASELINE:
            snapshot = load(name)
            missing = [
                r
                for room in snapshot["rooms"].values()
                for r in room["rounds"]
                if "critique_failed_open" not in r
            ]
            assert missing, f"{name}: 기준선에 계수기가 생겼다 — 서술을 고쳐야 한다"

    @pytest.mark.parametrize("name", TREATMENT)
    def test_the_setting_matches_the_baseline(self, name: str):
        """설정이 다르면 A/B 가 아니다."""
        snapshot = load(name)
        assert snapshot["critique_max_attempts"] == 1
        assert snapshot["regenerate_on_partial_reject"] is False
        assert snapshot["rounds"] == 3
        assert snapshot["repeats"] == 5

    @pytest.mark.parametrize("slug", ["busan_travel", "opic_study"])
    def test_the_candidate_count_did_not_collapse(self, slug: str):
        """검수가 이제 실제로 걸리므로 후보가 줄 수 있다 — 무너지지는 않았는지 본다."""

        def total(name: str) -> int:
            return sum(len(r["candidates"]) for r in load(name)["rooms"][slug]["rounds"])

        floor = 0.8 * min(total(n) for n in BASELINE)
        for name in TREATMENT:
            assert total(name) >= floor, f"{name}/{slug}: {total(name)} < {floor:.0f}"

    @pytest.mark.parametrize("slug", ["busan_travel", "opic_study"])
    def test_quality_cannot_be_claimed_to_have_improved(self, slug: str):
        """🔴 **과장 방지선** — 조건 간 차이가 조건 **안**의 편차보다 작다.

        `test_snapshot_critique_ab.py::test_neither_wins_on_the_metric` 과 같은 자다.
        ⚠️ 처음에는 `max(처치군) > min(기준선)` 만 걸었는데, 그건 "처치군 전부가 기준선
        전부를 이겼을 때"만 깨져서 **처치군 평균이 뚜렷이 좋아도 통과**한다(2026-08-03 리뷰
        P2-5). 이 데이터에서는 더 강한 형태가 그냥 성립한다.

        ⚠️ **좋은 소식이 오면 실패하는 역방향 단언이다.** 깨졌다면 고칠 것은 코드가 아니라
        `docs/EXPERIMENTS.md` #30 ⑤ 의 "구분되지 않는다" 서술이다.
        """
        base = [meta_ratio(load(n), slug) for n in BASELINE]
        treat = [meta_ratio(load(n), slug) for n in TREATMENT]
        between = abs(sum(base) / len(base) - sum(treat) / len(treat))
        within = max(max(base) - min(base), max(treat) - min(treat))
        assert between < within, (
            f"{slug}: 조건 간 차이 {between:.4f} 가 조건 안 편차 {within:.4f} 를 넘었다 — "
            "이제 개선/악화를 주장할 수 있으니 #30 을 고쳐야 한다"
        )

    def test_the_ceiling_is_breached_no_more_often_than_the_baseline(self):
        """지연이 나빠지지 않았는지. -237 은 여기서 기각됐다(11/30·12/30)."""

        def over(name: str) -> int:
            return sum(1 for s in round_seconds(load(name)) if s > CEILING)

        assert max(over(n) for n in TREATMENT) <= max(over(n) for n in BASELINE)

    def test_the_average_did_not_beat_the_baseline(self):
        """⚠️ **#30 ⑤ 가 한 번 틀렸던 자리다** (2026-08-03 리뷰 P1-3).

        초안이 "중앙값·평균이 기준선보다 빠르다"고 썼는데, 처치군 평균 하나(6.387초)가
        기준선 최댓값(6.221초)보다 높다. 그때 이 값들을 단언하는 테스트가 하나도 없었다.
        """
        means = {n: statistics.mean(round_seconds(load(n))) for n in BASELINE + TREATMENT}
        assert max(means[n] for n in TREATMENT) > max(means[n] for n in BASELINE), (
            f"처치군 평균이 기준선을 전부 이겼다 — #30 ⑤ 를 고쳐야 한다: {means}"
        )

    def test_the_worst_single_round_got_slower(self):
        """⚠️ **불리한 사실도 못 박는다.** 최악값은 커졌다(10.88 → 14.31초).

        같은 실행의 차순위가 7.09초라 단발 스파이크로 보이지만, "지연이 나아졌다"고 쓰지
        못하게 여기 남긴다.
        """
        worst_treatment = max(max(round_seconds(load(n))) for n in TREATMENT)
        worst_baseline = max(max(round_seconds(load(n))) for n in BASELINE)
        assert worst_treatment > worst_baseline


class TestNearDuplicatesWereNotTheCause:
    """가설 B(약한 형태) 기각 근거 — 뜻이 겹치는 제목은 판정을 합치지 않았다."""

    def test_the_near_dup_batch_never_mismatched(self, probe: dict):
        for condition in CONDITIONS:
            bad = [r for r in mismatches(probe, condition) if r["batch"] == "near_dup"]
            assert bad == [], f"{condition}: {bad}"

    def test_the_near_dup_batch_was_actually_measured(self, probe: dict):
        """기각을 주장하려면 실제로 돌았어야 한다 — 빈 결과로 "문제없음"을 말하면 안 된다."""
        for condition in CONDITIONS:
            ran = [r for r in rounds(probe, condition) if r["batch"] == "near_dup"]
            assert len(ran) == probe["repeats"]
