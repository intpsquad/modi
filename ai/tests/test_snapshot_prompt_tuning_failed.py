"""`docs/EXPERIMENTS.md` **#21** 의 수치 — 커밋된 스냅샷에서 단언한다. 크레딧 0 · 네트워크 0.

**"프롬프트 문구로는 카테고리를 못 고친다"가 이 프로젝트에서 가장 많이 인용되는 실측이다.**
`prompts.py` · `README.md` · `DECISIONS.md` · `specs/OPEN.md` · `PROJECT_PLAN.md` ·
`ai/CLAUDE.md` · `RESTORE-category-assignment.md` · #31 이 전부 이걸 근거로 든다.

⚠️ **그 가드를 한 번 잃을 뻔했다.** 이 카테고리를 걷어내며
`test_snapshot_category_fix.py` 를 통째로 지웠는데, 그 안에 이 단언들이 들어 있었다
(2026-08-04 리뷰 P1-5). 스냅샷 4개는 그대로 커밋돼 있는데 읽는 사람이 사라졌던 것이다.

**여기 있는 단언은 카테고리 기능과 무관하게 성립한다** — 전부 옛 스냅샷 JSON 을 읽을 뿐이고
운영 코드를 부르지 않는다. 그래서 기능이 사라져도 근거는 남는다.

**스냅샷을 고쳐서 통과시키면 안 된다.** 숫자가 바뀌었다면 문서와 스냅샷을 함께 다시 만든다.
"""

import json

import pytest

from evals.dataset import SNAPSHOT_DIR, load_snapshot

PREFIX = "2026-08-01_gpt-5.4-nano_summary_공부"

# #21 ①의 실패한 프롬프트 후보안들 → 새 카테고리 0개
REJECTED = {
    "v2": f"{PREFIX}_rule4v2.json",
    "schema_v2": f"{PREFIX}_hintv2.json",
    "v2_schema_v2": f"{PREFIX}_rule4v2_hintv2.json",
    "v3_schema_v2": f"{PREFIX}_rule4v3_hintv2.json",
}


def _raw(name: str) -> dict:
    return json.loads((SNAPSHOT_DIR / name).read_text(encoding="utf-8"))


class TestPromptTuningFailed:
    """**문구를 어떻게 고쳐도 0개였다.** 이게 판단을 코드로 옮긴 근거였고,
    나중에 코드마저 실패해 기능을 걷어낸 근거의 절반이다(-243, #31).
    """

    @pytest.mark.parametrize("name", REJECTED.values(), ids=list(REJECTED))
    def test_no_new_category(self, name: str):
        assert _raw(name)["summary"]["new_categories"] == 0

    @pytest.mark.parametrize("name", REJECTED.values(), ids=list(REJECTED))
    def test_every_single_candidate_went_to_the_existing_category(self, name: str):
        """0개라는 것보다 이게 더 무섭다 — 모델이 **한 번도 망설이지 않았다.**"""
        categories = {c.category for case in load_snapshot(name) for c in case.candidates}

        assert categories == {"공부"}

    def test_the_candidate_counts_are_frozen(self):
        """ "후보를 못 내서 0개"가 아니라는 확인 — 후보는 충분히 나왔는데 전부 한 곳으로 갔다."""
        counts = {k: _raw(v)["summary"]["candidates"] for k, v in REJECTED.items()}

        assert counts == {"v2": 38, "schema_v2": 33, "v2_schema_v2": 33, "v3_schema_v2": 29}

    def test_four_variants_were_actually_tried(self):
        """ "네 가지 문구를 다 재봤다"가 인용문의 핵심이다 — 표본이 하나였으면 못 할 주장이다."""
        assert len(REJECTED) == 4
        for name in REJECTED.values():
            assert (SNAPSHOT_DIR / name).exists(), name


class TestTheLoaderStillReadsOldSnapshots:
    """🔴 **옛 스냅샷을 못 읽으면 위 단언이 전부 죽는다.**

    -243 이 `TodoCandidate.category` 를 지우면서 `SnapshotCandidate.category` 도 선택 필드가
    됐다. 그 변경이 **옛 파일 읽기를 깨뜨리지 않았는지**를 여기서 고정한다 — 새 스냅샷은
    그 키가 없고 옛 스냅샷은 있다. 둘 다 읽혀야 한다.
    """

    def test_an_old_snapshot_still_carries_its_categories(self):
        cases = load_snapshot(REJECTED["v2"])

        assert any(c.category for case in cases for c in case.candidates)

    def test_a_candidate_without_a_category_key_loads_as_none(self):
        """-243 이후에 얼린 스냅샷의 모양 — 키가 아예 없다."""
        from evals.dataset import SnapshotCandidate

        assert SnapshotCandidate(title="가", source_item_id=1).category is None
