"""방 단위 러너의 순수 로직 — **크레딧 0 · 네트워크 0.**

러너 본체는 실제 LLM 을 부르지만 제외 창 누적·집계·픽스처 로딩은 순수 함수다.

**가장 중요한 것은 `TestExposureWindow` 다.** 제외 창이 서버(`TodoSuggestionExposureStore`)와
어긋나면 "후보가 마른다" 측정이 통째로 틀리는데, **증상이 안 보인다** — 숫자는 그럴듯하게
나온다. 여기가 유일한 방어선이다.
"""

import hashlib
import json
import logging
import pathlib
from datetime import date

import pytest

from evals.rooms import ROOM_DIR, available_slugs, load_room, load_rooms
from evals.run_room_eval import (
    MAX_EXCLUDED,
    ExposureWindow,
    RoundResult,
    UsageCollector,
    build_parser,
    captured_date,
    export_conditions,
    mean_sd,
    print_room_report,
    round_stats,
    run_name,
    run_repeat,
    run_round,
    summarize_room,
    title_length_stats,
)
from modi_ai.schemas import SuggestionRequest, TodoCandidate


def candidates(*titles: str) -> list[TodoCandidate]:
    return [TodoCandidate(title=t) for t in titles]


class TestExposureWindow:
    """서버 `TodoSuggestionExposureStore` 미러링 — 어긋나면 마름 측정이 무효다."""

    def test_the_last_candidate_of_a_round_is_the_newest(self):
        """⚠️ **한 번 반대로 박아뒀다가 리뷰에서 잡혔다**(2026-08-03).

        서버는 후보 순서대로 `saveAll` 하고 `order by createdAt desc, id desc` 로 읽는다.
        같은 `saveAll` 안에서는 `createdAt` 이 같아 **`id desc` 가 순서를 정하므로 마지막
        후보가 맨 앞**이다. 이 테스트가 반대를 단언하고 있었고, 그러면 나중에 누가 서버와
        맞추려 할 때 테스트가 빨개져서 되돌리게 된다.
        """
        window = ExposureWindow([])
        window.add(candidates(*[f"후보 {i}" for i in range(17)]))

        assert MAX_EXCLUDED == 16
        assert len(window.titles) == 16
        assert window.titles[0] == "후보 16"
        assert "후보 0" not in window.titles, "창이 넘칠 때 잘리는 쪽이 서버와 달라졌다"

    def test_newer_rounds_push_older_ones_out(self):
        window = ExposureWindow([])
        window.add(candidates(*[f"1회차 {i}" for i in range(10)]))
        window.add(candidates(*[f"2회차 {i}" for i in range(10)]))

        assert len(window.titles) == 16
        assert window.titles[0] == "2회차 9"
        # 1회차의 뒤쪽 4개가 밀려났다.
        assert sum(1 for t in window.titles if t.startswith("1회차")) == 6

    def test_normalizes_like_the_server(self):
        """공백·대소문자만 다른 제목은 창을 두 칸 먹지 않는다.

        운영 `suggest._normalize`(공백 제거 + 소문자)를 그대로 쓴다. 서버 Java 쪽도 같은
        함수를 미러링하고 있어 셋이 일치해야 한다.
        """
        window = ExposureWindow(["OPIc 모의고사 풀기"])
        window.add(candidates("opic  모의고사   풀기", "다른 후보"))

        assert window.titles == ["다른 후보", "OPIc 모의고사 풀기"]

    def test_ignores_blank_titles(self):
        """빈 제목이 들어가면 정규화 결과가 빈 문자열이라 **이후 모든 후보를 제외**해버린다.

        서버 `truncate` 가 같은 이유로 막는다.
        """
        window = ExposureWindow([])
        window.add(candidates("   ", "진짜 후보"))

        assert window.titles == ["진짜 후보"]

    def test_seeded_titles_are_capped_too(self):
        """캡처된 제외 목록이 16개를 넘어도(계약이 깨진 경우) 창은 16을 지킨다."""
        window = ExposureWindow([f"기존 {i}" for i in range(30)])

        assert len(window.titles) == 16

    def test_the_default_limit_is_what_production_uses(self):
        """기본값이 운영값이어야 **인자를 안 준 옛 측정과 결과가 같다.**

        창을 팔로 가르려고 인자를 뚫었는데 기본값이 달라지면, 지금까지 얼린 스냅샷과
        비교할 수 없게 된다 — 새 조건을 기존 기준선인 척 쓰는 사고다.
        """
        window = ExposureWindow([f"기존 {i}" for i in range(30)])

        assert MAX_EXCLUDED == 16
        assert len(window.titles) == MAX_EXCLUDED

    def test_a_smaller_limit_is_honoured(self):
        """#24 실측의 후보 지렛대 — `8` 이 `16` 보다 후보를 더 냈다(7.3 vs 6.0)."""
        window = ExposureWindow([], limit=8)
        window.add(candidates(*[f"후보 {i}" for i in range(12)]))

        assert len(window.titles) == 8
        # 서버와 같은 쪽(가장 오래된 것)이 밀려난다 — 창 크기를 바꿔도 그 규칙은 그대로다.
        assert window.titles[0] == "후보 11"
        assert "후보 0" not in window.titles

    def test_a_smaller_limit_caps_seeded_titles_too(self):
        """`--start-excluded captured` 와 좁은 창을 함께 쓰면 캡처값 16개가 들어온다."""
        window = ExposureWindow([f"기존 {i}" for i in range(16)], limit=8)

        assert len(window.titles) == 8


