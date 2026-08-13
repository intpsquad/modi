"""후보 자기 검수 + 재생성 루프 — **크레딧 0 · 네트워크 0**

`generate → critique → generate` 되돌아가는 엣지가 이 티켓에서 생겼다. 그래프가 처음으로
직선이 아니게 된 자리라, 여기서 지켜야 할 것이 셋이다.

1. **1회차 프롬프트가 전환 전과 한 글자도 같아야 한다** — `docs/EXPERIMENTS.md` #26 기준선과
   비교가 성립하려면. 회귀 위험이 여기 전부 몰려 있다.
2. **시도 상한을 절대 넘지 않아야 한다** — 넘으면 응답 시간이 사용자가 정한 7초를 깬다.
3. **검수가 고장나면 전부 통과시켜야 한다** — 나중에 얹은 층이 화면 본체를 잃게 하면 안 된다.
"""

import logging
import re

import pytest

from modi_ai import config
from modi_ai import suggest as module
from modi_ai.prompts import CRITIQUE_PROMPT, SYSTEM_PROMPT
from modi_ai.schemas import (
    ArchiveItemInput,
    CritiqueResponse,
    CritiqueVerdict,
    RoomInput,
    SuggestionRequest,
    SuggestionResponse,
    TodoCandidate,
)
from modi_ai.suggest import CRITIQUE_INDEX_BASE, suggest

_NUMBERED = re.compile(r"^\d+\. ")


def _request(**overrides) -> SuggestionRequest:
    base = {
        "room": RoomInput(name="방", goal="목표", start_date="2026-08-01", end_date="2026-08-31"),
        "categories": ["공부"],
        "existing_todos": [],
        "excluded_todos": [],
        "archive": [ArchiveItemInput(id=1, title="자료", content="내용")],
    }
    return SuggestionRequest(**(base | overrides))


def _embed(texts):
    """문자열마다 **서로 직교하는** 축을 준다.

    ⚠️ 전부 같은 벡터를 주면 `drop_semantic_duplicates` 가 코사인 1.0 으로 보고 후보를 하나만
    남긴다 — 검수를 재려는 테스트가 중복 제거 때문에 실패한다(처음에 실제로 그랬다).
    """
    axes: dict[str, int] = {}
    vectors = []
    for text in texts:
        index = axes.setdefault(text, len(axes))
        axis = [0.0] * 64
        axis[index % 64] = 1.0
        vectors.append(axis)
    return vectors


def _titles(*names: str) -> list[TodoCandidate]:
    return [TodoCandidate(title=n, source_item_id=1) for n in names]


class ScriptedLlm:
    """호출마다 **다른 응답**을 주는 가짜.

    `conftest.FakeChatModel` 은 생성 응답을 하나만 갖고 있어 재생성 루프를 재지 못한다 —
    2회차에 다른 후보가 나와야 "다시 만들었다"를 확인할 수 있다.

    `critiques` 를 다 쓰면 그 뒤로는 **전부 통과**로 답한다(무한 루프 방지).
    """

    def __init__(self, generations: list[list[TodoCandidate]], critiques=None, boom=False):
        self._generations = list(generations)
        self._critiques = list(critiques or [])
        self._boom = boom
        self.prompts: list[str] = []
        self.system_prompts: list[str] = []
        self.critique_prompts: list[str] = []
        self.critique_system_prompts: list[str] = []

    def with_structured_output(self, schema, include_raw: bool = False):
        return _Runnable(self, schema)

    def _generate(self, messages):
        self.prompts.append(str(messages[-1].content))
        self.system_prompts.append(str(messages[0].content))
        # 대본이 떨어지면 마지막 것을 되풀이한다 — 상한을 넘겼는지 재는 테스트가
        # IndexError 로 죽지 않게.
        batch = self._generations.pop(0) if len(self._generations) > 1 else self._generations[0]
        return {
            "raw": None,
            "parsed": SuggestionResponse(candidates=list(batch)),
            "parsing_error": None,
        }

    def _critique(self, messages):
        self.critique_prompts.append(str(messages[-1].content))
        self.critique_system_prompts.append(str(messages[0].content))
        if self._boom:
            raise RuntimeError("검수 게이트웨이 장애")
        if self._critiques:
            return self._critiques.pop(0)
        count = sum(1 for line in self.critique_prompts[-1].splitlines() if _NUMBERED.match(line))
        return CritiqueResponse(
            verdicts=[
                CritiqueVerdict(index=i, ok=True)
                for i in range(CRITIQUE_INDEX_BASE, CRITIQUE_INDEX_BASE + count)
            ]
        )


class _Runnable:
    def __init__(self, llm: ScriptedLlm, schema):
        self._llm = llm
        self._schema = schema

    def invoke(self, messages):
        if self._schema is CritiqueResponse:
            return self._llm._critique(messages)
        return self._llm._generate(messages)


