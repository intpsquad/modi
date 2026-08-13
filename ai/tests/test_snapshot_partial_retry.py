"""`docs/EXPERIMENTS.md` #29 가 인용하는 수치 — 커밋된 스냅샷에서 단언한다. 크레딧 0.

**은 기각됐다.** 이 파일은 "왜 기각인지"를 파일에 못 박아, 다음 사람이
같은 것을 다시 만들지 않게 한다.

지표는 새로 만들지 않는다 — `test_snapshot_critique_ab.py` 의 `META_VERBS` 를 그대로 쓴다.
**닫힌 집합이고 늘려서 결과를 바꾸지 말 것**이라고 그 파일이 못 박아뒀다.

## ⚠️ 평균으로 지연을 판정하지 않는다

리뷰에서 정확히 그걸로 차단당했다 — `seconds_mean < 7.0` 만 봐서 13% 의
상한 위반을 가렸다. 여기서는 **초과 라운드 수와 최악값**을 센다.
"""

import pytest

# **#28 과 #29 를 같은 자로 재는 것이 비교의 전제다.** 초안에 이 셋을 복사해 뒀는데, 정의가
# 두 곳에 있으면 한쪽만 바뀌어도 두 실험이 조용히 갈린다(2026-08-03 리뷰 P2).
from tests.test_snapshot_critique_ab import load, meta_ratio, round_seconds

CEILING = 10.0
"""사용자 확정 응답 상한 (2026-08-03). 착수 시점에 7초에서 상향했다 — 그러고도 깨졌다."""

BASELINE = ["2026-08-03_room_ab_critique1.json", "2026-08-03_room_ab2_critique1.json"]
"""현재 dev = 검수만(`critique_max_attempts=1`). #28 에서 얼린 것을 재사용한다.

재실행 없이 비교할 수 있는 근거는 `tests/test_partial_retry.py` 다 — 스위치가 꺼져 있으면
모든 경로가 -235 와 같다는 것을 거기서 고정한다.
"""

TREATMENT = ["2026-08-03_room_partial_run1.json", "2026-08-03_room_partial_run2.json"]


def total_candidates(snapshot: dict, slug: str) -> int:
    return sum(len(r["candidates"]) for r in snapshot["rooms"][slug]["rounds"] if not r["error"])


def baseline_meta(slug: str) -> list[float]:
    """기준선 두 실행의 메타 행위 비율.

    **리터럴 임계값을 쓰지 않는 이유**: 초안에 표에 적힌 반올림 값(`6.6%`)을 그대로
    `< 0.066` 으로 썼는데 기준선 실측이 **6.5574%** 라 기준선도 통과했다 — 가르지 못하는
    단언이었다(2026-08-03 리뷰 P1-3). 실제 값과 직접 비교한다.
    """
    return [meta_ratio(load(n), slug) for n in BASELINE]


class TestConditionsAreDistinct:
    """조건이 파일에 안 박혀 있으면 A/B 가 성립하지 않는다(-235 의 P8 과 같은 함정)."""

    @pytest.mark.parametrize("name", TREATMENT)
    def test_treatment_records_both_switches(self, name):
        snapshot = load(name)
        assert snapshot["critique_max_attempts"] == 2
        assert snapshot["regenerate_on_partial_reject"] is True

    @pytest.mark.parametrize("name", BASELINE)
    def test_baseline_had_no_partial_retry(self, name):
        """#28 스냅샷은 이 기능이 생기기 **전에** 얼렸다 — 키가 없는 것이 곧 꺼짐이다."""
        snapshot = load(name)
        assert snapshot["critique_max_attempts"] == 1
        assert snapshot.get("regenerate_on_partial_reject", False) is False


class TestWhyItWasRejected:
    """기각 사유 — **지연**. 두 실행이 거의 붙어서 실행 간 변동으로 설명되지 않는다."""

    @pytest.mark.parametrize("name", BASELINE)
    def test_the_baseline_almost_never_breaches(self, name):
        seconds = round_seconds(load(name))
        over = [s for s in seconds if s >= CEILING]
        assert len(over) <= 1, f"기준선이 상한을 {len(over)}번 넘었다 — 비교의 전제가 깨진다"

    @pytest.mark.parametrize("name", TREATMENT)
    def test_the_treatment_breaches_a_third_of_the_time(self, name):
        seconds = round_seconds(load(name))
        over = [s for s in seconds if s >= CEILING]
        assert len(over) / len(seconds) >= 0.35, "37%·40% 로 기록한 수치가 재현되지 않는다"

    @pytest.mark.parametrize("name", TREATMENT)
    def test_the_worst_round_is_far_past_the_ceiling(self, name):
        """최악값이 상한의 1.35배를 넘는다(13.78초 · 15.46초). 기준선 최악은 10.88초다."""
        assert max(round_seconds(load(name))) > CEILING * 1.35

    def test_the_two_runs_agree(self):
        """실행 간 차이가 효과보다 훨씬 작다 — #28 ① 에서 한 번 데인 확인이다."""
        rates = [
            len([s for s in round_seconds(load(n)) if s >= CEILING]) / len(round_seconds(load(n)))
            for n in TREATMENT
        ]
        assert abs(rates[0] - rates[1]) < 0.10, f"두 실행이 갈린다: {rates}"


class TestTheEffectPointsBothWays:
    """**방마다 방향이 반대다.** 이게 이 실험에서 제일 중요한 관측이다."""

    @pytest.mark.parametrize("name", TREATMENT)
    def test_busan_is_above_both_baselines(self, name):
        """하필 사용자가 불만을 제기한 방에서 올라갔다 — 기준선 **두 실행 모두**를 넘는다.

        ⚠️ **"나빠졌다"고 단정하지 않는다.** 기준선이 0.0% ↔ 5.9% 로 흔들리고(폭 5.9%p)
        군간 차가 7.2%p 라 **1.2배밖에 안 된다.** 지연에서는 3%p 흔들림 대비 34%p 효과였는데
        여기는 그 대비가 없다 — 같은 잣대를 대면 "흔들림과 크기가 비슷하다"가 정확하다
        (2026-08-03 리뷰 P2). 기각 사유는 이것이 아니라 지연이다.
        """
        assert meta_ratio(load(name), "busan_travel") > max(baseline_meta("busan_travel"))

    @pytest.mark.parametrize("name", TREATMENT)
    def test_opic_is_below_both_baselines(self, name):
        """반대로 검수가 항상 걸린 방에서는 내려갔다 — 기준선 **두 실행 모두** 아래.

        군간 차 3.5%p 대 군내 흔들림 1.4%p 로 **2.5배**다. 부산 쪽(1.2배)보다 견고하다 —
        즉 후보를 늘리면서 나쁜 모양이 준 것은 실제 효과로 볼 만하고, **기각 사유는 품질이
        아니라 지연**이라는 근거가 된다.
        """
        assert meta_ratio(load(name), "opic_study") < min(baseline_meta("opic_study"))

    @pytest.mark.parametrize("name", TREATMENT)
    def test_candidates_did_recover(self, name):
        """이 티켓의 목적 자체는 달성됐다 — 기준선 부산 41·42개, 오픽 55·63개."""
        snapshot = load(name)
        assert total_candidates(snapshot, "busan_travel") > 80
        assert total_candidates(snapshot, "opic_study") > 85
