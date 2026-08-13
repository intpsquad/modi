"""동결 스냅샷 생성기의 순수 함수 — **크레딧 0 · 네트워크 0.**

동결 스냅샷은 `docs/EXPERIMENTS.md` 수치의 **유일한 근거**다(러너 export 는 `.gitignore`).
그래서 여기서 못 박는 것은 "조건 필드가 빠지지 않는가" 하나다 — 조건 없는 숫자는 근거가 못 된다.
"""

from evals import freeze_snapshot as freeze


def _payload(**overrides) -> dict:
    payload = {
        "model": "m",
        "rule4": True,
        "schema_category_hint": True,
        "input": "summary",
        "categories": ["공부"],
        "temperature": 0.0,
        "summary": {"candidates": 1},
        "cases": [
            {
                "stem": "001_x",
                "raw_candidate_count": 1,
                "candidates": [],
                "raw_categories": ["여행"],
                "prompt_tokens": 900,
                "seconds": 1.4,
                "dropped_by_filter": 0,
                "error": None,
            }
        ],
    }
    return payload | overrides


def _room_payload(**overrides) -> dict:
    payload = {
        "model": "m",
        "rounds": 3,
        "repeats": 5,
        "start_excluded": "fresh",
        "critique_max_attempts": 2,
        "regenerate_on_partial_reject": True,
        "temperature": "운영 기본값",
        "rooms": {
            "busan_travel": {
                "summary": {"total_candidates": 1},
                "rounds": [
                    {
                        "room": "busan_travel",
                        "repeat": 1,
                        "round_index": 1,
                        "excluded_before": 0,
                        "candidates": [{"title": "화목정따로국밥 방문하기"}],
                        "prompt_tokens": 900,
                        "completion_tokens": 80,
                        "seconds": 9.4,
                        "error": None,
                        "critique_failed_open": False,
                    }
                ],
            }
        },
    }
    return payload | overrides


class TestBuildRoom:
    """⚠️ **-235 리뷰 P8 이 잡힌 자리가 정확히 여기인데 테스트가 없었다.**

    그때 조건 필드(`critique_max_attempts`)를 안 옮겨 A/B 두 짝이 파일만 봐서 구분되지
    않았다. 필드와 주석만 추가하고 회귀 테스트를 안 붙여서, -237 에서 `.get(...)` 으로
    바꿔도 395개가 전부 통과했다(2026-08-03 리뷰 P2). 두 티켓 분을 여기서 닫는다.
    """

    def test_every_condition_field_is_carried_over(self):
        snapshot = freeze.build_room("run-a", _room_payload(), "2026-08-03", None)

        for field in (
            "model",
            "rounds",
            "repeats",
            "start_excluded",
            "critique_max_attempts",
            "regenerate_on_partial_reject",
            "temperature",
        ):
            assert field in snapshot, field

    def test_the_conditions_keep_their_values(self):
        """존재만 보면 안 된다 — 값이 안 흐르면 조건이 전부 같아 보인다.

        -235 때 "조건을 검사한다"던 테스트가 실제로는 모든 조건에서 같은 값(`rounds`)만
        보고 있었다. 여기서는 **기본값과 다른 값**을 넣어 흐르는지 본다.
        """
        snapshot = freeze.build_room(
            "run-a",
            _room_payload(critique_max_attempts=0, regenerate_on_partial_reject=False),
            "2026-08-03",
            None,
        )

        assert snapshot["critique_max_attempts"] == 0
        assert snapshot["regenerate_on_partial_reject"] is False

    def test_a_missing_condition_field_is_loud(self):
        """조건이 빠진 export 로 얼리면 **죽어야 한다.** 조용히 기본값을 채우면 그게 바로
        P8 의 사고 — 조건 없는 스냅샷이 근거처럼 커밋된다."""
        payload = _room_payload()
        del payload["regenerate_on_partial_reject"]

        try:
            freeze.build_room("run-a", payload, "2026-08-03", None)
        except KeyError:
            return
        raise AssertionError("조건 필드가 없는데 조용히 얼렸다")

    def test_candidates_are_kept_in_full(self):
        """후보 전문이 있어야 지표를 나중에 새로 정의해도 크레딧 0 으로 다시 채점한다."""
        snapshot = freeze.build_room("run-a", _room_payload(), "2026-08-03", None)
        rounds = snapshot["rooms"]["busan_travel"]["rounds"]

        assert rounds[0]["candidates"] == [{"title": "화목정따로국밥 방문하기"}]
        assert rounds[0]["seconds"] == 9.4

    def test_a_condition_the_builder_never_heard_of_is_carried_over(self):
        """🔴 **여기가 같은 결함이 세 번째로 나는 자리다.**

        조건 필드를 손으로 나열하면, 러너에 조건을 추가할 때 **여기를 같이 고치는 것을 잊는다.**
        -235(P8)·2026-08-03 리뷰가 같은 것을 두 번 잡았고 그때마다 필드를 하나 더 적어 막았다.
        나열을 유지하는 한 다음 조건에서 또 난다 — `specs/OPEN.md` 가 올려둔 항목이다.

        그래서 못 박는 것은 "필드 하나가 있다"가 아니라 **빌더가 모르는 조건도 따라온다**이다.
        이 테스트가 통과하면 `--exclusion-window` 든 `--today` 든 freeze 를 안 고쳐도 실린다.
        """
        snapshot = freeze.build_room("run-a", _room_payload(exclusion_window=8), "2026-08-03", None)

        assert snapshot["exclusion_window"] == 8

    def test_results_do_not_leak_into_the_conditions(self):
        """조건을 통째로 옮기더라도 **결과는 조건이 아니다.**

        `rooms` 는 라운드별 관측값이라 별도로 정제해 담는다. 최상위에 그대로 올라오면
        "이 실행의 조건"을 읽는 사람이 결과를 조건으로 착각한다.

        ⚠️ `build_room` 출력만 보면 **이 검사가 헛돈다** — `**room_conditions(...)` 가
        `"rooms": {...}` 보다 앞에 있어서, 결과가 새어 나와도 뒤 항목이 덮어쓴다. 그래서
        조건 블록을 **직접** 본다.
        """
        conditions = freeze.room_conditions(_room_payload())

        assert "rooms" not in conditions

    def test_the_snapshot_owns_its_metadata(self):
        """export 에 `run` 같은 이름이 섞여 들어와도 스냅샷 메타데이터를 덮지 못한다.

        `**conditions` 를 펼치는 구조라 이 방어가 없으면 조건 하나가 `run`·`measured_at` 을
        조용히 갈아치울 수 있다 — 그러면 어느 실행인지가 거짓이 된다.
        """
        snapshot = freeze.build_room(
            "run-a",
            _room_payload(run="딴-실행", measured_at="1999-01-01"),
            "2026-08-03",
            None,
        )

        assert snapshot["run"] == "run-a"
        assert snapshot["measured_at"] == "2026-08-03"

    def test_the_rounds_keep_exactly_the_recorded_observations(self):
        snapshot = freeze.build_room("run-a", _room_payload(), "2026-08-03", None)

        assert set(snapshot["rooms"]) == {"busan_travel"}
        assert set(snapshot["rooms"]["busan_travel"]["rounds"][0]) == {
            "repeat",
            "round_index",
            "excluded_before",
            "candidates",
            "prompt_tokens",
            "completion_tokens",
            "seconds",
            "error",
            "critique_failed_open",
        }


