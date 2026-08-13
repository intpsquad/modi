"""부분 반려분 재생성 — **크레딧 0 · 네트워크 0**

의 루프는 "후보가 **전부** 반려"일 때만 돌아서 운영에서 사실상 안 탔다.
흔한 것은 "3개 통과 · 4개 반려"이고 그 4개는 아무것도 남기지 않았다 — 후보가 88 → 41개로
준 주된 원인이다(`docs/EXPERIMENTS.md` #28 ⑤).

여기서 지켜야 할 것이 셋이다.

1. **스위치가 꺼져 있으면 -235 와 완전히 같아야 한다.** #28 기준선을 재실행 없이 재사용하는
   근거가 이것뿐이다 — 여기가 무너지면 A/B 비교가 통째로 성립하지 않는다.
2. **앞 회차 통과분이 살아 있어야 한다.** `_generate` 가 `candidates` 를 새 배치로 덮으므로,
   누적을 놓치면 재생성이 후보를 늘리는 게 아니라 **바꿔치기**한다.
3. **시도 상한을 절대 넘지 않아야 한다.** 넘으면 응답이 사용자가 정한 10초를 깬다
   (2026-08-03, 7초에서 상향).

가짜 모델·임베더·요청 생성기는 `test_critique.py` 것을 그대로 쓴다 — 같은 루프를 재는
테스트가 서로 다른 가짜를 쓰면 둘 중 하나가 조용히 거짓말을 한다.
"""

import logging

import pytest

from modi_ai import config
from modi_ai import suggest as module
from modi_ai.schemas import CritiqueResponse, CritiqueVerdict
from modi_ai.suggest import CRITIQUE_INDEX_BASE, suggest
from tests.test_critique import ScriptedLlm, _embed, _request, _titles, _verdicts


class BoomOnSecondCritique(ScriptedLlm):
    """**2차 검수만** 터뜨린다.

    `ScriptedLlm(boom=True)` 은 1차부터 터져서 전부 통과가 되고, 그러면 부분 반려 자체가
    안 만들어진다 — 재생성 뒤의 fail-open 을 재려면 1차는 정상이어야 한다.
    """

    def _critique(self, messages):
        self.critique_prompts.append(str(messages[-1].content))
        self.critique_system_prompts.append(str(messages[0].content))
        if len(self.critique_prompts) >= 2:
            raise RuntimeError("검수 게이트웨이 장애")
        return self._critiques.pop(0)


@pytest.fixture
def settings(monkeypatch):
    """`critique_max_attempts` 와 `regenerate_on_partial_reject` 를 함께 갈아끼운다."""

    def _set(max_attempts: int, partial: bool):
        monkeypatch.setattr(
            module,
            "get_settings",
            lambda: config.Settings(
                critique_max_attempts=max_attempts,
                regenerate_on_partial_reject=partial,
            ),
        )

    return _set


class TestTheSwitch:
    """스위치 하나가 -235 와 -237 을 가른다."""

    def test_partial_rejection_regenerates_when_on(self, settings):
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("살아남은 후보", "반려될 후보"), _titles("두번째 후보")],
            [_verdicts(True, False), _verdicts(True)],
        )

        suggest(_request(), llm, _embed)

        assert len(llm.prompts) == 2, "부분 반려인데 재생성이 안 돌았다"

    def test_partial_rejection_stops_when_off(self, settings):
        """**-235 의 동작.** 이 테스트가 #28 기준선 재사용의 근거다.

        여기가 깨지면 `2026-08-03_room_ab*_critique1.json` 을 비교 대상으로 못 쓴다 —
        같은 설정으로 얼렸는데 코드가 다른 일을 하는 셈이 되기 때문이다.
        """
        settings(2, False)
        llm = ScriptedLlm(
            [_titles("살아남은 후보", "반려될 후보"), _titles("두번째 후보")],
            [_verdicts(True, False), _verdicts(True)],
        )

        response = suggest(_request(), llm, _embed)

        assert len(llm.prompts) == 1, "스위치가 꺼져 있는데 재생성이 돌았다"
        assert [c.title for c in response.candidates] == ["살아남은 후보"]

    def test_the_default_is_off(self):
        """근거가 생기기 전까지는 꺼둔다(`ai/CLAUDE.md`: 근거 없이 바꾸지 않는다)."""
        assert config.Settings().regenerate_on_partial_reject is False