class TestRunRepeat:
    """반복 간 격리 — 안 되면 5회 반복이 15라운드짜리 한 번이 된다."""

    @pytest.fixture
    def fixture_room(self):
        return load_room("busan_travel")

    def _patch_suggest(self, monkeypatch, seen: list[list[str]]):
        """`suggest()` 를 가로채 **그 라운드가 받은 제외 목록**을 기록한다. LLM 은 안 부른다."""
        from modi_ai.schemas import SuggestionResponse

        counter = {"n": 0}

        def fake_suggest(request, llm, embed):  # noqa: ARG001
            seen.append(list(request.excluded_todos))
            counter["n"] += 1
            return SuggestionResponse(candidates=candidates(f"후보 {counter['n']}"))

        monkeypatch.setattr("evals.run_room_eval.suggest", fake_suggest)

    def _patch_suggest_capturing_request(self, monkeypatch, seen: list) -> None:
        """요청 **객체**를 그대로 모은다 — `today` 처럼 목록이 아닌 필드를 보려면 필요하다."""
        from modi_ai.schemas import SuggestionResponse

        def fake_suggest(request, llm, embed):  # noqa: ARG001
            seen.append(request)
            return SuggestionResponse(candidates=candidates(f"후보 {len(seen)}"))

        monkeypatch.setattr("evals.run_room_eval.suggest", fake_suggest)

    def test_fresh_starts_each_repeat_from_an_empty_window(self, fixture_room, monkeypatch):
        """기본값 `fresh` — 1회차는 '처음 누른 것'이어야 마름을 잴 수 있다.

        캡처 당시 창은 이미 16개가 차 있어서, 그대로 두면 1회차가 '4회차 이후'처럼 보인다.
        """
        assert len(fixture_room.request.excluded_todos) == 16, "이 테스트의 전제(캡처값이 참)"
        seen: list[list[str]] = []
        self._patch_suggest(monkeypatch, seen)

        run_repeat(fixture_room, None, None, repeat=1, rounds=3, start_excluded="fresh")
        run_repeat(fixture_room, None, None, repeat=2, rounds=3, start_excluded="fresh")

        assert [len(s) for s in seen] == [0, 1, 2, 0, 1, 2]

    def test_captured_starts_from_the_frozen_window(self, fixture_room, monkeypatch):
        seen: list[list[str]] = []
        self._patch_suggest(monkeypatch, seen)

        run_repeat(fixture_room, None, None, repeat=1, rounds=2, start_excluded="captured")

        assert [len(s) for s in seen] == [16, 16]
        assert seen[0] == list(fixture_room.request.excluded_todos)
        # 2회차에는 1회차 후보가 들어가고 가장 오래된 것이 밀려났다.
        assert seen[1][0] == "후보 1"

    def test_the_frozen_fixture_is_never_mutated(self, fixture_room, monkeypatch):
        """`model_copy` 로 갈아끼우지 않고 원본을 고치면 반복 간 오염이 조용히 생긴다."""
        before = list(fixture_room.request.excluded_todos)
        self._patch_suggest(monkeypatch, [])

        run_repeat(fixture_room, None, None, repeat=1, rounds=3, start_excluded="fresh")

        assert fixture_room.request.excluded_todos == before

    def test_the_window_size_reaches_the_rounds(self, fixture_room, monkeypatch):
        """창 크기 팔이 **실제로 프롬프트가 받는 제외 목록**까지 내려가는지 본다.

        `ExposureWindow` 단위 테스트만으로는 부족하다 — `run_repeat` 이 인자를 안 넘기면
        창은 조용히 운영값으로 돌고, 그러면 A/B 두 짝이 **같은 조건의 재실행**이 된다.
        """
        seen: list[list[str]] = []
        self._patch_suggest(monkeypatch, seen)

        run_repeat(
            fixture_room,
            None,
            None,
            repeat=1,
            rounds=4,
            start_excluded="captured",
            exclusion_window=2,
        )

        # 캡처값 16개가 2개로 잘리고, 그 뒤로도 2를 넘지 않는다.
        assert [len(s) for s in seen] == [2, 2, 2, 2]

    def test_the_window_size_defaults_to_production(self, fixture_room, monkeypatch):
        """인자를 안 주면 옛 측정과 같아야 한다 — 안 그러면 기준선이 거짓이 된다."""
        seen: list[list[str]] = []
        self._patch_suggest(monkeypatch, seen)

        run_repeat(fixture_room, None, None, repeat=1, rounds=2, start_excluded="captured")

        assert [len(s) for s in seen] == [MAX_EXCLUDED, MAX_EXCLUDED]

    def test_today_is_off_by_default(self, fixture_room, monkeypatch):
        """기본값이 **지금 운영**이라 안 주면 프롬프트가 예전과 같다."""
        seen: list[SuggestionRequest] = []
        self._patch_suggest_capturing_request(monkeypatch, seen)

        run_repeat(fixture_room, None, None, repeat=1, rounds=1, start_excluded="fresh")

        assert seen[0].today is None

    def test_captured_injects_the_capture_date_not_the_wall_clock(self, fixture_room, monkeypatch):
        """🔴 **실행 시점 날짜를 쓰면 측정이 재현되지 않는다.**

        부산 픽스처는 2026-08-03 캡처에 종료일이 2026-08-05 다. `date.today()` 를 쓰면
        오늘 돌린 값과 내일 돌린 값이 다르고, 종료일을 지나면 음수가 된다.
        """
        seen: list[SuggestionRequest] = []
        self._patch_suggest_capturing_request(monkeypatch, seen)

        run_repeat(
            fixture_room, None, None, repeat=1, rounds=2, start_excluded="fresh", today="captured"
        )

        assert [r.today for r in seen] == [date(2026, 8, 3), date(2026, 8, 3)]
        assert captured_date(fixture_room) == date(2026, 8, 3)

    def test_a_failing_round_stops_that_repeat(self, fixture_room, monkeypatch):
        """실패하면 남은 라운드를 건너뛴다 — 제외가 안 쌓여 같은 조건의 재실행이 되어버린다."""

        def boom(request, llm, embed):  # noqa: ARG001
            raise RuntimeError("업스트림 죽음")

        monkeypatch.setattr("evals.run_room_eval.suggest", boom)

        results = run_repeat(fixture_room, None, None, repeat=1, rounds=3, start_excluded="fresh")

        assert len(results) == 1
        assert "RuntimeError: 업스트림 죽음" in results[0].error