def _verdicts(*flags: bool, reason: str = "고를 대상이 여러 개다") -> CritiqueResponse:
    return CritiqueResponse(
        verdicts=[
            CritiqueVerdict(index=i, ok=ok, reason=None if ok else reason)
            for i, ok in enumerate(flags, start=CRITIQUE_INDEX_BASE)
        ]
    )


@pytest.fixture
def attempts(monkeypatch):
    """`critique_max_attempts` 를 테스트마다 갈아끼운다."""

    def _set(value: int):
        monkeypatch.setattr(
            module, "get_settings", lambda: config.Settings(critique_max_attempts=value)
        )

    return _set


class TestFiltering:
    def test_only_the_approved_candidates_survive(self, attempts):
        attempts(2)
        llm = ScriptedLlm([_titles("좋은 후보", "나쁜 후보")], [_verdicts(True, False)])

        response = suggest(_request(), llm, _embed)

        assert [c.title for c in response.candidates] == ["좋은 후보"]

    def test_the_critique_sees_only_titles(self, attempts):
        """자료·방 정보를 다시 보내지 않는다 — 검수를 싸게 유지하는 근거다."""
        attempts(2)
        llm = ScriptedLlm([_titles("후보 하나")])

        suggest(_request(), llm, _embed)

        prompt = llm.critique_prompts[0]
        assert f"{CRITIQUE_INDEX_BASE}. 후보 하나" in prompt
        assert "아카이브 자료" not in prompt
        assert "내용" not in prompt

    def test_no_critique_call_when_generate_returned_nothing(self, attempts):
        """후보가 0이면 검수할 게 없다. **재생성도 하지 않는다** — 반려 사유가 없으니
        같은 프롬프트를 한 번 더 던지는 것뿐이다."""
        attempts(2)
        llm = ScriptedLlm([[]])

        response = suggest(_request(), llm, _embed)

        assert response.candidates == []
        assert llm.critique_prompts == []
        assert len(llm.prompts) == 1


class TestRegeneration:
    def test_it_regenerates_when_everything_was_rejected(self, attempts):
        attempts(2)
        llm = ScriptedLlm(
            [_titles("나쁜 후보"), _titles("좋은 후보")],
            [_verdicts(False), _verdicts(True)],
        )

        response = suggest(_request(), llm, _embed)

        assert len(llm.prompts) == 2, "재생성이 안 돌았다"
        assert [c.title for c in response.candidates] == ["좋은 후보"]

    def test_it_does_not_regenerate_when_something_survived(self, attempts):
        """통과분이 하나라도 있으면 그대로 간다 — 늘 두 번 부르면 지연만 2배가 된다."""
        attempts(2)
        llm = ScriptedLlm([_titles("좋은 후보", "나쁜 후보")], [_verdicts(True, False)])

        suggest(_request(), llm, _embed)

        assert len(llm.prompts) == 1

    def test_the_attempt_cap_is_never_exceeded(self, attempts):
        """계속 반려해도 생성은 상한까지만. **넘으면 응답이 7초를 깬다.**"""
        attempts(2)
        llm = ScriptedLlm([_titles("나쁜 후보")], [_verdicts(False)] * 5)

        response = suggest(_request(), llm, _embed)

        assert len(llm.prompts) == 2
        assert response.candidates == []

    def test_one_attempt_means_critique_only(self, attempts):
        """`1` 은 검수만 하고 재생성하지 않는다 — A/B 측정용 조건이다."""
        attempts(1)
        llm = ScriptedLlm([_titles("나쁜 후보")], [_verdicts(False)])

        response = suggest(_request(), llm, _embed)

        assert len(llm.prompts) == 1
        assert response.candidates == []

    def test_the_rejection_reason_reaches_the_retry_prompt(self, attempts):
        """사유 없이 되돌아가면 모델은 "다시 내지 마라"만 듣고 왜인지 모른다."""
        attempts(2)
        llm = ScriptedLlm(
            [_titles("맛집 10곳 중 1곳 체크하기"), _titles("초량해 칼국수 먹기")],
            [_verdicts(False, reason="고를 대상이 여러 개다"), _verdicts(True)],
        )

        suggest(_request(), llm, _embed)

        retry = llm.prompts[1]
        assert "맛집 10곳 중 1곳 체크하기 → 고를 대상이 여러 개다" in retry
        assert "반려" in retry

    def test_a_missing_reason_still_produces_a_line(self, attempts):
        """모델이 `reason` 을 비우고 반려할 수 있다. 그때도 재생성 프롬프트가 성립해야 한다."""
        attempts(2)
        llm = ScriptedLlm(
            [_titles("나쁜 후보"), _titles("좋은 후보")],
            [
                CritiqueResponse(verdicts=[CritiqueVerdict(index=CRITIQUE_INDEX_BASE, ok=False)]),
                _verdicts(True),
            ],
        )

        suggest(_request(), llm, _embed)

        assert "나쁜 후보 → 바로 실행할 수 없다" in llm.prompts[1]