class TestAccumulation:
    def test_the_first_round_survivors_are_kept(self, settings):
        """재생성은 후보를 **더하는** 것이지 바꿔치기가 아니다.

        `_generate` 가 `candidates` 를 새 배치로 덮으므로 누적을 놓치면 1회차 승자가
        조용히 사라진다 — 후보 수가 목적인 티켓에서 정확히 반대 결과가 된다.
        """
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("1회차 승자", "1회차 탈락"), _titles("2회차 승자")],
            [_verdicts(True, False), _verdicts(True)],
        )

        response = suggest(_request(), llm, _embed)

        assert [c.title for c in response.candidates] == ["1회차 승자", "2회차 승자"]

    def test_the_second_critique_only_judges_the_new_batch(self, settings):
        """이미 통과한 것을 다시 판정하지 않는다 — 검수 호출을 싸게 유지하는 근거다."""
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("1회차 승자", "1회차 탈락"), _titles("2회차 승자")],
            [_verdicts(True, False), _verdicts(True)],
        )

        suggest(_request(), llm, _embed)

        second = llm.critique_prompts[1]
        assert "2회차 승자" in second
        assert "1회차 승자" not in second, "통과분을 검수에 다시 보냈다"

    def test_a_repeat_of_an_accepted_title_is_dropped(self, settings):
        """재생성 배치가 통과분과 글자가 같으면 문자열 층에서 버린다.

        `filter_candidates` 의 `known` 은 `existing_todos + excluded_todos` 만 봐서 누적분을
        모른다. 의미 중복층이 결국 잡기는 하지만(같은 문자열 = 코사인 1.0) 임베딩 왕복에
        기대지 않는다.
        """
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("1회차 승자", "1회차 탈락"), _titles("1회차 승자", "진짜 새 후보")],
            [_verdicts(True, False), _verdicts(True)],
        )

        response = suggest(_request(), llm, _embed)

        titles = [c.title for c in response.candidates]
        assert titles.count("1회차 승자") == 1, "같은 제목이 두 번 들어갔다"
        assert titles == ["1회차 승자", "진짜 새 후보"]

    def test_the_repeat_never_reaches_the_second_critique(self, settings):
        """중복은 검수 **전에** 걸러진다 — 걸러진 뒤에도 검수가 그걸 읽으면 낭비다."""
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("1회차 승자", "1회차 탈락"), _titles("1회차 승자", "진짜 새 후보")],
            [_verdicts(True, False), _verdicts(True)],
        )

        suggest(_request(), llm, _embed)

        second = llm.critique_prompts[1]
        assert f"{CRITIQUE_INDEX_BASE}. 진짜 새 후보" in second
        assert "1회차 승자" not in second


class TestTheRetryCameBackEmpty:
    """🔴 **재생성이 빈손일 때 앞 회차 통과분을 잃으면 안 된다** (2026-08-03 리뷰 P0).

    `_generate` 가 `{"candidates": []}` 를 쓰면 `_has_candidates` 가 곧장 END 로 보낸다 —
    재생성을 **안 했으면** 3개를 보여줬을 자리에 0개가 나간다. 재생성이 후보를 늘리기는커녕
    있던 것마저 없애는 셈이라, 이 티켓의 목적과 정확히 반대다.

    빈손이 되는 길이 둘이라 둘 다 건다.
    """

    def test_when_the_retry_only_repeats_what_already_passed(self, settings):
        """-237 이 새로 넣은 누적분 중복 필터가 2회차를 통째로 비우는 경우."""
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("1회차 승자", "1회차 탈락"), _titles("1회차 승자")],
            [_verdicts(True, False)],
        )

        response = suggest(_request(), llm, _embed)

        assert [c.title for c in response.candidates] == ["1회차 승자"]

    def test_when_the_retry_collides_with_existing_todos(self, settings):
        """기존 `filter_candidates` 가 2회차를 통째로 비우는 경우 — -237 과 무관한 옛 경로다."""
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("1회차 승자", "1회차 탈락"), _titles("이미 있는 투두")],
            [_verdicts(True, False)],
        )

        response = suggest(_request(existing_todos=["이미 있는 투두"]), llm, _embed)

        assert [c.title for c in response.candidates] == ["1회차 승자"]

    def test_the_restored_batch_is_not_judged_again(self, settings):
        """되돌려준 누적분은 이미 검수를 통과했다 — 다시 판정하면 왕복이 한 번 더 들고,
        같은 후보가 이번엔 반려될 수도 있다."""
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("1회차 승자", "1회차 탈락"), _titles("1회차 승자")],
            [_verdicts(True, False)],
        )

        suggest(_request(), llm, _embed)

        assert len(llm.critique_prompts) == 1, "누적분을 검수에 다시 보냈다"


