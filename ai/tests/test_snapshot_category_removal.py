"""`docs/EXPERIMENTS.md` #31 이 인용하는 수치 — 커밋된 스냅샷에서 단언한다. 크레딧 0.

**카테고리 배정을 걷어낸 근거가 이 파일이다** 기능은 지웠지만 "왜 지웠나"의
증거는 남겨야 한다 — 그러지 않으면 다음 사람이 같은 것을 세 번째로 다시 만든다.

🔴 **프로브 코드는 어디에도 없다.** 제거한 심볼(`CATEGORIZE_PROMPT`·`CategorizeResponse`)을
참조해 트리에 못 두는데, 그 브랜치를 **원격에 push 한 적이 없다** — 즉
재생성이 불가능하다(2026-08-04 리뷰 P1-2). 여기서는 **커밋된 스냅샷 JSON 만 읽는다.**

⚠️ **이 파일은 기능이 되살아나도 아무 말 안 한다.** 측정을 고정할 뿐 코드를 막지 않는다 —
그건 `test_suggest_graph::test_the_category_node_is_gone` 과 `test_suggest.py` 의 계약
테스트가 한다. 여기서 다는 것은 **핵심 결론**이지 개별 수치 전부가 아니다.

⚠️ **후보당 카테고리 종수가 지표다** — 세션당 종수나 실행 합집합이 아니다. 합집합을 사용자
경험처럼 읽는 오독을 두 번 했다(#30 리뷰 · #31 ③).
"""

import json
import pathlib
import statistics

import pytest

SNAPSHOTS = pathlib.Path(__file__).parent.parent / "evals" / "data" / "snapshots"

BASELINE = [  # 임베딩 (에서 얼린 것 + 채택 흉내 대조군)
    "2026-08-03_room_index1_run1.json",
    "2026-08-03_room_index1_run2.json",
    "2026-08-04_room_embed_adopt.json",
]
TREATMENT = [  # LLM 별도 호출
    "2026-08-04_room_llmcat_run1.json",
    "2026-08-04_room_llmcat_adopt.json",
]
ROOMS = ("busan_travel", "opic_study")


def load(name: str) -> dict:
    return json.loads((SNAPSHOTS / name).read_text(encoding="utf-8"))


def kinds_per_candidate(snapshot: dict, slug: str) -> float:
    """라운드(시트) 하나에서 **후보 하나당 카테고리 몇 종**인가. 낮을수록 좋다.

    `1.0` 이면 후보마다 카테고리를 새로 만든다는 뜻이다. [#27] 이 정한 지표이고
    거기 적힌 당시 값이 0.62~0.85 다.
    """
    rounds = [r for r in snapshot["rooms"][slug]["rounds"] if r["candidates"]]
    return statistics.mean(
        len({c["category"] for c in r["candidates"] if c.get("category")}) / len(r["candidates"])
        for r in rounds
    )


class TestTheEvidenceIsOnFile:
    """수치를 읽기 전에 **파일이 실제로 있는지** 본다."""

    @pytest.mark.parametrize("name", BASELINE + TREATMENT)
    def test_the_snapshot_exists(self, name: str):
        assert (SNAPSHOTS / name).exists(), f"{name} 이 없다 — #31 의 근거가 끊긴다"

    @pytest.mark.parametrize("name", BASELINE + TREATMENT)
    def test_no_round_died(self, name: str):
        """에러 라운드가 섞이면 평균이 거짓말을 한다."""
        dead = [r for room in load(name)["rooms"].values() for r in room["rounds"] if r["error"]]
        assert dead == [], f"{name}: 에러 라운드 {len(dead)}건"

    @pytest.mark.parametrize("name", BASELINE + TREATMENT)
    def test_the_setting_is_recorded(self, name: str):
        """조건이 파일에 안 박혀 있으면 A/B 가 아니다."""
        snapshot = load(name)
        assert snapshot["critique_max_attempts"] == 1
        assert snapshot["rounds"] == 3
        assert snapshot["repeats"] == 5

    def test_the_two_arms_are_labelled_apart(self):
        """⚠️ **조건이 스냅샷에 안 박혀 있다. 이건 약한 검증이다.**

        `freeze_snapshot` 이 옮기는 필드는 고정 목록이라 `categorize_with_llm` 이 안 들어갔다
        (러너 export 에는 있었다). 그래서 어느 실행이 어느 팔인지 아는 근거가 **내가 붙인
        `--label` 문자열뿐**이다 — 설정 기록이 아니라 이름이다.

        같은 결함을 이 저장소가 이미 한 번 잡았다("freeze_snapshot 이 조건을 안 옮기고 있던
        것"). 고치려면 `freeze_snapshot` 이 조건 필드를 통째로 옮겨야 하는데, 그 설정 자체가
        에서 사라져 지금은 옮길 것이 없다 → `specs/OPEN.md` 후속 항목.

        보조 근거: 측정 날짜(`index1_*` 는 2026-08-03, -242 착수 전이라 임베딩 경로다)와
        결과의 모양(아래 `TestTheLlmPathWasWorse`)이 라벨과 일치한다.
        """
        assert load("2026-08-04_room_embed_adopt.json")["run"] == "embed_adopt"
        assert {load(n)["run"] for n in TREATMENT} == {"llmcat_run1", "llmcat_adopt"}
        assert all(load(n)["measured_at"].startswith("2026-08-03") for n in BASELINE[:2])