class TestCli:
    """CLI 계약. 기본값이 **지금 운영**이어야 인자를 안 준 옛 측정과 비교가 성립한다."""

    def test_the_help_survives_a_cp949_console(self):
        """🔴 **작업 중 두 번 냈다.** Windows 콘솔 기본 코드페이지가 cp949 라, help 문구에
        em dash 나 이모지를 넣으면 `--help` 자체가 `UnicodeEncodeError` 로 죽는다.

        주석으로 적어두는 것만으로는 안 막혔다(두 번째를 그 주석 바로 아래에서 냈다).
        """
        build_parser().format_help().encode("cp949")

    def test_the_defaults_match_production(self):
        args = build_parser().parse_args([])

        assert args.exclusion_window == MAX_EXCLUDED
        assert args.today == "none"
        assert args.start_excluded == "fresh"

    def test_a_negative_window_is_rejected_but_zero_is_not(self):
        """0 은 #24 가 실제로 잰 값이다('제외를 아예 안 보낸다') — 막으면 안 된다."""
        assert build_parser().parse_args(["--exclusion-window", "0"]).exclusion_window == 0
        assert build_parser().parse_args(["--exclusion-window", "8"]).exclusion_window == 8


class TestConditionsAreRecorded:
    """조건이 **이름**과 **파일** 양쪽에 남는가.

    이 저장소는 같은 결함을 세 번 겪었다 — 조건을 손으로 나열하다 빠뜨리면 A/B 두 짝이
    구분되지 않는다(-235 P8 · 2026-08-03 리뷰 · `specs/OPEN.md`). 고리가 셋이라 셋을 다 본다:

        run_name  ──이름──┐
                          ├─ export[name] ─→ freeze_snapshot ─→ 스냅샷
        export_conditions ┘
    """

    AXES = (
        ("rounds", 4),
        ("repeats", 3),
        ("start_excluded", "captured"),
        ("critique", 0),
        ("partial_retry", True),
        ("exclusion_window", 8),
        ("today", "captured"),
    )
    """축을 늘리면 `run_name`·`export_conditions` 가 **인자를 요구해 이 목록이 빨개진다.**

    그게 설계다 — 축을 추가하고 여기 등록을 잊으면 조건이 이름·파일에 안 실리는데, 그 실수가
    이 저장소에서 세 번 났다.
    """

    def _kwargs(self, **overrides) -> dict:
        return {
            "rounds": 3,
            "repeats": 5,
            "start_excluded": "fresh",
            "critique": 1,
            "partial_retry": False,
            "exclusion_window": MAX_EXCLUDED,
            "today": "none",
        } | overrides

    def test_every_condition_changes_the_run_name(self):
        """한 축이라도 이름에 안 실리면 그 축의 A/B 가 서로를 덮는다."""
        baseline = run_name("m", **self._kwargs())

        for axis, value in self.AXES:
            assert run_name("m", **self._kwargs(**{axis: value})) != baseline, axis

    def test_every_condition_changes_the_export_block(self):
        """이름만 달라도 안 된다 — 파일 안에서도 구분돼야 근거가 된다."""
        baseline = export_conditions("m", **self._kwargs())

        for axis, value in self.AXES:
            assert export_conditions("m", **self._kwargs(**{axis: value})) != baseline, axis

    def test_the_export_block_satisfies_what_freeze_requires(self):
        """러너와 동결기의 계약. 어긋나면 **다 돌린 뒤 동결 단계에서** 죽는다 — 크레딧을 태우고."""
        from evals.freeze_snapshot import _ROOM_REQUIRED_CONDITIONS, room_conditions

        block = export_conditions("m", **self._kwargs())

        assert set(_ROOM_REQUIRED_CONDITIONS) <= set(block)
        # 조건 블록이 그대로 스냅샷으로 넘어간다(`rooms` 를 붙여도 조건은 안 사라진다).
        assert room_conditions(block | {"rooms": {}}) == block

    def test_the_window_size_reaches_the_snapshot(self):
        """이 커밋이 뚫은 축이 끝까지 가는지 — 러너 인자에서 스냅샷 파일까지."""
        from evals.freeze_snapshot import room_conditions

        block = export_conditions("m", **self._kwargs(exclusion_window=8))

        assert block["exclusion_window"] == 8
        assert room_conditions(block | {"rooms": {}})["exclusion_window"] == 8


