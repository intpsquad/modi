"""요약 프롬프트 복제본이 **Spring 원본과 같은지** 확인한다 — 크레딧 0 · 네트워크 0.

`evals/summarize_fixtures.py` 는 평가 픽스처의 요약을 만들 때 Spring 과 **같은 프롬프트**를 써야
한다. 다르면 "운영과 같은 입력으로 쟀다" 는 기록이 거짓이 되는데, **틀려도 아무 데서도 터지지
않는다** — 요약은 그럴듯하게 나오고 리포트는 정상으로 보인다. 그래서 여기서 못 박는다.

원본은 `server/.../client/OpenAiSummaryClient.java` 의 `SYSTEM_PROMPT`(Java text block)다.
Java 쪽에도 이 문자열을 고정하는 테스트가 있으므로, 프롬프트를 고치면 **양쪽이 같이 빨개진다.**

⚠️ **한계**: CI 의 `ai` 잡은 경로 필터 `ai/**` 로 걸려 있어서
**Java 만 바뀐 커밋에서는 이 테스트가 돌지 않는다.** 그 커밋은 Java 쪽 테스트가 잡고, 여기는
다음 `ai/` 변경 때 잡는다. 그 사이에 요약을 재생성하면 조건이 어긋난 상태로 동결될 수 있으니,
`_meta.json` 의 `prompt_fingerprint` 를 함께 볼 것.
"""

import json
import re
from pathlib import Path

import pytest

from evals.summarize_fixtures import META_PATH, check_prompt_matches_frozen, prompt_fingerprint
from evals.summarize_fixtures import SYSTEM_PROMPT as PYTHON_COPY

JAVA_SOURCE = (
    Path(__file__).resolve().parents[2]
    / "server/src/main/java/com/nomara/modi/server/domain/archive/client/OpenAiSummaryClient.java"
)


def extract_java_text_block(source: str, field: str) -> str:
    """Java text block 을 문자열로 되살린다 — **쓰이는 문법만** 다룬다.

    구현하는 규칙(JLS 3.10.6 중 이 파일이 실제로 쓰는 것):

    - 여는 `\"\"\"` 다음 줄부터 닫는 `\"\"\"` 앞 줄까지가 내용
    - 들여쓰기는 **비어 있지 않은 내용 줄과 닫는 구분자 줄**의 공통 최소값만큼 벗긴다
    - 줄 끝 공백은 버린다
    - 마지막 줄이 `\\` 로 끝나면 그 줄바꿈을 없앤다

    다루지 **않는** 것: `\\s` 이스케이프, 문자열 연결(`+`), 내용 줄 안의 `\"\"\"`.
    그런 문법이 들어오면 조용히 틀린 값을 내지 말고 죽어야 하므로 아래에서 검사한다.
    """
    match = re.search(rf'{re.escape(field)}\s*=\s*\n?\s*"""\n', source)
    if match is None:
        raise AssertionError(
            f"{field} 의 text block 을 못 찾았다. Java 쪽 선언 형태가 바뀌었으면 "
            "이 추출기를 함께 고칠 것 — 그냥 두면 '원본과 같다' 를 확인할 방법이 사라진다."
        )

    rest = source[match.end() :]
    closing = re.search(r'^[ \t]*"""', rest, re.MULTILINE)
    if closing is None:
        raise AssertionError(f"{field} 의 닫는 구분자를 못 찾았다")

    body = rest[: closing.start()]
    lines = body.split("\n")
    if lines and lines[-1] == "":
        lines.pop()  # 닫는 구분자 줄 앞의 개행

    indent_sources = [line for line in lines if line.strip()] + [closing.group()]
    indent = min(len(line) - len(line.lstrip()) for line in indent_sources)
    stripped = [line[indent:].rstrip() for line in lines]

    if any("\\s" in line or line.endswith("\\\\") for line in stripped):
        raise AssertionError("이 추출기가 다루지 않는 이스케이프가 들어왔다 — 추출기를 고칠 것")

    if stripped and stripped[-1].endswith("\\"):
        stripped[-1] = stripped[-1][:-1]
        return "\n".join(stripped)
    return "\n".join(stripped) + "\n"


class TestSummaryPromptDrift:
    def test_java_source_is_where_we_think_it_is(self):
        """경로가 틀리면 아래 테스트가 **통과할 방법이 없다** — 원인을 먼저 분리해 둔다."""
        assert JAVA_SOURCE.exists(), JAVA_SOURCE

    def test_python_copy_matches_the_java_original(self):
        java = extract_java_text_block(JAVA_SOURCE.read_text(encoding="utf-8"), "SYSTEM_PROMPT")

        assert PYTHON_COPY == java, (
            "요약 프롬프트가 Spring 과 갈렸다. evals/summarize_fixtures.py 의 복제본을 맞추고, "
            "이미 동결한 요약이 있으면 --force 로 다시 만들 것."
        )


class TestFrozenFingerprint:
    """일부만 다시 만들면 **두 프롬프트의 요약이 한 디렉터리에 섞인다** — 리뷰 지적."""

    def test_the_committed_summaries_match_the_current_prompt(self):
        """커밋된 `_meta.json` 이 지금 프롬프트로 만든 것인지. 어긋나면 재생성 신호다."""
        meta = json.loads(META_PATH.read_text(encoding="utf-8"))

        assert meta["prompt_fingerprint"] == prompt_fingerprint()

    def test_partial_regeneration_dies_when_the_prompt_changed(self):
        with pytest.raises(SystemExit, match="섞인다"):
            check_prompt_matches_frozen({"prompt_fingerprint": "옛날지문"}, force=False)

    def test_force_regenerates_everything_so_nothing_mixes(self):
        check_prompt_matches_frozen({"prompt_fingerprint": "옛날지문"}, force=True)

    def test_a_first_run_has_no_fingerprint_yet(self):
        check_prompt_matches_frozen({}, force=False)


class TestExtractJavaTextBlock:
    """추출기 자체의 테스트. **이게 틀리면 위 대조가 통과해도 의미가 없다.**"""

    def test_strips_common_indentation_including_the_closing_delimiter(self):
        source = 'static final String P =\n      """\n      가\n      나\n      """;\n'

        assert extract_java_text_block(source, "P") == "가\n나\n"

    def test_closing_delimiter_deeper_than_content_does_not_over_strip(self):
        """닫는 구분자가 더 깊으면 공통값은 내용 줄이 정한다."""
        source = 'static final String P =\n  """\n  가\n      """;\n'

        assert extract_java_text_block(source, "P") == "가\n"

    def test_blank_lines_survive_and_do_not_set_the_indent(self):
        source = 'static final String P =\n    """\n    가\n\n    나\n    """;\n'

        assert extract_java_text_block(source, "P") == "가\n\n나\n"

    def test_trailing_backslash_suppresses_the_final_newline(self):
        source = 'static final String P =\n    """\n    가\\\n    """;\n'

        assert extract_java_text_block(source, "P") == "가"

    def test_dies_when_the_field_is_gone(self):
        with pytest.raises(AssertionError, match="못 찾았다"):
            extract_java_text_block('static final String Q =\n  """\n  가\n  """;\n', "P")