class TestTheLlmPathWasWorse:
    """🔴 **기각 근거.** LLM 이 이긴 칸이 하나도 없다."""

    @pytest.mark.parametrize("slug", ROOMS)
    def test_every_treatment_run_is_worse_than_every_baseline_run(self, slug: str):
        base = [kinds_per_candidate(load(n), slug) for n in BASELINE]
        treat = [kinds_per_candidate(load(n), slug) for n in TREATMENT]

        assert min(treat) > max(base), (
            f"{slug}: 처치군이 기준선을 이겼다 — #31 ② 의 결론을 고쳐야 한다. "
            f"기준선 {[round(x, 2) for x in base]} · 처치군 {[round(x, 2) for x in treat]}"
        )

    def test_opic_is_outside_the_noise(self):
        """오픽은 **확실하다** — 가장 작은 쌍별 차이가 기준선 편차보다 크다."""
        base = [kinds_per_candidate(load(n), "opic_study") for n in BASELINE]
        treat = [kinds_per_candidate(load(n), "opic_study") for n in TREATMENT]
        smallest_gap = min(t - b for b in base for t in treat)
        baseline_spread = max(base) - min(base)

        assert smallest_gap > baseline_spread, (
            f"가장 작은 차이 {smallest_gap:.4f} ≤ 기준선 편차 {baseline_spread:.4f}"
        )

    def test_busan_is_worse_but_inside_the_noise(self):
        """⚠️ **부산은 방향만 맞고 크기는 못 주장한다.** 이걸 숨기지 않는다.

        초안이 `#31 ②` 에 "조건 안 편차가 0.02 인데 차이는 0.08~0.16" 이라고 적었는데
        **틀렸다**(2026-08-04 리뷰 P1-1). 0.02 는 `index1_run{1,2}` 둘만 센 값이고,
        조건을 맞춘 대조군(`embed_adopt`, 0.893)을 넣으면 기준선 편차가 **0.094** 로 커진다.
        짝을 맞춘 비교(채택켬 vs 채택켬)는 **0.0155** 라 그 편차 안이다.

        그래도 5/5 비교에서 전부 LLM 쪽이 나쁘다 — 방향은 일관된다. 그 이상은 말하지 않는다.
        """
        base = [kinds_per_candidate(load(n), "busan_travel") for n in BASELINE]
        treat = [kinds_per_candidate(load(n), "busan_travel") for n in TREATMENT]
        smallest_gap = min(t - b for b in base for t in treat)
        baseline_spread = max(base) - min(base)

        assert smallest_gap > 0, "방향이 뒤집혔다 — #31 ② 의 결론을 고쳐야 한다"
        assert smallest_gap < baseline_spread, (
            f"부산 차이가 편차를 넘었다({smallest_gap:.4f} > {baseline_spread:.4f}) — "
            "이제 크기까지 주장할 수 있으니 #31 ② 와 이 docstring 을 고칠 것"
        )

    def test_almost_one_category_per_candidate(self):
        """**0.97 = 후보 하나당 카테고리 하나.** 고치려던 문제가 심해졌다는 근거."""
        worst = max(kinds_per_candidate(load(n), slug) for n in TREATMENT for slug in ROOMS)
        assert worst >= 0.95, worst


