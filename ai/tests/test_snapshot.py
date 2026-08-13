"""동결 스냅샷 검증 — `docs/EXPERIMENTS.md` #13 의 수치를 **실행 가능하게** 만든다.

크레딧 0 · 네트워크 0. 스냅샷은 그때 모델이 실제로 낸 후보를 고정한 파일이고, #13 의 모든
수치는 이 파일에서 뽑았다. 여기서 다시 뽑아 단언하므로 **문서와 파일이 어긋나면 pytest 가
잡는다.**

리뷰에서 실제로 어긋난 것이 잡혔기 때문에 만들었다 — 문서는 temperature 0.0 실행의 숫자를
적어놓고 커밋된 파일은 temperature 미고정 별개 실행이었다. 그 상태로는 아무도 문서를 검증할
수 없었다.

**스냅샷을 고쳐서 통과시키면 안 된다.** 숫자가 바뀌었다면 문서와 스냅샷을 함께 다시 만든다.
"""

import statistics

import pytest

from evals.dataset import load_snapshot

BASELINE = "2026-07-30_gpt-4.1-mini_baseline.json"


@pytest.fixture(scope="module")
def titles() -> list[str]:
    return [c.title for case in load_snapshot(BASELINE) for c in case.candidates]


class TestBaselineSnapshot:
    """#13 "요약 도입 전 기준선" 의 관측값."""

    def test_shape_is_frozen(self):
        cases = load_snapshot(BASELINE)

        assert len(cases) == 15

    def test_candidate_count(self, titles):
        assert len(titles) == 50

    def test_title_length_distribution(self, titles):
        """#13 결론 1 — "제목이 안 간결하다" 의 근거 수치."""
        lengths = [len(t) for t in titles]

        assert min(lengths) == 8
        assert statistics.median(lengths) == 22.5
        assert max(lengths) == 40

    def test_thirty_titles_exceed_twenty_chars(self, titles):
        assert sum(1 for t in titles if len(t) > 20) == 30

    def test_no_candidate_was_dropped_by_the_filter(self):
        """`source_item_id` 위반·중복이 0건이었다 — 필터가 아무것도 버리지 않았다."""
        cases = load_snapshot(BASELINE)

        for case in cases:
            assert case.raw_candidate_count == len(case.candidates), case.stem


class TestQuotedExamples:
    """문서가 인용한 사례가 스냅샷에 **실제로 있는지** 확인한다.

    리뷰에서 잡힌 것: 문서가 인용한 예시 중 여럿이 커밋된 스냅샷에 없었다. 인용을 고칠 때
    이 테스트도 함께 고쳐야 하므로 어긋난 채로 남기 어려워진다.
    """

    @pytest.mark.parametrize(
        "quoted",
        [
            # 결론 1 — 가장 긴 제목
            "2026년 1회 정보처리기사 실기 이론 압축 PDF 다운로드 및 인쇄하기",
            # 결론 2 — 지역명 중복
            "부산 부산진구 히떼 로스터리 커피 메뉴 및 운영시간 알아보기",
            # 결론 3 — 어투 이탈(반말)
            "기출 문제 오답노트 작성하여 실기점수 90점 이상 목표로 하자",
            # 대조 사례 — 장소명만 나열된 자료에서는 짧게 쓴다
            "서울숲 산책하기",
        ],
    )
    def test_example_exists_in_snapshot(self, titles, quoted):
        assert quoted in titles

    def test_region_prefix_is_duplicated_three_times(self, titles):
        """#13 결론 2 — `부산 부산진구 …` 가 3건."""
        duplicated = [t for t in titles if "부산 부산진구" in t]

        assert len(duplicated) == 3

    def test_exactly_one_title_breaks_the_suffix_pattern(self, titles):
        """#13 결론 3 — 49개는 `~기` 로 끝나고 1개만 튄다."""
        outliers = [t for t in titles if not t.endswith("기")]

        assert len(outliers) == 1
