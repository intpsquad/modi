"""`docs/EXPERIMENTS.md` #26 이 인용하는 수치를 **커밋된 스냅샷에서** 단언한다 — 크레딧 0.

## 왜 이 파일이 있는가

러너 출력(`data/room_eval_export.json`)은 `.gitignore` 다. 그 파일의 숫자를 문서에 옮겨 적으면
**나중에 확인할 방법이 사라진다.** 실제로 그 사고가 한 번 났고([#13]), 그래서 이 저장소는
*"EXPERIMENTS 에 적는 숫자는 커밋된 스냅샷에서 나와야 한다"* 를 규칙으로 갖고 있다
(`evals/freeze_snapshot.py`).

`tests/test_snapshot_2026_08_01.py` 가 자료 단위 러너에 대해 하는 일을 **방 단위 러너에 대해**
한다. 처음 #26 을 쓸 때 이 장치를 빠뜨렸고 리뷰에서 지적받았다.

## 끝동사 목록이 여기 있는 이유

#26 의 "실제 행동 14% / 44%" 는 제목의 **끝어절**로 가른 값이다. 그 목록이 문서에만 있으면
다음 사람이 재현할 수 없다(리뷰 지적 — 리뷰어가 목록을 추측해서 맞춰야 했다).
여기 코드로 두면 실행 가능한 기록이 된다.

⚠️ **이건 지표가 아니라 거친 근사다.** 과대계상한다 — `… 묶어서 방문하기` 처럼 동사만 행동인
것이 섞인다. #26 이 그 점을 명시하고 눈으로 센 값(약 10%)을 따로 적어뒀다.
"""

import hashlib
import json

import pytest

from evals.rooms import ROOM_DIR
from evals.run_room_eval import MAX_EXCLUDED

SNAPSHOT = "2026-08-03_room_baseline_clean.json"

# 제목 끝어절이 이 목록에 있으면 "실제로 하는 일", 아니면 "계획·확인".
DOING_VERBS = frozenset(
    {
        "먹기",
        "먹어보기",
        "방문하기",
        "예약하기",
        "이동하기",
        "마무리하기",
        "주문하기",
        "산책하기",
        "연습하기",
        "연습",
        "말하기",
        "말해보기",
        "반복",
        "훈련하기",
        "풀기",
        "외우기",
        "만들기",
    }
)


@pytest.fixture(scope="module")
def snapshot() -> dict:
    from evals.dataset import SNAPSHOT_DIR

    return json.loads((SNAPSHOT_DIR / SNAPSHOT).read_text(encoding="utf-8"))


def unique_titles(room: dict) -> list[str]:
    return sorted({c["title"] for r in room["rounds"] for c in r["candidates"]})


class TestConditions:
    """조건이 안 박혀 있으면 숫자는 근거가 못 된다."""

    def test_the_run_conditions(self, snapshot):
        assert snapshot["model"] == "gpt-5.4-nano"
        assert (snapshot["rounds"], snapshot["repeats"]) == (3, 5)
        assert snapshot["start_excluded"] == "fresh"
        assert snapshot["temperature"] == "운영 기본값"

    def test_it_still_describes_the_committed_fixtures(self, snapshot):
        """**픽스처가 바뀌면 이 스냅샷의 수치는 다른 입력에 대한 것이 된다.**

        여기서 걸리면 #26 을 다시 재야 한다 — 해시만 고쳐서 넘어가면 안 된다.
        """
        for slug, expected in snapshot["fixture_digests"].items():
            payload = json.loads((ROOM_DIR / f"{slug}.json").read_text(encoding="utf-8"))
            digest = hashlib.sha256(
                json.dumps(payload["request"], ensure_ascii=False, sort_keys=True).encode()
            ).hexdigest()[:16]

            assert digest == expected, f"{slug} 픽스처가 스냅샷 측정 이후 바뀌었다"

    def test_the_rooms_are_the_two_we_measured(self, snapshot):
        assert set(snapshot["rooms"]) == {"busan_travel", "opic_study"}
        assert snapshot["rooms"]["busan_travel"]["summary"]["archive_items"] == 13
        assert snapshot["rooms"]["opic_study"]["summary"]["archive_items"] == 21