class TestCritiqueFailOpenCounter:
    """검수가 우회된 라운드를 세는 계수기.

    ⚠️ **이 계수기는 `_critique` 의 로그 문구에 묶여 있다** — 문구가 바뀌면 조용히 0을 센다.
    그 결합을 여기서 고정한다. 계수기가 없어서 #29 ④ 의 수치에 커밋된 근거가 없었고,
    그것으로 별도 티켓의 심각도가 정해졌다(2026-08-03 리뷰 P1-1).
    """

    def _run(self, monkeypatch, emit: bool) -> RoundResult:
        from modi_ai.schemas import SuggestionResponse

        def fake_suggest(request, llm, embed):  # noqa: ARG001
            if emit:
                # `_critique` 의 세 갈래가 실제로 내는 것과 **같은 로거·같은 문구**다.
                logging.getLogger("modi_ai.suggest").error(
                    "검수 판정 개수가 안 맞는다(후보 %d개, 판정 %d개) — 전부 통과시킨다", 8, 7
                )
            return SuggestionResponse(candidates=candidates("후보"))

        monkeypatch.setattr("evals.run_room_eval.suggest", fake_suggest)
        request = load_room("busan_travel").request
        return run_round(request, None, None, room="r", repeat=1, round_index=1)

    def test_it_catches_a_bypassed_round(self, monkeypatch):
        assert self._run(monkeypatch, emit=True).critique_failed_open is True

    def test_a_normal_round_is_not_counted(self, monkeypatch):
        assert self._run(monkeypatch, emit=False).critique_failed_open is False

    def test_every_fail_open_branch_still_logs_the_watched_phrase(self):
        """위 두 테스트는 **내가 쓴 문구끼리** 맞춘 것이라, `_critique` 가 다른 말을 하게
        바뀌면 둘 다 통과하면서 계수기만 조용히 죽는다. 소스에서 직접 센다.

        fail-open 은 셋(예외 · 개수 불일치 · 번호 불일치)이고 전부 같은 문구를 남겨야 한다.
        """
        import modi_ai.suggest

        source = pathlib.Path(modi_ai.suggest.__file__).read_text(encoding="utf-8")
        logging_lines = [
            line
            for line in source.splitlines()
            if "전부 통과시킨다" in line and not line.lstrip().startswith("#")
        ]

        assert len(logging_lines) == 3, f"fail-open 로그가 셋이 아니다: {logging_lines}"

    def test_the_summary_counts_them(self):
        results = [
            RoundResult(room="r", repeat=1, round_index=1, excluded_before=0),
            RoundResult(room="r", repeat=1, round_index=2, excluded_before=0),
        ]
        results[0].critique_failed_open = True

        summary = summarize_room(load_room("busan_travel"), results, rounds=2)

        assert summary["critique_failed_open"] == 1