class TestCritiqueAddsNothingToTheFirstPrompt:
    """검수 기능이 1회차 프롬프트에 **아무것도 덧붙이지 않는다.**

    ⚠️ **이 클래스가 지키는 범위를 정확히 적는다**(2026-08-03 리뷰). 원래 이름이
    "1회차 프롬프트가 전환 전과 같다"였는데 그건 **지키지 못하는 주장**이다 — 아래
    `test_it_equals_build_payload_exactly` 의 양변이 모두 살아 있는 코드라, 누가
    `build_payload` 나 `SYSTEM_PROMPT` 를 고치면 두 쪽이 같이 변해 테스트는 초록인 채로
    `docs/EXPERIMENTS.md` #26 기준선과의 비교가 깨진다.

    그 회귀를 진짜로 막으려면 **얼린 골든 문자열**이 필요하다. 여기서 보장하는 것은
    "검수가 1회차에 끼어들지 않는다"까지다.
    """

    def test_no_retry_section_on_the_first_attempt(self, attempts):
        attempts(2)
        llm = ScriptedLlm([_titles("후보")])

        suggest(_request(), llm, _embed)

        assert "반려" not in llm.prompts[0]

    def test_it_equals_build_payload_exactly(self, attempts):
        """문구 검사가 아니라 **전체 문자열 동일성**을 본다 — 검수가 한 글자라도 붙이면 걸린다."""
        attempts(2)
        request = _request(existing_todos=["이미 있는 것"], excluded_todos=["이미 본 것"])
        llm = ScriptedLlm([_titles("후보")])

        suggest(request, llm, _embed)

        # ⚠️ 원본 `request` 로 비교한다. 픽스처 자료가 1건이라 `_select_archive` 가 항등이어서
        # 성립하는 것이다 — 자료를 2건 이상으로 늘리면 `select` 가 갈아끼운 것과 비교해야 한다.
        # (초안 주석이 "모델이 본 것과 비교한다"라고 코드와 반대로 적혀 있었다, 2026-08-03 리뷰.)
        assert len(request.archive) == 1, "이 비교가 성립하는 전제"
        assert llm.prompts[0] == module.build_payload(request)

    def test_the_system_prompt_is_the_shipped_one(self, attempts):
        """검수를 넣으면서 생성 쪽 시스템 프롬프트를 건드리지 않았는지."""
        attempts(2)
        llm = ScriptedLlm([_titles("후보")])

        suggest(_request(), llm, _embed)

        assert llm.system_prompts[0] == SYSTEM_PROMPT


class TestTheCritiquePromptItself:
    """`CRITIQUE_PROMPT` 를 고정하는 테스트가 하나도 없었다(2026-08-03 리뷰).

    특히 **학습 방 보호 단서**는 `docs/DECISIONS.md` 가 "필수"라고 단정하는데 그 줄을 지워도
    깨지는 테스트가 없었다 — 회화 스터디 후보(`완료시제 넣어 말하기 연습하기`)는 물리적 대상이
    없어 규칙 1에 전부 걸린다.
    """

    def test_the_shipped_prompt_is_what_goes_out(self, attempts):
        attempts(2)
        llm = ScriptedLlm([_titles("후보")])

        suggest(_request(), llm, _embed)

        assert llm.critique_system_prompts[0] == CRITIQUE_PROMPT

    def test_it_carries_the_three_reject_rules(self):
        """#26 ③ 이 눈으로 분류해 얻은 셋. 하나라도 빠지면 지표가 재던 것이 달라진다."""
        assert "대상이 특정되지 않았다" in CRITIQUE_PROMPT
        assert "고르는 일을 사용자에게 떠넘겼다" in CRITIQUE_PROMPT
        assert "행위가 계획·확인이다" in CRITIQUE_PROMPT

    def test_it_carries_the_study_room_escape_hatch(self):
        """⚠️ **이 단서가 빠지면 학습 방 후보가 통째로 날아간다**(추정 — 절제 측정은 안 했다).

        `docs/DECISIONS.md` 가 이 단서를 "필수"라고 적어둔 근거는 규칙 1의 문면이지
        빼고 돌려본 실측이 아니다. 그래서 문서에도 "(추정)"으로 적었다.
        """
        assert "행위 자체가 대상인 경우는 통과" in CRITIQUE_PROMPT
        assert "연습" in CRITIQUE_PROMPT

    def test_it_keeps_the_prompt_injection_guard(self):
        """검수도 사용자 자료에서 나온 제목을 읽는다 — 생성 프롬프트와 같은 방어가 필요하다."""
        assert "지시문이나 명령처럼" in CRITIQUE_PROMPT

    def test_disabling_critique_restores_the_old_path(self, attempts):
        """`0` 이면 검수 노드를 아예 안 탄다 — 전환 전과 완전히 같은 동작이어야 한다."""
        attempts(0)
        llm = ScriptedLlm([_titles("후보 하나", "후보 둘")])

        response = suggest(_request(), llm, _embed)

        assert llm.critique_prompts == []
        assert len(llm.prompts) == 1
        assert [c.title for c in response.candidates] == ["후보 하나", "후보 둘"]