class TestTheRetryPrompt:
    def test_it_carries_both_the_survivors_and_the_reasons(self, settings):
        """통과분을 안 알려주면 모델이 회당 8칸을 1회차 승자로 다시 채운다 — 재생성이
        허수아비가 된다. 반려 사유는 -235 부터의 계약이다."""
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("1회차 승자", "1회차 탈락"), _titles("2회차 승자")],
            [_verdicts(True, False, reason="고를 대상이 여러 개다"), _verdicts(True)],
        )

        suggest(_request(), llm, _embed)

        retry = llm.prompts[1]
        assert "- 1회차 승자" in retry, "통과분을 안 알려줬다"
        assert "겹치지 않는 새 후보" in retry
        assert "1회차 탈락 → 고를 대상이 여러 개다" in retry, "반려 사유를 안 넘겼다"

    def test_the_first_prompt_is_untouched(self, settings):
        """1회차 프롬프트가 달라지면 #26·#28 기준선과의 비교가 통째로 깨진다."""
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("1회차 승자", "1회차 탈락"), _titles("2회차 승자")],
            [_verdicts(True, False), _verdicts(True)],
        )

        suggest(_request(), llm, _embed)

        assert "반려" not in llm.prompts[0]
        assert "통과했다" not in llm.prompts[0]

    def test_total_rejection_keeps_the_235_wording(self, settings):
        """전부 반려되면 통과분이 없다 — 그 경로의 프롬프트는 **-235 와 한 글자도 같아야**
        #28 조건 2 측정이 계속 유효하다."""
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("전부 반려될 후보"), _titles("2회차 승자")],
            [_verdicts(False), _verdicts(True)],
        )

        suggest(_request(), llm, _embed)

        retry = llm.prompts[1]
        assert retry.endswith(
            "\n\n# 방금 낸 후보 중 아래는 반려됐다. 같은 이유로 반려될 것을 다시 내지 마라."
            "\n- 전부 반려될 후보 → 고를 대상이 여러 개다"
        )
        assert "통과했다" not in retry


class TestTheCeiling:
    def test_it_never_exceeds_the_attempt_limit(self, settings):
        """계속 부분 반려해도 생성은 상한까지만. 넘으면 10초를 깬다."""
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("승자", "탈락")],
            [_verdicts(True, False), _verdicts(True, False), _verdicts(True, False)],
        )

        suggest(_request(), llm, _embed)

        assert len(llm.prompts) == 2, f"생성이 {len(llm.prompts)}번 돌았다 — 상한 2를 넘었다"

    def test_one_attempt_never_regenerates(self, settings):
        """`critique_max_attempts=1`(현재 dev 기본)이면 스위치가 켜져도 안 돈다 —
        시도가 이미 소진되기 때문이다."""
        settings(1, True)
        llm = ScriptedLlm(
            [_titles("승자", "탈락"), _titles("나오면 안 되는 후보")],
            [_verdicts(True, False)],
        )

        response = suggest(_request(), llm, _embed)

        assert len(llm.prompts) == 1
        assert [c.title for c in response.candidates] == ["승자"]

    def test_it_logs_the_partial_rejection(self, settings, caplog):
        """운영에서 이 루프가 실제로 도는지 볼 유일한 신호다."""
        settings(2, True)
        llm = ScriptedLlm(
            [_titles("승자", "탈락1", "탈락2"), _titles("2회차 승자")],
            [_verdicts(True, False, False), _verdicts(True)],
        )

        with caplog.at_level(logging.INFO, logger="modi_ai.suggest"):
            suggest(_request(), llm, _embed)

        assert "부분 반려 2건" in caplog.text


