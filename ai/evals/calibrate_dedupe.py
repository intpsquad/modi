"""의미 중복 임계값 캘리브레이션.

`drop_semantic_duplicates` 의 임계값을 **근거 없이 박지 않기 위한** 러너다.
지표를 먼저 만들고 데이터를 맞추는 실수를 반복하지 않는다(`ai/CLAUDE.md`).

입력은 2026-07-30 에뮬레이터 실측 데이터다 — 방 "회화 스터디"(목표: 오픽)에서 추천을
3 회 눌러 나온 24 개 후보 전부. `todo_suggestion_exposures` 에 실제로 저장됐던 값이고,
이 파일이 유일한 사본이다(DB 는 검증 후 비웠다).

실행:
    uv run python -m evals.calibrate_dedupe

크레딧: 임베딩 호출 1 회(24 개 짧은 문자열 배치).
"""

import time

from modi_ai.embeddings import get_embedder
from modi_ai.ranking import cosine
from modi_ai.suggest import SEMANTIC_DUPLICATE_THRESHOLD

# 회차별 후보. 순서·표기 모두 DB 에 저장됐던 그대로다.
ROUND_1 = [
    "OPIc 공식 사이트에서 평가기준 및 문제유형 가이드 PDF 내려받기",
    "서베이 주제 중 1분 이상 말할 수 있는 관심사 3~4개 고르기",
    "OPIc 시험 전 필수 준비물과 수험 규정신분증 확인하기",
    "OPIc 시험센터 위치와 접수기간 내 시험장 변경 가능 여부 확인하기",
    "단기간 AL 목표로 6-6 난이도 선택 및 두괄식 답변 연습하기",
    "감정표현을 포함한 스크립트 템플릿 반복 연습하기",
    "모바일 유튜브 모의고사를 활용해 주제별 답변 구조 연습하기",
    "스픽 어플을 활용해 난이도별 수업과 프리톡 AI 기능 체험하기",
]

ROUND_2 = [
    "시험 전 과거시제 점검과 두괄식 감정표현 답변 연습하기",
    "응시료 대학생 할인 방법과 배우는 템플릿 반복 연습하기",
    "시험에서 스킵할 문제 과감히 넘기는 연습하기",
    "서베이에서 자신 있는 주제 3~4개 선별 및 어휘 연습하기",
    "유튜브 모의고사로 주제별 답변 구조 연습하고 표현 정리하기",
    "오픽 서베이 및 돌발 질문 대비 필러와 메인포인트 익히기",
    "오픽 시험 전 필수 준비물인 규정신분증 원본 준비 확인하기",
    "출퇴근길에 자주 쓰는 표현 속으로 반복하여 암기하기",
]

ROUND_3 = [
    "오픽 응시료 대학생 할인 방법 확인하기",
    "유튜브 모의고사로 다양한 주제별 답변 구조 연습하기",
    "서베이 관심 주제 3~4개 선별 및 어휘 확장 연습하기",
    "스픽 어플 프리톡 AI 기능 체험하며 실전 말하기 연습하기",
    "오픽 시험 전 오픽 공식 사이트 평가기준 및 문제유형 PDF 내려받기",
    "두괄식 문장과 감정표현을 포함한 답변 연습하기",
    "서베이 전략으로 필러 및 메인포인트 자연스럽게 익히기",
    "롤플레이와 다양한 실제 질문에 대비한 답변 팁 연습하기",
]

ALL_TITLES = ROUND_1 + ROUND_2 + ROUND_3

# 눈으로 판정한 정답. "같은 행동을 다시 시키는가"를 기준으로 삼았다 —
# 같은 주제(오픽)라는 이유만으로는 중복이 아니다.
SHOULD_MATCH: list[tuple[str, str]] = [
    (ROUND_1[6], ROUND_2[4]),  # 유튜브 모의고사 답변 구조
    (ROUND_1[6], ROUND_3[1]),
    (ROUND_2[4], ROUND_3[1]),
    (ROUND_1[0], ROUND_3[4]),  # 평가기준·문제유형 PDF 내려받기
    (ROUND_1[1], ROUND_2[3]),  # 서베이 주제 3~4개 선별
    (ROUND_1[1], ROUND_3[2]),
    (ROUND_2[3], ROUND_3[2]),
    (ROUND_1[2], ROUND_2[6]),  # 규정신분증 준비물 확인
    (ROUND_2[1], ROUND_3[0]),  # 응시료 대학생 할인
    (ROUND_1[7], ROUND_3[3]),  # 스픽 어플 프리톡 AI
    (ROUND_2[5], ROUND_3[6]),  # 필러·메인포인트
]

# 경계 확인용. 같은 도메인이지만 시키는 행동이 다르다 — 이것들이 걸리면 임계값이 너무 낮다.
SHOULD_NOT_MATCH: list[tuple[str, str]] = [
    (ROUND_2[2], ROUND_2[0]),  # 스킵 연습 vs 과거시제 점검
    (ROUND_1[3], ROUND_1[2]),  # 시험장 변경 vs 준비물 확인
    (ROUND_2[7], ROUND_1[4]),  # 출퇴근길 암기 vs 난이도 선택
    (ROUND_3[7], ROUND_1[1]),  # 롤플레이 대비 vs 서베이 주제 선별
    (ROUND_1[5], ROUND_1[3]),  # 스크립트 템플릿 vs 시험장 변경
]


