"""검수 프로브의 순수 로직 — **크레딧 0 · 네트워크 0**

프로브 본체는 실제 LLM 을 부르지만, 렌더링과 판정 분류는 순수 함수다.

**가장 중요한 것은 `TestRenderMatchesProduction` 이다.** 프로브가 운영 `_critique` 와 다른
문자열을 보내면, 재는 것은 운영이 아니라 **프로브 자신**이 된다 — 그런데 숫자는 그럴듯하게
나온다. 여기가 유일한 방어선이다.
"""

import pytest

from evals.probe_critique import (
    BATCHES,
    CONDITIONS,
    build_messages,
    classify,
    render_candidates,
)
from modi_ai import suggest as module
from modi_ai.prompts import CRITIQUE_PROMPT
from modi_ai.schemas import TodoCandidate
from modi_ai.suggest import CRITIQUE_INDEX_BASE, _normalize


def candidates(*titles: str) -> list[TodoCandidate]:
    return [TodoCandidate(title=t) for t in titles]


class TestRenderMatchesProduction:
    """프로브 렌더링 == 운영 `_critique` 가 실제로 보내는 것.

    운영 코드를 읽어 베낀 게 아니라 **가짜 LLM 으로 실제로 나간 메시지를 잡아** 비교한다.

    ⚠️ 비교 기준은 `CRITIQUE_INDEX_BASE` 다 — 운영이 1-based 로 바뀌었으므로
    프로브의 `zero_based` 조건은 이제 **고치기 전의 렌더링**이고, 재현용으로 남겨둔 것이다.
    상수를 함께 옮기면 이 테스트는 통과하므로, "1 부터 시작한다"는 것 자체는 아래
    `TestProductionNumbersFromOne` 이 리터럴로 못박는다.
    """

    def _sent(self, fake_llm, titles: list[str]) -> list:
        llm = fake_llm()
        module._critique(
            {
                "candidates": candidates(*titles),
                "llm": llm,
                "passed": [],
                "rejected": [],
                "attempts": 0,
            }
        )
        assert llm.critique_calls, "검수 호출이 일어나지 않았다 — 테스트가 아무것도 안 재고 있다"
        return llm.critique_calls[0]

    def test_the_human_message_is_byte_identical(self, fake_llm):
        titles = ["감천문화마을 골목 탐방 일정 넣기", "동백섬 산책 동선 확보하기"]
        sent = self._sent(fake_llm, titles)
        expected = f"# 후보\n{render_candidates(titles, start=CRITIQUE_INDEX_BASE)}"
        assert str(sent[-1].content) == expected

    def test_the_system_message_is_the_production_prompt(self, fake_llm):
        sent = self._sent(fake_llm, ["가", "나"])
        assert str(sent[0].content) == CRITIQUE_PROMPT

    def test_build_messages_matches_production_shape(self, fake_llm):
        """메시지 개수·순서·역할까지 같아야 한다 — 본문만 같고 순서가 다르면 다른 실험이다."""
        titles = ["가", "나", "다"]
        sent = self._sent(fake_llm, titles)
        built = build_messages(titles, start=CRITIQUE_INDEX_BASE)
        assert len(built) == len(sent) == 2
        assert [type(m).__name__ for m in built] == [type(m).__name__ for m in sent]
        assert [str(m.content) for m in built] == [str(m.content) for m in sent]

    def test_one_based_is_actually_different(self, fake_llm):
        """조건 둘이 같은 문자열이면 A/B 가 아니다 — 실험이 성립하는지부터 확인한다."""
        titles = ["가", "나"]
        assert render_candidates(titles, start=0) != render_candidates(titles, start=1)


class TestProductionNumbersFromOne:
    """운영이 후보를 **`1.` 부터** 번호 매기는지 — 리터럴로 못박는다.

    이 값이 `0` 으로 되돌아가면 판정이 30회 중 10회 어긋난다(실측:
    `data/snapshots/2026-08-03_critique_index_probe.json`). 상수 하나를 옮기면 다른 테스트는
    전부 따라 움직여 통과하므로, **여기만 리터럴이어야 한다.**
    """

    def test_the_constant_is_one(self):
        assert CRITIQUE_INDEX_BASE == 1

    def test_the_first_line_the_model_sees_starts_with_one(self, fake_llm):
        llm = fake_llm()
        module._critique(
            {
                "candidates": candidates("첫 후보", "둘째 후보"),
                "llm": llm,
                "passed": [],
                "rejected": [],
                "attempts": 0,
            }
        )
        body = str(llm.critique_calls[0][-1].content)
        assert body == "# 후보\n1. 첫 후보\n2. 둘째 후보"

    def test_a_zero_based_verdict_set_is_rejected_by_production(self, fake_llm, caplog):
        """운영이 `0,1` 을 **틀린 번호로** 봐야 한다 — 안 그러면 판정이 한 칸 밀려 적용된다."""
        from modi_ai.schemas import CritiqueResponse, CritiqueVerdict

        llm = fake_llm(
            critique=[
                CritiqueResponse(
                    verdicts=[
                        CritiqueVerdict(index=0, ok=False, reason="반려"),
                        CritiqueVerdict(index=1, ok=True),
                    ]
                )
            ]
        )
        with caplog.at_level("ERROR", logger="modi_ai.suggest"):
            result = module._critique(
                {
                    "candidates": candidates("가", "나"),
                    "llm": llm,
                    "passed": [],
                    "rejected": [],
                    "attempts": 0,
                }
            )
        assert [c.title for c in result["candidates"]] == ["가", "나"], "fail-open 이 안 걸렸다"
        assert any("번호가 후보와 안 맞는다" in r.getMessage() for r in caplog.records)