class TestDryingUp:
    """#26 ② — 두 방 모두 회차가 갈수록 후보가 준다."""

    @pytest.mark.parametrize(
        ("slug", "expected"),
        [
            ("busan_travel", [(7.00, 0.00), (4.80, 1.92), (3.40, 1.52)]),
            ("opic_study", [(6.20, 1.10), (4.40, 0.89), (4.00, 1.87)]),
        ],
    )
    def test_per_round_means_and_deviations(self, snapshot, slug, expected):
        stats = snapshot["rooms"][slug]["summary"]["per_round"]

        assert [(s["count_mean"], s["count_sd"]) for s in stats] == expected
        assert all(s["samples"] == 5 for s in stats), "표본이 5가 아니면 편차 해석이 달라진다"

    def test_the_deviation_is_wide_enough_to_swallow_small_gains(self, snapshot):
        """**이게 #26 의 요점이다.** 부산 2회차는 최소 3 · 최대 8이 나왔다 — 이 폭 안에서는
        프롬프트를 고쳐 2~3개가 늘어도 개선인지 잡음인지 못 가른다."""
        second = snapshot["rooms"]["busan_travel"]["summary"]["per_round"][1]

        assert (second["count_min"], second["count_max"]) == (3, 8)


class TestActionVerbs:
    """#26 ③ — 여행 방에서만 '실제로 하는 일'이 안 나온다. **다른 데이터에서 재현됐다.**"""

    @pytest.mark.parametrize(
        ("slug", "doing", "total"),
        [("busan_travel", 10, 74), ("opic_study", 31, 71)],
    )
    def test_the_ratio_documents_quote(self, snapshot, slug, doing, total):
        titles = unique_titles(snapshot["rooms"][slug])

        assert len(titles) == total
        assert sum(1 for t in titles if t.split()[-1] in DOING_VERBS) == doing

    def test_the_travel_room_is_far_worse(self, snapshot):
        """수치가 흔들려도 **방향**은 유지돼야 한다 — 이게 #26 의 결론이다."""
        ratios = {}
        for slug, room in snapshot["rooms"].items():
            titles = unique_titles(room)
            ratios[slug] = sum(1 for t in titles if t.split()[-1] in DOING_VERBS) / len(titles)

        assert ratios["busan_travel"] < 0.20 < 0.40 < ratios["opic_study"]


class TestCategorySprawl:
    """#26 ④ — 기존 카테고리로 접히지 않는 이름이 대부분이다."""

    @pytest.mark.parametrize(
        ("slug", "kinds", "new_kinds"),
        [("busan_travel", 22, 21), ("opic_study", 32, 29)],
    )
    def test_the_counts_documents_quote(self, snapshot, slug, kinds, new_kinds):
        stats = snapshot["rooms"][slug]["summary"]["categories"]

        assert (stats["kinds"], stats["new_kinds"]) == (kinds, new_kinds)

    def test_whitespace_only_variants_are_present(self, snapshot):
        """이 고치는 대상이 이 기준선에 실제로 있다는 증거.

        236 이후 스냅샷에서는 이 쌍들이 하나로 접혀야 한다 — 없어졌는지 확인할 대조군이다.
        """
        names = set(snapshot["rooms"]["opic_study"]["summary"]["categories"]["new_names"])

        assert {"시험 준비", "시험준비"} <= names
        assert {"오픽 준비", "오픽준비"} <= names


class TestTitleLength:
    """#26 ⑤ — 관측이지 합격선이 아니다."""

    @pytest.mark.parametrize(
        ("slug", "median", "over"),
        [("busan_travel", 21.0, 43), ("opic_study", 23, 64)],
    )
    def test_the_distribution_documents_quote(self, snapshot, slug, median, over):
        stats = snapshot["rooms"][slug]["summary"]["title_length"]

        assert stats["median"] == median
        assert stats["over_20"] == over


class TestNoErrors:
    def test_every_round_succeeded(self, snapshot):
        """오류가 섞였으면 회차 평균이 그만큼 적은 표본에서 나온 것이다."""
        for slug, room in snapshot["rooms"].items():
            assert room["summary"]["errors"] == 0, f"{slug} 에 실패 라운드가 있다"
            assert len(room["rounds"]) == 15, f"{slug}: 3라운드 × 5반복 = 15가 아니다"

    def test_the_exclusion_window_never_exceeded_the_server_cap(self, snapshot):
        """실행 기록으로도 상한을 확인한다 — 단위 테스트와 별개의 증거다."""
        for room in snapshot["rooms"].values():
            assert max(r["excluded_before"] for r in room["rounds"]) <= MAX_EXCLUDED