class TestItWasNotRejectedForLatency:
    """⚠️ [#29] 와 기각 사유가 다르다 — **비싸서가 아니라 효과가 없어서**다.

    이걸 안 박아두면 다음 사람이 "더 빠른 모델이면 되겠네"로 오해한다.
    """

    @pytest.mark.parametrize("name", TREATMENT)
    def test_the_ceiling_was_never_breached(self, name: str):
        over = [
            r
            for room in load(name)["rooms"].values()
            for r in room["rounds"]
            if not r["error"] and r["seconds"] > 10.0
        ]
        assert over == [], f"{name}: 10초 초과 {len(over)}건"

    def test_it_was_no_slower_than_the_baseline(self):
        """LLM 호출이 2회 → 3회가 됐는데도 초과가 늘지 않았다."""

        def over(name: str) -> int:
            return sum(
                1
                for room in load(name)["rooms"].values()
                for r in room["rounds"]
                if not r["error"] and r["seconds"] > 10.0
            )

        assert max(over(n) for n in TREATMENT) <= max(over(n) for n in BASELINE)

    @pytest.mark.parametrize("name", TREATMENT)
    def test_the_candidate_count_held(self, name: str):
        """후보가 줄어서 종수가 좋아 보이는 것이 아니라는 확인."""
        snapshot = load(name)
        for slug in ROOMS:
            total = sum(len(r["candidates"]) for r in snapshot["rooms"][slug]["rounds"])
            assert total >= 33, f"{name}/{slug}: 후보 {total}개"


class TestTheProbeSaidTheOppositeOfTheRoomEval:
    """🔴 **프로브만 보고 배포했으면 틀렸을 것이다.** 그 교훈을 남긴다.

    프로브(호출 하나만 격리해 96회)는 통과였는데 방 평가(그래프 전부)가 뒤집었다.
    """

    def test_the_probe_measured_the_production_model(self):
        probe = json.loads(
            (SNAPSHOTS / "2026-08-04_categorize_probe.json").read_text(encoding="utf-8")
        )
        assert set(probe["conditions"].values()) == {"gpt-5-nano", "gpt-5.4-nano"}

    def test_the_small_model_was_ten_times_slower(self):
        """`gpt-5-nano` 를 쓰려다 실측으로 뒤집힌 자리 — 숨은 추론 토큰 때문이다(#14 재현)."""
        probe = json.loads(
            (SNAPSHOTS / "2026-08-04_categorize_probe.json").read_text(encoding="utf-8")
        )
        nano5, nano54 = probe["summary"]["nano5"], probe["summary"]["nano54"]

        assert nano5["seconds_median"] > 10.0, nano5["seconds_median"]
        assert nano54["seconds_median"] < 3.0, nano54["seconds_median"]
        assert nano5["completion_tokens_median"] > 10 * nano54["completion_tokens_median"]

    def test_the_probe_showed_no_collapse(self):
        """[#21] 재현이 아니었다 — 그래서 프로브는 '통과'로 읽혔다."""
        probe = json.loads(
            (SNAPSHOTS / "2026-08-04_categorize_probe.json").read_text(encoding="utf-8")
        )
        for summary in probe["summary"].values():
            assert summary["all_into_one"] == 0

    def test_tightening_the_name_rule_shortened_but_did_not_fix(self):
        """길이는 줄었는데 **제목을 베끼는 성향**은 안 바뀌었다 — 이게 0.97 의 원인이다."""
        loose = json.loads(
            (SNAPSHOTS / "2026-08-04_categorize_probe.json").read_text(encoding="utf-8")
        )
        tight = json.loads(
            (SNAPSHOTS / "2026-08-04_categorize_probe_tight.json").read_text(encoding="utf-8")
        )

        def names(probe: dict) -> list[str]:
            return [
                a["new_name"]
                for r in probe["rounds"]
                if r["condition"] == "nano54" and not r["error"]
                for a in r["assignments"]
                if a["category"] is None and a["new_name"]
            ]

        loose_len = statistics.median(len(n) for n in names(loose))
        tight_len = statistics.median(len(n) for n in names(tight))

        assert tight_len < loose_len, (tight_len, loose_len)
        assert tight_len <= 6, tight_len
        # 그런데 이름 가짓수는 여전히 많다 — 후보마다 하나씩 짓는다는 뜻이다.
        assert len(set(names(tight))) > 80, len(set(names(tight)))
