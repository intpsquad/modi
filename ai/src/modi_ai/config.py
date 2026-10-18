"""환경 설정. 값은 ai/.env 에서 읽고, 없으면 아래 기본값을 쓴다.

키(OPENAI_API_KEY·INTERNAL_API_KEY·LANGSMITH_API_KEY)는 기본값을 빈 문자열로 둔다 —
없는 상태로도 서버가 뜨고 헬스체크가 동작해야 하기 때문이다. 실제로 키가 필요한
엔드포인트를 만들 때 그 시점에 검증한다.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # OpenAI (직접 호출)
    # 🔴 2026-08-13: 게이트웨이 경유 → OpenAI 직접 호출로 바꿨고, 회수된 게이트웨이의 이름을
    # 딴 필드명도 이 이름으로 개명했다. 값은 OpenAI 플랫폼 키(sk-...)다.
    # ⚠️ 이 이름을 또 바꿀 때는 운영 .env 를 **같은 배포에서** 함께 바꿔야 한다 — 어긋나면
    # 서버는 정상 부팅하고 AI 기능만 조용히 꺼진다(아래 키가 빈 문자열이어도 뜨기 때문이다).
    openai_api_key: str = ""
    openai_base_url: str = "https://api.openai.com/v1/"
    # 투두 추천 생성 모델. 2026-07-30 사용자 지시로 gpt-4.1-mini 에서 교체.
    # 2026-08-13: 태깅·요약도 이 값으로 통일됐다(EXPERIMENTS #34) — 세 기능이 한 모델을 쓴다.
    # ⚠️ **추천 워크로드로 재본 실측이 아직 없다** — 사용자가 "이 모델로 가고 근거는 결과를 내며
    # 찾는다"로 확정했다. 없는 근거를 있는 것처럼 적지 않기 위해 그대로 남긴다(docs/DECISIONS.md).
    # 참고로 가진 인접 실측은 요약 워크로드뿐이다(EXPERIMENTS #14: 1.3~2.8초 · 추론 토큰 0).
    openai_model: str = "gpt-5.4-nano"
    # (2026-10-18: `openai_embedding_model` 을 지웠다 — 이 서버는 임베딩을 부르지 않는다, #109.
    #  자료 임베딩은 Spring 이 `ARCHIVE_EMBEDDING_MODEL` 로 만든다.)

    # 프롬프트의 "아카이브 자료" 절에 넣을 수 있는 최대 글자 수. 넘으면 뒤쪽 자료부터
    # 버린다(`ranking.select_archive`).
    #
    # ⚠️ **2026-08-09: 성격이 바뀌었다 — 안전밸브가 아니라 상시 발동하는 선별기다.**
    # 원래 값 12,000 은 "발동하지 않는 크기"를 노린 것이었는데(자료 약 58건분), 시연 응답시간
    # 목표(5초) 때문에 **입력을 고정 상한으로 묶기로 했다**(사용자 확정). 3,000 자는 206자/건
    # 실측 기준 **약 14~15건**이다.
    #
    # 근거가 된 실측:
    #   · 2026-08-02 방 "회화 스터디" 자료 18건 = 렌더 합계 3,709자(206자/건, input 2,982 tok)
    #   · 2026-08-09 운영 방 "춘천여행" 자료 35건 = 앱 실측 응답 25.9 / 28.5 / 30.1초
    #
    # ⚠️ **품질은 재지 않았다.** "자료가 몇 건일 때 추천 품질이 나빠지는가"는 여전히 모른다 —
    # 이 값은 품질이 아니라 지연을 근거로 정했다. 자료가 15건 넘는 방은 오래된 자료가 추천
    # 근거에서 빠진다는 뜻이고, 그 대가를 알고 받았다.
    archive_prompt_budget_chars: int = 3_000

    # 예산 안에 넣을 자료를 **최신순**으로 고를지, 기존 4축 가중 순위(좋아요·핀·목표유사도·
    # 최근성)로 고를지.
    #
    # **True 로 확정했다**(2026-08-09 사용자 확정). 예산이 상시 발동하게 되면서 "무엇이 잘리는가"가
    # 처음으로 중요해졌고, 시연에서는 **직전에 추가한 자료가 반드시 들어가는 것**이 요구사항이다.
    # 순위로 고르면 방금 넣은 자료가 좋아요 0·핀 없음이라 밀려날 수 있다.
    #
    # ⚠️ **대가 — 핀·좋아요·목표 유사도가 선별에서 빠진다.** 방 목표와 무관한 최신 자료가
    # 프롬프트를 채울 수 있고, 그 영향은 재지 않았다.
    #
    # False 로 두면 순위 모드로 돌지만 **목표 유사도 축은 빠진다** — 2026-10-18 에 목표 임베딩
    # 왕복을 걷어냈다(#109, 외부 호출은 LLM 1회뿐). 핀·좋아요·최근성 세 축으로 줄 세운다.
    archive_select_by_recency: bool = True

    # (2026-10-18: `critique_max_attempts`·`regenerate_on_partial_reject` 를 지웠다 — 검수·재생성
    #  코드를 걷어냈다, #109. 2026-08-14 부터 0/False 로 꺼져 있었다. 측정과 경위는
    #  `docs/EXPERIMENTS.md` #28·#29 와 `docs/DECISIONS.md`.)

    # Spring 만 호출할 수 있게 하는 공유 시크릿
    internal_api_key: str = ""

    # LangSmith — 운영에서는 반드시 false.
    # 이 값들은 그냥 두면 SDK 에 닿지 않는다(SDK 는 os.environ 만 본다) — `tracing.py` 참고.
    langsmith_tracing: bool = False
    langsmith_api_key: str = ""
    langsmith_project: str = "modi-ai"


@lru_cache
def get_settings() -> Settings:
    return Settings()