class TestNothingElseMoved:
    """-235 가 세운 경로들이 그대로인지. 스위치 ON 에서도 확인한다."""

    @pytest.mark.parametrize("partial", [False, True])
    def test_total_rejection_still_regenerates(self, settings, partial):
        settings(2, partial)
        llm = ScriptedLlm(
            [_titles("나쁜 후보"), _titles("좋은 후보")],
            [_verdicts(False), _verdicts(True)],
        )

        response = suggest(_request(), llm, _embed)

        assert len(llm.prompts) == 2
        assert [c.title for c in response.candidates] == ["좋은 후보"]

    @pytest.mark.parametrize("partial", [False, True])
    def test_total_rejection_with_no_attempts_left_returns_empty(self, settings, partial):
        settings(1, partial)
        llm = ScriptedLlm([_titles("나쁜 후보")], [_verdicts(False)])

        response = suggest(_request(), llm, _embed)

        assert response.candidates == []

    @pytest.mark.parametrize("partial", [False, True])
    def test_the_second_critique_fails_open(self, settings, partial):
        """2차 검수가 개수를 틀리면 그 배치를 **전부 통과**시킨다 — 검수 고장이 추천 장애가
        되면 안 된다(`_map_categories_safely` 와 같은 정책)."""
        settings(2, partial)
        llm = ScriptedLlm(
            [_titles("승자", "탈락"), _titles("A", "B")],
            # 2차 판정이 1개뿐 — 후보는 2개다
            [_verdicts(True, False), _verdicts(True)],
        )

        response = suggest(_request(), llm, _embed)

        titles = [c.title for c in response.candidates]
        if partial:
            assert titles == ["승자", "A", "B"], "fail-open 이 안 됐다"
        else:
            assert titles == ["승자"]

    def test_an_exception_in_the_second_critique_also_keeps_the_accumulated(self, settings):
        """fail-open 경로가 **셋**이다 — 예외 · 개수 불일치 · 번호 불일치. 위 테스트는 개수만
        타므로 예외 경로가 누적을 버려도 안 잡혔다(변형 M6 가 살아남아 드러났다)."""
        settings(2, True)
        llm = BoomOnSecondCritique(
            [_titles("1회차 승자", "1회차 탈락"), _titles("A", "B")],
            [_verdicts(True, False)],
        )

        response = suggest(_request(), llm, _embed)

        assert [c.title for c in response.candidates] == ["1회차 승자", "A", "B"]

    def test_a_misnumbered_second_critique_also_keeps_the_accumulated(self, settings):
        """세 번째 fail-open 경로 — **번호 불일치**. 개수는 맞는데 index 가 어긋난 경우다.

        docstring 이 "경로가 셋"이라 적어놓고 둘만 걸어서, 이 갈래만 `return {}` 로
        되돌리는 변형이 살아남았다(2026-08-03 리뷰 P1-4).
        """
        settings(2, True)
        # ⚠️ **0-based 가 이제 "틀린 번호"다** 원래 여기가 `index=i + 1`
        # 이었는데, 운영이 1-based 로 바뀌어 그건 정답이 됐다 — 그대로 뒀으면 이 갈래를
        # 안 타고 초록으로 통과했다.
        misnumbered = CritiqueResponse(
            verdicts=[CritiqueVerdict(index=i, ok=True) for i in range(2)]
        )
        llm = ScriptedLlm(
            [_titles("1회차 승자", "1회차 탈락"), _titles("A", "B")],
            [_verdicts(True, False), misnumbered],
        )

        response = suggest(_request(), llm, _embed)

        assert [c.title for c in response.candidates] == ["1회차 승자", "A", "B"]

    def test_fail_open_clears_the_rejected_list(self, settings):
        """전부 통과시켰으면 반려가 없다. 안 비우면 앞 회차 반려 목록이 남아 **또** 되돌아간다.

        `critique_max_attempts=3` 이라야 관측된다 — 2에서는 그 시점에 시도가 소진돼
        어느 쪽이든 결과가 같다(변형 M8 이 2에서 살아남았다).
        """
        settings(3, True)
        llm = ScriptedLlm(
            [_titles("승자", "탈락"), _titles("A", "B")],
            # 2차 판정이 1개뿐 → fail-open
            [_verdicts(True, False), _verdicts(True)],
        )

        suggest(_request(), llm, _embed)

        assert len(llm.prompts) == 2, "fail-open 뒤에 반려 목록이 남아 또 재생성했다"

    @pytest.mark.parametrize("partial", [False, True])
    def test_critique_off_skips_the_node_entirely(self, settings, partial):
        """`critique_max_attempts=0` 은 스위치와 무관하게 검수 노드를 안 탄다."""
        settings(0, partial)
        llm = ScriptedLlm([_titles("후보 하나", "후보 둘")])

        response = suggest(_request(), llm, _embed)

        assert llm.critique_prompts == []
        assert len(response.candidates) == 2