class TestUsageCollector:
    """토큰이 조용히 0 이 되는 것을 막는다 — **실제로 한 번 그렇게 됐다.**

    처음에는 `llm.with_config(callbacks=[...])` 로 붙였는데 `suggest._generate` 가 그 위에
    `with_structured_output()` 을 얹으면서 config 가 떨어져 나가 콜백이 **한 번도 안 불렸다.**
    리포트에는 `토큰 prompt 0` 이 찍혔고 그게 정상인지 고장인지 구분되지 않았다.
    지금은 `get_usage_metadata_callback()` 을 쓰고, 실행 끝에 총합이 0 이면 경고를 낸다.
    """

    def test_absorbs_the_per_model_shape(self):
        """`get_usage_metadata_callback()` 은 `{모델명: {…}}` 로 준다 — 모델이 여럿일 수 있다."""
        collector = UsageCollector()

        collector.absorb(
            {
                "gpt-5.4-nano": {"input_tokens": 100, "output_tokens": 20},
                "text-embedding-3-small": {"input_tokens": 7, "output_tokens": 0},
            }
        )

        assert (collector.prompt_tokens, collector.completion_tokens) == (107, 20)

    def test_it_accumulates_instead_of_replacing(self):
        """라운드 안에서 여러 번 흡수될 수 있다 — 덮어쓰면 마지막 호출분만 남는다.

        (앞 버전은 빈 dict 만 넣어봤는데, `absorb` 본문을 `pass` 로 바꿔도 통과했다.)
        """
        collector = UsageCollector()

        collector.absorb({"m": {"input_tokens": 10, "output_tokens": 1}})
        collector.absorb({})
        collector.absorb({"m": {"input_tokens": 5, "output_tokens": 2}})

        assert (collector.prompt_tokens, collector.completion_tokens) == (15, 3)


