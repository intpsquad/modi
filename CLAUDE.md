# 프로젝트: 팀 목표 협업 앱
한 줄 목적: 방(room)을 만들어 팀이 목표 기간 동안 투두·일정·아카이브를 공유하고 서로 독려하는 협업 앱.

## 아키텍처
- 모바일: **Flutter (Dart)** — `app/`. 라우팅 go_router, 상태 Riverpod, 자체 디자인 시스템.
- 백엔드: **Spring Boot 3.5.x (Java 21)** — `server/`. **3.x LTS 고정** — 4.x 등 상위 메이저로 임의 업그레이드 금지(안정성 우선, 2026-07-22 확정). PostgreSQL, 마이그레이션 Flyway, API 문서 springdoc-openapi.
- 인증: **Firebase Authentication** (소셜 4종 + 이메일). Firebase가 ID 토큰(JWT) 발급 → 서버가 Firebase Admin SDK로 검증. 도메인 데이터는 전부 서버 DB(Firebase는 인증·푸시 전용).
- AI(투두 추천/태깅): 앱이 아니라 **서버에서 LLM API 호출**. 제공사는 **OpenAI 직접**(`api.openai.com`, 키 `OPENAI_API_KEY`) — 2026-08-13에 전환했다(`specs/0001-architecture.md` 참고). **모델은 투두 추천·아카이브 요약·자동 태깅 셋 다 `gpt-5.4-nano`**(2026-08-13 통일). 단일 진실은 `ai/docs/DECISIONS.md`이고, 근거 없이 바꾸지 않는다.
  - ⚠️ **키 환경변수 이름을 바꿀 때는 서버 `.env`를 같은 배포에서 함께 바꿔야 한다.** 어긋나면 **부팅은 성공하고 AI 기능만 조용히 꺼진다**(`OpenAiConfig`의 `@ConditionalOnProperty`가 빈 문자열에도 매칭된다) — 로그에 아무 흔적이 없어 발견이 늦는다.

## 명령
### app/ (Flutter)
- 설치: `flutter pub get`
- 실행: `flutter run`
- 린트: `flutter analyze`
- 포맷: `dart format .`
- 테스트: `flutter test`
### server/ (Spring Boot)
- 빌드: `./gradlew build`
- 실행: `./gradlew bootRun`
- 테스트: `./gradlew test`

## 스펙 인덱스 — 단일 진실은 specs/ 파일들
- `specs/full_spec.md`        : **전체 IA 원본 — 최상위 진실.** 용어·탭 구성·화면별 요구사항의 근거. 수정 금지(원본 보존), 여기와 충돌하는 파생 스펙이 있으면 파생 쪽을 고친다.
- `specs/design.md`          : **디자인에 관한 유일한 진실.** 색·타이포·간격·라운드·엘리베이션·컴포넌트·상태 패턴. 구현체는 `app/lib/design/tokens.dart` + `theme.dart`
- `specs/0001-architecture.md`: 시스템 구조·인증 흐름·나중 네이티브 확장 경계
- `specs/0002-data-model.md` : 관계형 스키마 (엔티티·관계·상태 전이)
- `specs/0003-navigation.md` : 라우트 트리(go_router)·화면 전이표·재진입 로직
- `specs/NNNN-<기능>.md`      : 화면별 상세(S-xx). `full_spec.md`를 화면 단위로 쪼갠 파생본이며, **해당 화면에 대해서는 이 문서가 진실**
- `specs/OPEN.md`            : 미결 결정 트래커
> 네비게이션·데이터·디자인 규칙은 위 파일이 유일한 진실. 본문/코드에 복붙하지 말고 항상 해당 스펙을 열어 참조.
> **디자인은 `specs/design.md` 하나만 본다.** (2026-07-27: 기존 `design_full_spec.md`와 `DESIGN-airbnb.md`는 `design.md` v4로 통합·삭제됐다. S-00 디자인 시스템 → `design.md`, S-01~S-40 화면 상세 → `0004`~`0013`.)
> 요구사항이 충돌하면 `full_spec.md`(IA)가 이긴다 — 발견 즉시 파생 스펙을 고친다. 단 **디자인 값(색·크기·간격)은 예외로 `design.md`가 이긴다.**

