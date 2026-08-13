---
name: feature-done
description: 기능 구현을 마무리할 때 완료 정의(Definition of Done)를 강제하는 체크리스트를 실행한다. "/feature-done"으로 호출.
---
이 기능이 정말 완료됐는지 CLAUDE.md의 완료 정의로 점검하고, 빠진 것을 채운다:
1. 테스트: 서버/앱 테스트가 통과하는지 실제로 실행해 출력을 보여준다.
2. API 명세: 엔드포인트 변경이 있으면 OpenAPI가 반영됐는지 확인, `docs/api/openapi.json` 내보내기 최신화. 필요 시 `docs/api/<기능>.md` 요약 갱신.
3. ERD: 스키마 변경이 있으면 `specs/0002-data-model.md`의 엔티티/Mermaid erDiagram을 수정.
4. 스펙: 관련 `specs/`를 최신화.
5. PROJECT_PLAN.md: "4. 개발 로드맵"에서 이번에 끝난 항목을 체크하고, 새 spec 파일을 추가했으면 "6. 지금 생성된 산출물"에도 반영. 이때 내 세션이 모르는 사이 다른 세션이 이미 커밋해놓은 기능이 있는지 `git log --oneline`으로 먼저 확인하고 함께 반영한다(로드맵은 항상 git 로그 기준 최신 상태여야 함).
6. reviewer 서브에이전트로 최종 리뷰.
하나라도 빠지면 "완료"라고 말하지 말고 그 항목을 먼저 채운다.