def _summarise(name: str, scores: list[float]) -> None:
    ordered = sorted(scores)
    print(
        f"{name:14s} n={len(scores):2d}  min={ordered[0]:.3f}  "
        f"median={ordered[len(ordered) // 2]:.3f}  max={ordered[-1]:.3f}"
    )


def main() -> None:
    embed = get_embedder()

    started = time.perf_counter()
    vectors = embed(ALL_TITLES)
    elapsed = time.perf_counter() - started
    by_title = dict(zip(ALL_TITLES, vectors, strict=True))
    print(f"임베딩 1회 호출: {len(ALL_TITLES)}개 제목 · {elapsed:.2f}초 · 차원 {len(vectors[0])}\n")

    match_scores = [cosine(by_title[a], by_title[b]) for a, b in SHOULD_MATCH]
    other_scores = [cosine(by_title[a], by_title[b]) for a, b in SHOULD_NOT_MATCH]

    print("== 중복이어야 하는 쌍 ==")
    for (a, b), score in sorted(zip(SHOULD_MATCH, match_scores, strict=True), key=lambda t: t[1]):
        print(f"  {score:.3f}  {a[:34]:34s} | {b[:34]}")
    print("\n== 중복이 아니어야 하는 쌍 ==")
    for (a, b), score in sorted(
        zip(SHOULD_NOT_MATCH, other_scores, strict=True), key=lambda t: -t[1]
    ):
        print(f"  {score:.3f}  {a[:34]:34s} | {b[:34]}")

    print()
    _summarise("중복이어야", match_scores)
    _summarise("아니어야", other_scores)

    # 전체 쌍 분포 — 위 정답 라벨과 무관하게 값이 어디에 몰려 있는지 본다.
    every = [
        cosine(vectors[i], vectors[j])
        for i in range(len(ALL_TITLES))
        for j in range(i + 1, len(ALL_TITLES))
    ]
    _summarise("전체 쌍", every)

    # 이 기능에서는 오탐이 미탐보다 비싸다 — 오탐은 쓸 만한 새 후보를 조용히 지우고,
    # 미탐은 중복이 한 번 더 보이는 것(= 지금 상태)에 그친다. 게다가 "6~7번 누르면 후보가
    # 마른다"가 이미 관측돼 있어 과하게 거르면 빈 화면이 빨라진다.
    # 그래서 임계값은 "라벨된 비중복 쌍을 하나도 걸지 않는 최저값"으로 잡는다.
    ceiling = max(other_scores)
    floor = min(match_scores)
    print()
    print(f"비중복 최대 {ceiling:.3f} / 중복 최소 {floor:.3f}")
    if ceiling < floor:
        print(f"[OK] 완전히 갈린다. 후보 구간 {ceiling:.3f} ~ {floor:.3f}")
        return

    print("[WARN] 단일 임계값으로 라벨 전부를 가르지 못한다(구간이 겹친다).")
    print("       오탐 0 을 우선해 임계값을 비중복 최대값 바로 위로 잡는다.")
    for threshold in (0.65, 0.70, 0.75, 0.80, 0.85, 0.90):
        caught = sum(1 for s in match_scores if s >= threshold)
        false_positive = sum(1 for s in other_scores if s >= threshold)
        print(
            f"       t={threshold:.2f}  잡음 {caught:2d}/{len(match_scores)}  "
            f"오탐 {false_positive}/{len(other_scores)}"
        )
    print(f"\n       채택 임계값 {SEMANTIC_DUPLICATE_THRESHOLD} 로 못 잡는 중복 쌍(미탐):")
    for score, a, b in sorted(
        (s, a, b)
        for (a, b), s in zip(SHOULD_MATCH, match_scores, strict=True)
        if s < SEMANTIC_DUPLICATE_THRESHOLD
    ):
        print(f"         {score:.3f}  {a[:30]} | {b[:30]}")

    # 라벨이 붙지 않은 쌍이 임계값을 넘는지 본다. 이걸 안 보면 "오탐 0" 이 라벨 누락이 만든
    # 착시일 수 있다 — 실제로 0.699 짜리 미라벨 중복이 채택값 바로 아래에 있었다(리뷰 P2-1).
    labelled = {frozenset(p) for p in SHOULD_MATCH + SHOULD_NOT_MATCH}
    unlabelled = sorted(
        (
            (cosine(vectors[i], vectors[j]), ALL_TITLES[i], ALL_TITLES[j])
            for i in range(len(ALL_TITLES))
            for j in range(i + 1, len(ALL_TITLES))
            if frozenset((ALL_TITLES[i], ALL_TITLES[j])) not in labelled
        ),
        reverse=True,
    )
    print("\n       라벨 없는 상위 쌍 — 눈으로 확인할 것(오탐 후보):")
    for score, a, b in unlabelled[:5]:
        mark = " <== 임계값 이상" if score >= SEMANTIC_DUPLICATE_THRESHOLD else ""
        print(f"         {score:.3f}  {a[:28]} | {b[:26]}{mark}")


if __name__ == "__main__":
    main()