## 규칙
- 편집 전 **plan mode**로 계획(변경 파일·리스크·테스트) 제시 후 승인받기.
- 한 번에 작은 작업 하나. 다중 파일 대규모 재작성 금지.
- **"됐다" 금지** — 테스트 출력/실행 결과/스크린샷 등 증거를 제시.
- 새 기능은 실패하는 테스트를 먼저 쓰고 통과시킨다.
- UI는 반드시 `specs/design.md`의 토큰만 사용(하드코딩 색/크기 금지).
- 화면/이동은 `specs/0003-navigation.md`를 따른다. 임의로 라우트를 만들지 않는다.
- 서버 인가: **방장 개념 없음** — 방 멤버는 동일 권한. 파괴적 액션(방 삭제·나가기·자료 삭제)은 앱에서 확인 모달.
- **git 협업 규칙(브랜치·커밋·이슈·PR·테스트·버저닝)의 단일 진실은 `CONTRIBUTING.md`다.** 여기에 복붙하지 말고 그 파일을 연다. 반드시 지킬 두 가지만 적는다:
  - **push 전엔 반드시 최신 `dev`를 병합한다** (`git fetch origin` → `git merge origin/dev`). 원격 브랜치가 앞서갔는지만 확인하는 걸로는 부족하다. `dev`/`main` 자체에 push할 때도 동일하게 선행한다. (2026-07-30 실제 사고: `dev` merge 커밋을 revert한 게 대상 브랜치가 아니라 `dev` 자체에 병합되면서 배포 설정이 통째로 사라짐 — 경위는 `CONTRIBUTING.md`.)
  - **커밋 타입은 소문자다** — `feat:` `fix:` `docs:` `refactor:` `test:` `chore:` `revert:` `design:` (2026-08-15 통일. 그 이전 커밋은 `Feat(ai):` 처럼 대문자+스코프였고 그대로 둔다). **`Co-Authored-By` 트레일러는 붙이지 않는다.**
- **추측 금지**: 명세에 없거나 모순되는 결정은 임의로 굳히지 말 것. `specs/OPEN.md`에 기록하고, 그 항목에 의존하는 구현 전에 **AskUserQuestion으로 사용자에게 물어** 확정한다.

## 건드리지 말 것
- `.env`, Firebase 서비스 계정 키(Admin SDK), 서명/키스토어 설정
- 생성된 코드, Flyway 마이그레이션 과거 파일(새 파일로만 변경)
- 인증(Firebase ID 토큰 검증) 코드는 수정 후 반드시 사람 최종 확인

## 완료 정의 (Definition of Done) — 아래를 모두 채워야 기능이 "완료"다
- 테스트 통과(서버 단위/통합 + 앱 위젯 테스트) + 인수 기준 충족(증거 제시)
- **API 명세 갱신**: 엔드포인트를 추가/변경하면 OpenAPI가 최신이어야 함(아래 문서 자동화 참조) + 필요 시 `docs/api/<기능>.md` 요약
- **ERD 갱신**: 스키마를 바꾸면 `specs/0002-data-model.md`의 엔티티 목록과 Mermaid `erDiagram`을 함께 수정
- **스펙 갱신**: 관련 `specs/`(navigation/data-model/해당 기능) 최신화
- **PROJECT_PLAN.md 갱신**: 기능이 커밋되면(`Feat`/`Feat!` 커밋) 그 즉시 `PROJECT_PLAN.md`의 "4. 개발 로드맵" 체크박스를 갱신하고, "구현 중"인 항목은 체크하지 않는다. 새 `specs/NNNN-*.md`를 추가했으면 "6. 지금 생성된 산출물"에도 반영한다. **이 프로젝트는 여러 세션/작업자가 병렬로 기능을 커밋할 수 있으므로, 다른 세션이 이미 커밋한 기능을 발견하면(로드맵에 반영 안 된 커밋) 그 세션이 아니어도 먼저 발견한 쪽이 갱신한다** — PROJECT_PLAN.md는 항상 "지금 git 로그 기준으로 뭐가 진짜 끝났는가"를 반영해야 하며, 특정 세션의 기억에 의존해서는 안 된다.
- reviewer 서브에이전트 리뷰 통과
> 문서 갱신이 빠진 기능은 완료가 아니다. `/feature-done` 스킬로 이 체크리스트를 강제한다.

