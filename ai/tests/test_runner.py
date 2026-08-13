"""평가 러너의 순수 함수 — **크레딧 0 · 네트워크 0.**

러너 본체는 실제 LLM 을 부르지만 `summarize`/`build_request`/`run_name` 은 순수 함수다.
리뷰에서 "러너에 테스트가 0개" 로 지적된 공백을 메운다 — 특히 `strip_rule4` 는 **조용히
잘못 자르면 실험 결과 자체가 무효**가 되는 자리다.
"""

import pytest

from evals.dataset import EvalCase
from evals.run_suggest_eval import (
    CaseResult,
    build_request,
    resolve_content,
    run_case,
    run_name,
    summarize,
    title_length_stats,
)
from modi_ai.prompts import SYSTEM_PROMPT
from modi_ai.schemas import SuggestionResponse, TodoCandidate


def _candidate(title: str = "제목") -> TodoCandidate:
    return TodoCandidate(title=title, source_item_id=1)


class TestSummarize:
    def _case(self, *, candidates=0, raw=None, dropped=0) -> CaseResult:
        return CaseResult(
            stem="x",
            candidates=[_candidate() for _ in range(candidates)],
            raw_candidate_count=candidates if raw is None else raw,
            dropped_by_filter=dropped,
        )

    def test_counts_candidates_and_drops(self):
        results = [self._case(candidates=3, dropped=1), self._case(candidates=2)]

        summary = summarize(results)

        assert summary["cases"] == 2
        assert summary["candidates"] == 5
        assert summary["dropped_by_filter"] == 1

    def test_no_quality_metric_is_produced(self):
        """**품질 지표를 만들지 않는 것이 의도다.**

        자동 채점을 먼저 만들었다가 지표 셋이 전부 무효로 판명된 전례가 있다. 무엇을 재야
        할지 정하기 전에 지표 이름을 붙이면 그 이름이 근거처럼 쓰인다.
        """
        summary = summarize([self._case(candidates=2)])

        for banned in (
            "corruption",
            "corruption_ratio",
            "suspect",
            "suspect_ratio",
            "false_alarms",
            "suppression_ratio",
        ):
            assert banned not in summary, banned

    def test_empty_input_is_safe(self):
        summary = summarize([])

        assert summary["cases"] == 0
        assert summary["candidates"] == 0

    def test_errors_are_counted(self):
        errored = self._case()
        errored.error = "Timeout"

        assert summarize([errored])["errors"] == 1


class TestBuildRequest:
    def test_puts_the_case_text_in_the_archive(self):
        case = EvalCase(stem="001_x", text="본문이다")

        request = build_request(case)

        assert [item.content for item in request.archive] == ["본문이다"]

    def test_room_context_is_fixed_across_cases(self):
        """방 정보가 케이스마다 달라지면 점수 차이가 자료 때문인지 방 때문인지 갈리지 않는다."""
        cases = [EvalCase(stem=s, text="t") for s in ("a", "b")]

        rooms = {build_request(c).room.model_dump_json() for c in cases}

        assert len(rooms) == 1

    def test_explicit_content_replaces_the_case_text(self):
        """`--input summary` 가 지나가는 길 — 원문이 아니라 요약이 들어가야 한다."""
        request = build_request(EvalCase(stem="001_x", text="원문"), content="요약")

        assert [item.content for item in request.archive] == ["요약"]


class TestResolveContent:
    def test_body_mode_returns_the_raw_caption(self):
        assert resolve_content(EvalCase(stem="001_x", text="원문"), "body") == "원문"

    def test_summary_mode_dies_when_the_fixture_is_missing(self):
        """**조용히 원문으로 폴백하면 안 된다** — 리포트에 "요약으로 쟀다" 가 거짓으로 남는다.

        크레딧을 쓰기 **전에** 죽어야 하므로 러너는 호출 루프 앞에서 이걸 전부 부른다.
        """
        with pytest.raises(SystemExit, match="요약 픽스처가 없다"):
            resolve_content(EvalCase(stem="없는_자료", text="원문"), "summary")


class TestRunName:
    """조건이 다른 실행이 **서로를 덮어쓰지 않는지**. 덮어쓰면 A/B 한 짝이 조용히 사라진다.

    ⚠️ **축이 둘로 줄었다** 카테고리·규칙4·스키마 힌트 축은 카테고리 배정을
    걷어내면서 함께 사라졌다. 그 시절 이름(`m_summary_할 일_norule4_noschemahint`)으로 얼린
    스냅샷은 파일로 남아 있고 그 이름을 다시 만들 일은 없다.
    """

    def _name(self, **kwargs) -> str:
        return run_name("m", **({"input_mode": "summary"} | kwargs))

    def test_every_axis_changes_the_name(self):
        assert len({self._name(), self._name(input_mode="body")}) == 2

    def test_the_model_is_in_the_name(self):
        assert self._name().startswith("m_")

    def test_same_condition_gives_the_same_name(self):
        """반복 실행(잡음 바닥 측정)은 **일부러** 덮어쓴다 — `--label` 로 갈라야 한다."""
        assert self._name() == self._name()