class TestSlugify:
    def test_spaces_become_hyphens(self):
        """실행 이름에 `할 일` 처럼 공백이 든 카테고리가 들어간다."""
        assert freeze.slugify("m_summary_할 일_repeat") == "m_summary_할-일_repeat"

    def test_path_separators_are_replaced(self):
        """카테고리 이름은 사용자 입력이라 `/` 가 들어올 수 있다 — 디렉터리를 만들면 안 된다."""
        assert "/" not in freeze.slugify("m_summary_공부/여행")
        assert "\\" not in freeze.slugify("m_summary_공부\\여행")


class TestBuild:
    def test_every_condition_field_is_carried_over(self):
        snapshot = freeze.build("run-a", _payload(), "2026-08-01", None)

        for field in ("rule4", "schema_category_hint", "input", "categories", "temperature"):
            assert field in snapshot, field
        assert snapshot["run"] == "run-a"
        assert snapshot["measured_at"] == "2026-08-01"

    def test_per_case_observations_are_kept(self):
        """**문서가 인용하는 값은 전부 커밋돼야 한다.**

        처음엔 로더가 읽는 세 키만 남겼는데, 그러면 EXPERIMENTS #20 의 응답시간·토큰 절이
        `.gitignore` 된 export 에만 남는다 — 이 티켓이 없애려던 실패 유형 그 자체다.
        로더는 특정 키만 인덱싱하므로 여분 키는 무해하다(`TestRoundTrip` 이 확인).
        """
        case = freeze.build("run-a", _payload(), "2026-08-01", None)["cases"][0]

        assert set(case) == {
            "stem",
            "raw_candidate_count",
            "candidates",
            "raw_categories",
            "prompt_tokens",
            "seconds",
            "dropped_by_filter",
            "error",
        }

    def test_the_note_is_omitted_when_absent(self):
        assert "_note" not in freeze.build("run-a", _payload(), "2026-08-01", None)

    def test_the_note_is_kept_when_given(self):
        snapshot = freeze.build("run-a", _payload(), "2026-08-01", "이 실행만의 사정")

        assert snapshot["_note"] == "이 실행만의 사정"