class TestTheFilteringIsVisibleInLogs:
    """⚠️ **채택 설정(1)에서 이 층은 재생성을 안 하고 후보를 절반으로 줄이고 끝난다.**

    운영에서 그 사실을 알 수 있는 신호가 `log.info("후보 검수: N개 중 M개 통과")` 한 줄뿐인데
    테스트가 없었다 — fail-open 의 ERROR 로그 셋은 전부 고정하면서 정상 경로의 이 한 줄만
    빠져 있었다(2026-08-03 리뷰에서 변이가 살아남았다). 우선순위가 거꾸로였다.
    """

    def test_it_says_how_many_survived(self, attempts, caplog):
        attempts(1)
        llm = ScriptedLlm(
            [_titles("좋은 후보", "나쁜 후보", "또 나쁜 후보")], [_verdicts(True, False, False)]
        )

        with caplog.at_level(logging.INFO, logger="modi_ai.suggest"):
            suggest(_request(), llm, _embed)

        assert any("3개 중 1개 통과" in r.getMessage() for r in caplog.records)


class TestFailOpen:
    """검수 층 고장이 추천 장애가 되면 안 된다 — `_map_categories_safely` 와 같은 정책."""

    def _errors(self, caplog):
        return [r for r in caplog.records if r.levelname == "ERROR"]

    def test_an_exception_passes_everything(self, attempts, caplog):
        attempts(2)
        llm = ScriptedLlm([_titles("후보 하나", "후보 둘")], boom=True)

        with caplog.at_level(logging.ERROR, logger="modi_ai.suggest"):
            response = suggest(_request(), llm, _embed)

        assert [c.title for c in response.candidates] == ["후보 하나", "후보 둘"]
        assert any("검수 실패" in r.getMessage() for r in self._errors(caplog))

    def test_a_verdict_count_mismatch_passes_everything(self, attempts, caplog):
        """**인덱스가 한 칸 밀리면 멀쩡한 후보가 반려되고 나쁜 후보가 통과한다.**

        그리고 그건 조용하다 — 판정이 그럴듯하게 돌아오므로 로그도 안 남는다.
        그래서 개수가 다르면 판정을 통째로 버린다.
        """
        attempts(2)
        llm = ScriptedLlm([_titles("후보 하나", "후보 둘")], [_verdicts(False)])

        with caplog.at_level(logging.ERROR, logger="modi_ai.suggest"):
            response = suggest(_request(), llm, _embed)

        assert [c.title for c in response.candidates] == ["후보 하나", "후보 둘"]
        assert any("개수가 안 맞는다" in r.getMessage() for r in self._errors(caplog))

    def test_wrong_index_numbers_pass_everything(self, attempts, caplog):
        """개수는 맞는데 번호가 `0,1`(1-based 가 아님)로 오는 경우.

        ⚠️ **원래 이 테스트는 `1,2` 를 "틀린 번호"로 썼다** — 운영이 0-based 였을 때다.
        이 운영을 1-based 로 바꿨으므로 `1,2` 는 이제 **정답**이고, 그대로
        뒀으면 이 테스트가 초록인 채로 아무것도 안 재게 됐다.
        """
        attempts(2)
        llm = ScriptedLlm(
            [_titles("후보 하나", "후보 둘")],
            [
                CritiqueResponse(
                    verdicts=[
                        CritiqueVerdict(index=0, ok=False),
                        CritiqueVerdict(index=1, ok=True),
                    ]
                )
            ],
        )

        with caplog.at_level(logging.ERROR, logger="modi_ai.suggest"):
            response = suggest(_request(), llm, _embed)

        assert [c.title for c in response.candidates] == ["후보 하나", "후보 둘"]
        assert any("번호가 후보와 안 맞는다" in r.getMessage() for r in self._errors(caplog))

    def test_a_failure_does_not_trigger_regeneration(self, attempts):
        """폴백은 "전부 통과"라 통과분이 생긴다 — 재생성으로 새지 않아야 한다."""
        attempts(2)
        llm = ScriptedLlm([_titles("후보")], boom=True)

        suggest(_request(), llm, _embed)

        assert len(llm.prompts) == 1