class TestTitleLengthStats:
    """[#13] 이 요약 도입 후 쓰기로 한 관측값. **합격선이 아니다.**"""

    def _results(self, *titles: str) -> list[CaseResult]:
        return [CaseResult(stem="x", candidates=[_candidate(t) for t in titles])]

    def test_empty_input_does_not_explode(self):
        """후보가 0개인 실행은 정상 경로다(제외 창이 차면 실제로 그렇게 된다)."""
        assert title_length_stats([]) == {"min": 0, "median": 0, "max": 0, "over_20": 0}

    def test_reports_the_distribution(self):
        stats = title_length_stats(self._results("가" * 8, "가" * 22, "가" * 40))

        assert stats == {"min": 8, "median": 22, "max": 40, "over_20": 2}

    def test_the_threshold_is_exclusive(self):
        """정확히 20자는 초과가 아니다 — 경계에서 개수가 흔들리면 비교가 어긋난다."""
        assert title_length_stats(self._results("가" * 20))["over_20"] == 0


class TestRunCase:
    """🔴 **`run_case` 에 테스트가 없어서 러너가 조용히 빈손이 됐다** (2026-08-04 리뷰 P0-1).

    에서 카테고리 블록을 잘라내며 `result.candidates = kept` 를 같이 지웠다.
    `kept` 가 바로 아래 `len()` 에 쓰여 린트가 안 걸렸고, 이 함수를 부르는 테스트가 하나도
    없어 **417개 초록인 채로 모든 케이스가 후보 0개**를 보고했다. 러너의 존재 이유가
    후보 전문인데 그게 통째로 비었다.

    LLM 은 안 부른다 — `with_structured_output(...).invoke()` 두 가지만 흉내낸 가짜를 쓴다.
    """

    class _Llm:
        def __init__(self, *candidates: TodoCandidate) -> None:
            self._parsed = SuggestionResponse(candidates=list(candidates))

        def with_structured_output(self, schema, include_raw: bool = False):
            parsed = self._parsed

            class _Runnable:
                def invoke(self, messages):
                    return {"raw": None, "parsed": parsed, "parsing_error": None}

            return _Runnable()

    def _case(self) -> EvalCase:
        return EvalCase(stem="001_x", text="성수동 어니언은 10시에 연다")

    def test_the_kept_candidates_reach_the_result(self):
        """이게 비면 후보 전문·제목 길이 분포가 전부 0이 된다."""
        llm = self._Llm(
            TodoCandidate(title="성수동 어니언 영업시간 확인하기", source_item_id=1),
            TodoCandidate(title="원두 사기", source_item_id=1),
        )

        result = run_case(self._case(), llm, SYSTEM_PROMPT, content="성수동 어니언은 10시에 연다")

        assert [c.title for c in result.candidates] == [
            "성수동 어니언 영업시간 확인하기",
            "원두 사기",
        ]
        assert result.raw_candidate_count == 2
        assert result.dropped_by_filter == 0

    def test_a_filtered_candidate_is_counted_but_not_kept(self):
        """`filter_candidates` 가 버린 것은 `dropped_by_filter` 로만 남는다."""
        llm = self._Llm(
            TodoCandidate(title="살아남는 후보", source_item_id=1),
            TodoCandidate(title="없는 자료 참조", source_item_id=999),
        )

        result = run_case(self._case(), llm, SYSTEM_PROMPT, content="성수동 어니언은 10시에 연다")

        assert [c.title for c in result.candidates] == ["살아남는 후보"]
        assert (result.raw_candidate_count, result.dropped_by_filter) == (2, 1)

    def test_the_summary_sees_what_run_case_produced(self):
        """단위로만 재면 `summarize` 와의 연결을 놓친다 — 그게 이번에 뚫린 자리다."""
        llm = self._Llm(TodoCandidate(title="가" * 25, source_item_id=1))

        summary = summarize(
            [run_case(self._case(), llm, SYSTEM_PROMPT, content="성수동 어니언은 10시에 연다")]
        )

        assert summary["candidates"] == 1
        assert summary["title_length"]["max"] == 25