class TestFixtures:
    def test_both_committed_rooms_parse(self):
        """픽스처가 `SuggestionRequest` 로 파싱되지 않으면 러너는 크레딧을 쓰기 전에 죽어야 한다."""
        rooms = {f.slug: f for f in load_rooms()}

        assert set(rooms) == {"busan_travel", "opic_study"}
        assert len(rooms["busan_travel"].request.archive) == 13
        assert len(rooms["opic_study"].request.archive) == 21

    def test_archive_items_carry_full_embeddings(self):
        """벡터가 빠지면 `select` 노드의 유사도 축이 죽고 자료 순서가 달라진다."""
        for fixture in load_rooms():
            vectors = [item.embedding for item in fixture.request.archive]
            assert all(v is not None for v in vectors), f"{fixture.slug}: 벡터 없는 자료가 있다"
            assert {len(v) for v in vectors} == {1536}, f"{fixture.slug}: 차원이 섞였다"

    def test_content_is_the_summary_not_the_raw_body(self):
        """운영 `pickContent` 는 요약·본문 중 짧은 쪽을 고른다. 백필(232) 뒤라 전부 요약이다.

        캡처가 백필 전 상태로 돌아가면(본문 34,206자) 여기서 걸린다.
        """
        lengths = [len(i.content or "") for f in load_rooms() for i in f.request.archive]

        assert max(lengths) < 1_000, f"본문이 실린 자료가 있다(최대 {max(lengths)}자)"

    def test_missing_fixture_dies_loudly(self):
        """조용히 폴백하면 리포트에는 '방 데이터로 쟀다'가 남는데 실제로는 아니게 된다."""
        with pytest.raises(SystemExit, match="방 픽스처가 없다"):
            load_room("그런_방_없음")

    # 캡처 직후 `request` 블록의 SHA-256. **이 값을 손으로 고치면 안 된다** — 픽스처를 다시
    # 뜬 경우에만 새 해시로 바꾸고, 그때는 EXPERIMENTS 의 수치도 함께 다시 재야 한다.
    _REQUEST_DIGESTS = {
        "busan_travel": "b599d02f81b90dad",
        "opic_study": "8f4b787dfe151f58",
    }

    def test_fixtures_are_byte_identical_to_what_was_captured(self):
        """**`note` 문구만 검사하면 `request` 를 한 줄 고쳐도 초록이다**(리뷰 지적).

        픽스처의 존재 이유가 "운영이 보낸 것 그대로"이므로, 그 주장을 해시로 고정한다.
        """
        for slug in available_slugs():
            payload = json.loads((ROOM_DIR / f"{slug}.json").read_text(encoding="utf-8"))
            digest = hashlib.sha256(
                json.dumps(payload["request"], ensure_ascii=False, sort_keys=True).encode()
            ).hexdigest()[:16]

            assert payload["captured_at"]
            assert "재구현하지 않기 위해서다" in payload["note"]
            assert digest == self._REQUEST_DIGESTS[slug], (
                f"{slug} 의 request 가 캡처 이후 바뀌었다. 다시 뜬 것이면 해시와 함께 "
                "docs/EXPERIMENTS.md #26 의 수치도 다시 재야 한다."
            )