## 로컬 전용 파일 (커밋 안 됨) — 생길 때마다 README.md에 기록
- `.env`, 키/인증서, `google-services.json`류처럼 개발자 각자 로컬에 준비해야 하는 파일이 새로 생기면(코드 작성 중이든 사용자가 직접 받아오든) **그 즉시 `README.md`의 "로컬 전용 파일" 절에 파일명·경로·용도·발급 방법을 추가**한다. 파일 내용/값 자체는 절대 기록하지 않는다.
- `.gitignore`에 없으면 함께 추가한다.
- 목록의 단일 진실은 README.md — 여기(CLAUDE.md)에는 중복 기재하지 않는다.

## 인프라 / CI·CD  *(2026-08-13 전면 교체 — 아래가 현재다)*
- **저장소**: **GitHub** (`intpsquad/modi`, **공개** — 2026-08-15 전환. 브랜치 보호가 무료 플랜에서는 공개 저장소에만 열려서다). MR 대신 **PR** 용어를 쓴다.
  - ⚠️ **2026-08-14에 오가니제이션을 `modintps` → `intpsquad` 로 개명했다**(번들 ID `com.intpsquad.modi` 와 맞춤). GitHub 이 옛 주소를 리다이렉트해 주지만 그 리다이렉트는 언제든 끊길 수 있으므로, 각자 로컬에서 `git remote set-url origin https://github.com/intpsquad/modi.git` 을 한 번 돌린다.
- **브랜치 3계층**: `main`(운영 — **머지하면 배포된다**) / `dev`(통합·테스트 — 배포 안 함) / `feat/<이슈번호>-<내용>`. 단일 진실은 `CONTRIBUTING.md`. 기본 브랜치는 `dev`다(PR 대부분이 `feat/*`→`dev`라, 기본이 `main`이면 base를 잘못 잡아 테스트를 건너뛴 채 운영에 머지될 수 있다).
- **CI/CD**: **GitHub Actions** — `.github/workflows/ci.yml` **한 파일**. 잡 6개(`changes`→`app`/`server`/`ai`→`gate`/`deploy`)를 `needs`로 묶어 "테스트 통과해야 배포"를 유지한다. 브랜치 보호의 필수 상태 체크는 **`gate` 하나만** 건다(경로 필터로 스킵된 잡을 필수로 걸면 PR이 영구 대기한다). Jenkins·`Jenkinsfile`은 제거했다.
- **배포 인프라**: **단일 오라클 클라우드 Ampere A1**(ARM aarch64, 4 OCPU/24GB, ap-tokyo-1)에 서버·PostgreSQL·Redis·MinIO·Caddy를 Docker로 운영. 접속은 `ssh modi` 별칭. 상세는 `README.md` "배포" 절.
  - ⚠️ **빌드는 러너가 아니라 서버에서 한다** — 러너는 x86_64, 서버는 ARM이라 러너에서 만든 이미지는 뜨지 않는다.
- **출시 대상**: **iOS 전용**. `app/android/`는 코드만 남아 있고 **CI·릴리스 경로가 없다**. iOS 릴리스는 Mac에서 수동(`docs/ios-release.md`) — 프라이빗 저장소의 macOS 러너가 분수를 10배로 소모해서였다. ⚠️ **2026-08-15 공개 전환으로 그 이유는 사라졌다**(공개 저장소는 Actions 무료). 아직 자동화하지 않았을 뿐이다.
- **팀·권한 소유 현황**: `docs/TEAM.md`.

## 문서 자동화 (하네스)
- **API 명세**: 서버에 `springdoc-openapi`를 넣어 컨트롤러에서 OpenAPI/Swagger UI를 **자동 생성**(수기 유지 아님 → 드리프트 없음). CI(`.github/workflows/ci.yml`의 `server` 잡)가 `./gradlew build` 중 `docs/api/openapi.json`을 재생성하고, 커밋된 버전과 다르면 `git diff --exit-code`로 실패시켜 갱신 누락을 잡는다.
- **ERD**: `specs/0002-data-model.md`의 Mermaid `erDiagram`을 단일 진실로 유지. 스키마 변경 커밋에 ERD 변경이 없으면 리뷰에서 지적. (원하면 SchemaSpy로 상세 리포트 추가)
- **커밋 규칙**: 서버 컨트롤러/마이그레이션이 바뀐 커밋은 각각 API 문서/ERD 변경을 동반해야 한다.
