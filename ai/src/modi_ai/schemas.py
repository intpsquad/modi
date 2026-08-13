"""투두 추천(S-16-B) 요청·응답 모델.

필드는 서버 도메인(`server/.../domain/{Room,Category,Todo,ArchiveItem}.java`)의 실제 컬럼을
그대로 따른다. 이 서버는 도메인 DB를 직접 보지 않으므로 필요한 값은 전부 요청에 실려 온다.
"""

from datetime import date, datetime

from pydantic import BaseModel, Field

# `specs/0006-투두-탭.md` 엣지케이스의 클라이언트 검증값과 맞춘다(투두 제목 1~50자).
# 스키마 제약(max_length)이 아니라 설명 + 사후 필터로 다루는 이유는 suggest.filter_candidates 참고.
MAX_TITLE_LENGTH = 50

# 카테고리 이름 상한. **서버가 실제로 거부하는 값**과 맞춘다 —
# `CreateCategoryRequest` 의 `@Size(min = 1, max = 20)`, `specs/0006-투두-탭.md` 클라이언트 검증.
#
# ⚠️ **지금 이 파일에서 쓰는 곳이 없다** — AI 가 카테고리를 정하지 않게 되면서
# `_clean_category` 와 함께 소비자가 사라졌다. **그래도 남긴다**: `git revert` 로 되살릴 때
# 같이 돌아와야 하고, 서버 제약을 한 곳에 적어두는 값 자체는 유효하다.
MAX_CATEGORY_LENGTH = 20


class ArchiveItemInput(BaseModel):
    """추천의 근거가 되는 자료.

    뒤의 네 필드(`embedding`·`pinned`·`like_count`·`created_at`)는 **프롬프트에 실을 순서를
    정하는 축**이다(`ranking.py`). 전부 기본값이 있는 이유는 둘이다 —
    평가 픽스처가 이 축들을 모르고, 이 필드를 싣기 전 버전의 Spring 도 그대로 통과해야 한다.
    """

    id: int
    title: str
    content: str | None = Field(
        default=None,
        description=(
            "자료의 AI 요약 또는 본문. **어느 쪽인지는 Spring이 고른다**(요약·본문 중 짧은 쪽) — "
            "이 서버는 구분하지 않는다. 요약을 쓰는 것이 이 필드의 목적이고, 요약이 없는 자료가 "
            "정상적으로 있어서 본문 폴백이 함께 필요하다. 크롤링 전(PENDING)·실패(FAILED)면 둘 다 "
            "없어 None 이다."
        ),
    )
    tags: list[str] = Field(default_factory=list)
    embedding: list[float] | None = Field(
        default=None,
        description=(
            "Spring 이 자료 등록 시점에 만들어 둔 벡터(`archive_items.embedding`). "
            "**None 이 정상인 경우가 넷 있다**(`V7__add_embedding_to_archive_items.sql`) — "
            "그 자료는 유사도 축에서만 빠지고 나머지 세 축으로 후보에 남는다."
        ),
    )
    pinned: bool = False
    like_count: int = 0
    created_at: datetime | None = Field(
        default=None, description="최근성 축. 없으면 그 축에서만 빠진다"
    )


class RoomInput(BaseModel):
    name: str
    goal: str
    goal_detail: str | None = None
    start_date: date
    end_date: date


class SuggestionRequest(BaseModel):
    room: RoomInput
    """⚠️ `categories`(방의 기존 카테고리명)를 **더 이상 받지 않는다** 

    Spring 이 아직 보내도 `extra` 기본값(무시)이라 깨지지 않는다 — 배포 순서를 맞출 필요가 없다.
    되살리는 방법은 `docs/RESTORE-category-assignment.md`.
    """

    existing_todos: list[str] = Field(default_factory=list)
    excluded_todos: list[str] = Field(
        default_factory=list, description="이미 후보로 노출한 투두 — 재노출하지 않는다"
    )
    archive: list[ArchiveItemInput] = Field(default_factory=list)

    today: date | None = Field(
        default=None,
        description=(
            "요청 시점의 날짜(KST 기준). 프롬프트에 '오늘'과 종료까지 남은 일수를 넣는 데 쓴다 "
            "— 이게 없으면 모델은 지금이 언제인지 몰라서 D-2 와 D-28 에 같은 후보를 낸다."
        ),
    )
    """⚠️ **이 서버가 `date.today()` 로 구하지 않는다.** 이유가 둘이다.

    ① **평가 재현성** — 방 픽스처는 과거 캡처다(`evals/data/rooms/`). 실행 시점 날짜를 쓰면
       같은 스냅샷이 날마다 다른 값을 내고, 픽스처 종료일을 지나면 음수가 된다.
    ② **시간대** — 배포 컨테이너에 `TZ` 가 없어 프로세스가 **UTC** 로 돈다(`specs/OPEN.md`).
       KST 자정 전후로 "오늘"이 하루 어긋난다. 그 판단은 KST 를 아는 Spring 이 한다.

    `None` 이면 프롬프트에서 그 줄이 **아예 빠진다** — Spring 이 아직 안 보내도 동작이 같다.
    """


class TodoCandidate(BaseModel):
    """LLM 출력 스키마이자 API 응답 항목."""

    title: str = Field(
        description=f"한국어 투두 제목. {MAX_TITLE_LENGTH}자 이내의 동작 가능한 문장"
    )
    """⚠️ `category` 를 **더 이상 내보내지 않는다** 

    AI 가 카테고리를 정하지 않고 후보는 **기타(미분류)** 로 나간다. 사용자가 투두 탭에서 직접
    분류한다(제품 결정, 2026-08-04).

    **받는 쪽은 안 고쳐도 된다** — Spring 의 `AiCandidate` 는 Java record 라 키가 없으면 `null`
    이 들어가고, 그 `null` 을 앱에 그대로 넘긴다. 앱의 `_resolveCategoryId` 는 이름이 비면
    `null`(= 기타)을 돌려주므로 채택한 투두가 기타로 간다 — 원하는 동작 그대로다.

    왜 지웠는지와 되살리는 방법은 `docs/RESTORE-category-assignment.md`.
    """

    source_item_id: int | None = Field(
        default=None, description="이 후보의 근거가 된 자료의 id. 반드시 입력에 있는 id여야 한다"
    )


class SuggestionResponse(BaseModel):
    candidates: list[TodoCandidate] = Field(default_factory=list)


class CritiqueVerdict(BaseModel):
    """검수 판정 1건. **API 로 나가지 않는다** — 그래프 내부 전용이다."""

    index: int = Field(description="입력 후보 목록에 적힌 번호. 그대로 돌려준다")
    ok: bool = Field(description="바로 실행할 수 있는 일이면 true")
    reason: str | None = Field(
        default=None,
        description="반려 사유 한 문장. 다시 만들 때 모델에게 그대로 보여준다. 통과면 비운다",
    )


class CritiqueResponse(BaseModel):
    """⚠️ `verdicts` 는 **입력 후보와 개수가 같아야 한다.** 어긋나면 `suggest._critique` 가
    판정을 통째로 버리고 전부 통과시킨다 — 검수 층 고장이 추천 장애가 되면 안 된다.
    """

    verdicts: list[CritiqueVerdict] = Field(default_factory=list)
