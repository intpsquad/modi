"""후보 의미 중복 제거.

`filter_candidates` 의 문자열 정규화가 못 잡는 층을 검증한다. 실제 임베딩 API 를 부르지
않는다 — 벡터를 직접 정해야 "임계값 위/아래"가 확정적으로 갈린다(`FakeEmbedder`).
"""

import logging

from modi_ai.schemas import TodoCandidate
from modi_ai.suggest import (
    SEMANTIC_DUPLICATE_THRESHOLD,
    _drop_semantic_duplicates_safely,
    drop_semantic_duplicates,
)


def _candidate(title: str) -> TodoCandidate:
    return TodoCandidate(title=title, source_item_id=12)


class TestDropSemanticDuplicates:
    def test_drops_a_candidate_that_means_the_same_as_an_excluded_one(self, fake_embedder):
        """이 티켓의 본체. 글자는 달라도 벡터가 같으면 버린다."""
        embed = fake_embedder(
            {
                "유튜브 모의고사로 주제별 답변 구조 연습하기": [1.0, 0.0],
                "모바일 유튜브 모의고사를 활용해 주제별 답변 구조 연습하기": [1.0, 0.0],
            }
        )

        kept = drop_semantic_duplicates(
            [_candidate("유튜브 모의고사로 주제별 답변 구조 연습하기")],
            ["모바일 유튜브 모의고사를 활용해 주제별 답변 구조 연습하기"],
            embed,
            threshold=0.8,
        )

        assert kept == []

    def test_keeps_a_candidate_that_is_merely_the_same_topic(self, fake_embedder):
        """같은 도메인(오픽)이라고 버리면 안 된다 — 다른 행동은 다른 후보다."""
        embed = fake_embedder(
            {
                "시험에서 스킵할 문제 과감히 넘기는 연습하기": [1.0, 0.0],
                "시험 전 과거시제 점검하기": [0.0, 1.0],
            }
        )

        kept = drop_semantic_duplicates(
            [_candidate("시험에서 스킵할 문제 과감히 넘기는 연습하기")],
            ["시험 전 과거시제 점검하기"],
            embed,
            threshold=0.8,
        )

        assert [c.title for c in kept] == ["시험에서 스킵할 문제 과감히 넘기는 연습하기"]

    def test_drops_near_duplicates_inside_one_round(self, fake_embedder):
        """한 회차 안에서도 LLM 이 근접 중복을 낸다 — 먼저 나온 것만 살린다."""
        embed = fake_embedder(
            {
                "이미 본 것": [0.0, 1.0],
                "유튜브 모의고사로 답변 구조 연습하기": [1.0, 0.0],
                "유튜브 모의고사 활용해 답변 구조 연습하기": [1.0, 0.0],
            }
        )

        kept = drop_semantic_duplicates(
            [
                _candidate("유튜브 모의고사로 답변 구조 연습하기"),
                _candidate("유튜브 모의고사 활용해 답변 구조 연습하기"),
            ],
            ["이미 본 것"],
            embed,
            threshold=0.8,
        )

        assert [c.title for c in kept] == ["유튜브 모의고사로 답변 구조 연습하기"]

    def test_does_not_call_the_api_when_there_is_nothing_to_compare(self, fake_embedder):
        """후보 1개 + 제외 0개 = 비교 대상이 없다. 지연을 쓰지 않는다."""
        embed = fake_embedder()

        kept = drop_semantic_duplicates([_candidate("답변 틀 만들기")], [], embed, threshold=0.8)

        assert [c.title for c in kept] == ["답변 틀 만들기"]
        assert embed.calls == []

    def test_still_dedupes_within_the_first_round(self, fake_embedder):
        """제외 목록이 비어도 후보끼리는 비교한다 — 첫 추천에서도 회차 내 중복은 걸린다.

        처음에는 `not excluded` 로 통째로 건너뛰어서 이 경로가 죽어 있었다(리뷰 P2-3).
        docstring 이 "비교 대상은 둘"이라고 무조건적으로 주장하는데 실제로는 첫 회차에
        ②가 꺼져 있었던 것 — 주장과 구현을 일치시켰다.
        """
        embed = fake_embedder({"같은 뜻 A": [1.0, 0.0], "같은 뜻 B": [1.0, 0.0]})

        kept = drop_semantic_duplicates(
            [_candidate("같은 뜻 A"), _candidate("같은 뜻 B")], [], embed, threshold=0.8
        )

        assert [c.title for c in kept] == ["같은 뜻 A"]
        assert embed.calls == [["같은 뜻 A", "같은 뜻 B"]]

    def test_does_not_call_the_api_when_there_are_no_candidates(self, fake_embedder):
        embed = fake_embedder()

        assert drop_semantic_duplicates([], ["이미 본 것"], embed, threshold=0.8) == []
        assert embed.calls == []

    def test_sends_excluded_and_candidates_in_one_batch(self, fake_embedder):
        """제목마다 호출하면 추천 1회에 최대 58번을 부른다 — 배치 1회여야 한다."""
        embed = fake_embedder()

        drop_semantic_duplicates(
            [_candidate("후보1"), _candidate("후보2")],
            ["제외1", "제외2", "제외3"],
            embed,
            threshold=0.8,
        )

        assert len(embed.calls) == 1
        assert embed.calls[0] == ["제외1", "제외2", "제외3", "후보1", "후보2"]

    def test_threshold_boundary_is_inclusive(self, fake_embedder):
        """임계값과 정확히 같으면 버린다 — 경계를 코드로 못 박아 둔다."""
        embed = fake_embedder({"a": [1.0, 0.0], "b": [1.0, 0.0]})

        assert drop_semantic_duplicates([_candidate("a")], ["b"], embed, threshold=1.0) == []


class TestFallback:
    """임베딩 호출이 실패해도 추천은 살아 있어야 한다."""

    def test_returns_string_deduped_result_when_embedding_blows_up(self):
        def exploding(_: list[str]) -> list[list[float]]:
            raise RuntimeError("embedding gateway down")

        kept = _drop_semantic_duplicates_safely(
            [_candidate("답변 틀 만들기")], ["이미 본 것"], exploding
        )

        assert [c.title for c in kept] == ["답변 틀 만들기"]

    def test_uses_the_measured_threshold(self, fake_embedder, caplog):
        """상수를 실제로 쓰는지 — 값 자체의 근거는 suggest.py docstring 과 EXPERIMENTS #17.

        **ERROR 로그가 없음을 함께 단언한다.** 이게 없으면 "임계값을 지켰다"와 "층이 예외로
        죽어 폴백이 원본을 돌려줬다"가 같은 결과라서 테스트가 아무것도 구분하지 못한다
        (2026-07-30 리뷰 P2-5).
        """
        above = SEMANTIC_DUPLICATE_THRESHOLD + 0.05
        below = SEMANTIC_DUPLICATE_THRESHOLD - 0.05
        embed = fake_embedder(
            {
                "기준": [1.0, 0.0],
                "임계값 위": [above, (1 - above**2) ** 0.5],
                "임계값 아래": [below, (1 - below**2) ** 0.5],
            }
        )

        with caplog.at_level(logging.ERROR, logger="modi_ai.suggest"):
            kept = _drop_semantic_duplicates_safely(
                [_candidate("임계값 위"), _candidate("임계값 아래")], ["기준"], embed
            )

        assert [c.title for c in kept] == ["임계값 아래"]
        assert caplog.records == [], "폴백이 예외를 삼켜 통과한 것이 아님을 확인"