class TestRenderCandidates:
    def test_zero_based_starts_at_zero(self):
        assert render_candidates(["가", "나"], start=0) == "0. 가\n1. 나"

    def test_one_based_starts_at_one(self):
        assert render_candidates(["가", "나"], start=1) == "1. 가\n2. 나"

    def test_an_empty_batch_renders_empty(self):
        assert render_candidates([], start=0) == ""


class TestClassify:
    """운영 `_critique` 의 두 검사를 **같은 순서로** 흉내내는지.

    순서가 뒤바뀌면 "개수가 모자란다"와 "번호가 어긋난다"를 프로브가 반대로 기록한다 —
    그러면 이 티켓의 결론(어느 가설이 맞는가)이 뒤집힌다.
    """

    def test_a_full_matching_set_is_ok(self):
        assert classify([0, 1, 2], candidates=3, start=0) == "ok"

    def test_one_based_full_set_is_ok(self):
        assert classify([1, 2, 3], candidates=3, start=1) == "ok"

    def test_a_missing_verdict_is_a_count_mismatch(self):
        assert classify([0, 1], candidates=3, start=0) == "count_mismatch"

    def test_an_extra_verdict_is_a_count_mismatch(self):
        assert classify([0, 1, 2, 3], candidates=3, start=0) == "count_mismatch"

    def test_right_count_wrong_numbers_is_an_index_mismatch(self):
        """이게 "모델이 1부터 셌다"의 신호다 — 개수는 맞고 번호만 밀린다."""
        assert classify([1, 2, 3], candidates=3, start=0) == "index_mismatch"

    def test_duplicated_indices_are_caught_as_index_mismatch(self):
        """개수는 맞는데 같은 번호가 두 번 오는 경우. 집합이 작아져 걸린다."""
        assert classify([0, 0, 1], candidates=3, start=0) == "index_mismatch"

    def test_count_is_checked_before_numbers(self):
        """개수·번호가 **둘 다** 틀리면 운영은 개수를 먼저 찍는다. 프로브도 그래야 한다."""
        assert classify([5, 6], candidates=3, start=0) == "count_mismatch"


class TestBatches:
    """프로브 입력이 실제로 검수까지 도달할 수 있는 모양인지."""

    @pytest.mark.parametrize("name", sorted(BATCHES))
    def test_no_batch_has_titles_that_filter_candidates_would_drop(self, name: str):
        """⚠️ **글자가 같은 제목은 운영에서 검수까지 못 간다.**

        `filter_candidates` 가 `_normalize` 기준 중복을 검수 **전에** 버린다. 프로브 묶음에
        그런 쌍이 있으면 운영에서 절대 안 생기는 입력을 재게 된다 — `near_dup` 묶음도
        "뜻이 비슷한" 쌍이어야 하고 "글자가 같은" 쌍이면 안 된다.
        """
        titles = BATCHES[name]
        normalized = [_normalize(t) for t in titles]
        assert len(set(normalized)) == len(titles), (
            f"{name} 에 정규화 후 같아지는 제목이 있다 — 운영에서는 검수까지 못 가는 입력이다"
        )

    @pytest.mark.parametrize("name", sorted(BATCHES))
    def test_no_title_exceeds_the_production_limit(self, name: str):
        """`MAX_TITLE_LENGTH` 를 넘는 제목도 `filter_candidates` 가 버린다."""
        for title in BATCHES[name]:
            assert len(title) <= module.MAX_TITLE_LENGTH, f"{name}: {title}"

    def test_the_near_dup_batch_really_contains_a_near_duplicate(self):
        """가설 B 묶음이 그 역할을 하는지 — 안 그러면 조건 하나가 헛돈다."""
        titles = BATCHES["near_dup"]
        kalguksu = [t for t in titles if "칼국수" in t]
        assert len(kalguksu) >= 2, "near_dup 묶음에 뜻이 겹치는 쌍이 없다"

    def test_conditions_cover_both_numbering_schemes(self):
        assert set(CONDITIONS.values()) == {0, 1}