class TestRoundTrip:
    def test_the_real_loader_reads_what_build_produces(self):
        """포맷이 어긋나면 **커밋한 뒤에야** 알게 된다 — 여기서 왕복시킨다."""
        import json
        import tempfile
        from pathlib import Path

        from evals import dataset

        payload = _payload(
            cases=[
                {
                    "stem": "001_x",
                    "raw_candidate_count": 1,
                    "candidates": [{"title": "가", "category": "공부", "source_item_id": 1}],
                    "raw_categories": ["자격증 공부"],
                    "prompt_tokens": 900,
                    "seconds": 1.4,
                    "dropped_by_filter": 0,
                    "error": None,
                }
            ]
        )
        snapshot = freeze.build("run-a", payload, "2026-08-01", None)

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "snap.json"
            path.write_text(json.dumps(snapshot, ensure_ascii=False), encoding="utf-8")
            # `load_snapshot` 은 SNAPSHOT_DIR 기준이라 잠시 갈아끼운다. `lru_cache` 도 비운다.
            original, dataset.SNAPSHOT_DIR = dataset.SNAPSHOT_DIR, Path(tmp)
            dataset.load_snapshot.cache_clear()
            try:
                loaded = dataset.load_snapshot("snap.json")
            finally:
                dataset.SNAPSHOT_DIR = original
                dataset.load_snapshot.cache_clear()

        assert [c.title for case in loaded for c in case.candidates] == ["가"]


class TestItFreezesWhatTheRunnersActuallyProduce:
    """🔴 **위 픽스처는 옛 모양이다** (2026-08-04 리뷰 P0-2).

    `_payload` 가 `rule4`·`categories`·`raw_categories` 를 넣는데 이후
    러너는 그걸 안 낸다. 그래서 `freeze_snapshot` 이 `KeyError` 로 죽는데도 이 파일은
    초록이었다 — **아무 러너도 못 얼리는 상태**로 통과했다.

    옛 픽스처를 지우지 않는 이유: 그 조건으로 얼린 스냅샷 8개가 아직 커밋돼 있고, 다시
    얼릴 일이 생기면 그 모양도 읽혀야 한다. **두 모양 다 되는지**를 본다.
    """

    def _current_suggest_payload(self) -> dict:
        """`run_suggest_eval` 이 **지금** 내는 모양 — 카테고리 축이 전부 없다."""
        return {
            "model": "m",
            "input": "summary",
            "temperature": 0.0,
            "summary": {"candidates": 1},
            "cases": [
                {
                    "stem": "001_x",
                    "raw_candidate_count": 1,
                    "candidates": [{"title": "가", "source_item_id": 1}],
                    "prompt_tokens": 900,
                    "seconds": 1.4,
                    "dropped_by_filter": 0,
                    "error": None,
                }
            ],
        }

    def test_a_suggest_run_without_the_category_axis_freezes(self):
        snapshot = freeze.build("run", self._current_suggest_payload(), "2026-08-04", None)

        assert snapshot["run"] == "run"
        assert snapshot["input"] == "summary"
        # 사라진 축은 `None` 으로 남는다 — 키를 지우면 옛 스냅샷 로더가 깨진다.
        assert snapshot["rule4"] is None
        assert snapshot["categories"] is None

    def test_the_candidates_survive_the_freeze(self):
        """후보 전문이 스냅샷의 본체다. 비면 나중에 다시 채점할 수 없다."""
        snapshot = freeze.build("run", self._current_suggest_payload(), "2026-08-04", None)

        assert snapshot["cases"][0]["candidates"] == [{"title": "가", "source_item_id": 1}]

    def test_a_room_run_without_category_stats_freezes(self):
        """`summarize_room` 이 `categories` 를 더 이상 안 낸다 — 있던 시절엔 하드 인덱싱이었다."""
        payload = {
            "model": "m",
            "rounds": 3,
            "repeats": 5,
            "start_excluded": "fresh",
            "critique_max_attempts": 1,
            "regenerate_on_partial_reject": False,
            "temperature": "운영 기본값",
            "rooms": {
                "busan_travel": {
                    "summary": {"total_candidates": 1, "fixture_digest": "x"},
                    "rounds": [
                        {
                            "repeat": 1,
                            "round_index": 1,
                            "excluded_before": 0,
                            "candidates": [],
                            "prompt_tokens": 0,
                            "completion_tokens": 0,
                            "seconds": 1.0,
                            "error": None,
                            "critique_failed_open": False,
                        }
                    ],
                }
            },
        }

        snapshot = freeze.build_room("run", payload, "2026-08-04", None)

        assert snapshot["rooms"]["busan_travel"]["summary"]["total_candidates"] == 1