class TestAggregation:
    """집계를 러너 밖으로 뺀 이유는 `count_new_categories` 때와 같다 — 계산이 LLM 호출 안에
    묻히면 '모델이 안 낸다'와 '계수기가 못 센다'가 구분되지 않는다(리뷰 지적).
    """

    def test_mean_and_sd(self):
        assert mean_sd([2.0, 4.0, 6.0]) == (4.0, 2.0)

    def test_single_sample_reports_zero_sd(self):
        """표본 1개면 편차는 '0'이 아니라 '잴 수 없는 것'이다 — 표본 수를 함께 찍어 구분한다."""
        assert mean_sd([7.0]) == (7.0, 0.0)
        assert mean_sd([]) == (0.0, 0.0)

    def test_round_stats_groups_by_round_across_repeats(self):
        """3회차가 몇 개를 내는지가 마름 축이다 — 반복들 사이에서 모아야 한다."""
        results = [
            _round(repeat=1, round_index=1, titles=["a", "b", "c"]),
            _round(repeat=2, round_index=1, titles=["d", "e", "f", "g", "h"]),
            _round(repeat=1, round_index=2, titles=["i"]),
            _round(repeat=2, round_index=2, titles=["j", "k", "l"]),
        ]

        first, second = round_stats(results, 1), round_stats(results, 2)

        assert (first["count_mean"], first["count_min"], first["count_max"]) == (4.0, 3, 5)
        assert (second["count_mean"], second["samples"]) == (2.0, 2)

    def test_round_stats_excludes_failed_rounds(self):
        """실패를 후보 0개로 세면 마름이 실제보다 심해 보인다."""
        results = [
            _round(repeat=1, round_index=1, titles=["a", "b"]),
            _round(repeat=2, round_index=1, titles=[], error="BadGateway"),
        ]

        stats = round_stats(results, 1)

        assert (stats["samples"], stats["count_mean"]) == (1, 2.0)

    def test_title_length_stats_is_observation_not_a_gate(self):
        results = [_round(repeat=1, round_index=1, titles=["짧다", "가" * 25])]

        stats = title_length_stats(results)

        assert (stats["min"], stats["max"], stats["over_20"]) == (2, 25, 1)

    def test_exactly_twenty_characters_is_not_over(self):
        """`over_20` 은 초과지 이상이 아니다. 실측에 정확히 20자인 제목이 부산 2 · 오픽 6개
        있어서 경계가 실제로 밟힌다 — 앞 테스트는 2자/25자만 넣어 지나쳤다(리뷰 지적)."""
        results = [_round(repeat=1, round_index=1, titles=["가" * 20, "가" * 21])]

        assert title_length_stats(results)["over_20"] == 1

    def test_zero_tokens_with_candidates_is_flagged_loudly(self, capsys):
        """토큰 수집이 고장났을 때 경고가 실제로 나오는지 — **그 경고가 유일한 대책인데
        아무도 지키지 않고 있었다**(리뷰 지적)."""
        fixture = load_room("busan_travel")
        results = [_round(repeat=1, round_index=1, titles=["a"])]  # prompt_tokens 기본값 0

        summary = summarize_room(fixture, results, rounds=1)
        print_room_report(fixture, results, summary)

        assert "토큰이 0이다" in capsys.readouterr().out

    def test_no_warning_when_tokens_were_collected(self):
        """후보가 있고 토큰도 있으면 조용해야 한다 — 늘 경고하면 경고가 무의미해진다."""
        fixture = load_room("busan_travel")
        results = [_round(repeat=1, round_index=1, titles=["a"], prompt_tokens=2_478)]

        summary = summarize_room(fixture, results, rounds=1)

        assert summary["prompt_tokens"] == 2_478

    def test_summarize_room_reports_every_requested_round(
        self,
    ):
        """3라운드를 시켰는데 2회차에서 다 죽었어도 3회차 칸이 있어야 한다 — 없으면
        '측정 안 함'과 '후보 0개'가 리포트에서 구분되지 않는다."""
        fixture = load_room("busan_travel")
        results = [_round(repeat=1, round_index=1, titles=["a"])]

        summary = summarize_room(fixture, results, rounds=3)

        assert [s["round"] for s in summary["per_round"]] == [1, 2, 3]
        assert summary["per_round"][2]["samples"] == 0


def _round(
    *,
    repeat: int,
    round_index: int,
    titles: list[str],
    cats=None,
    error=None,
    prompt_tokens: int = 0,
):
    cats = cats if cats is not None else [None] * len(titles)
    return RoundResult(
        room="busan_travel",
        repeat=repeat,
        round_index=round_index,
        excluded_before=0,
        candidates=[
            {"title": t, "category": c, "source_item_id": None}
            for t, c in zip(titles, cats, strict=True)
        ],
        prompt_tokens=prompt_tokens,
        error=error,
    )
