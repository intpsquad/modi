# MODI — 팀 목표 협업 앱

> **방(room)을 만들어 팀이 목표 기간 동안 투두·일정·자료를 함께 관리하고 서로 독려하는 협업 앱.**
> 혼자 쓰는 할 일 앱이 아니라, "같은 목표를 향한 팀"이 진행 상황을 한눈에 보고 서로를 밀어주는 데 초점을 맞췄다.

---

## 📖 소개

여러 개의 "할 일 앱"은 개인의 목록에서 끝나지만, **MODI**는 팀 단위다. 팀은 목표와 기간을 가진 **방**을 만들고, 그 안에서:

- **투두**를 카테고리·담당자·마감일로 나눠 맡고,
- **일정**을 공유 캘린더로 관리하며,
- **자료(모아보기)** 를 링크·메모로 아카이브하면 AI가 요약·태깅해 주고,
- **홈 대시보드**에서 D-day·진행률·팀원 활동을 실시간으로 확인하고,
- **콕찌르기·협업 캐릭터**로 서로 동기부여한다.

목표 기간이 끝나면 방은 자동으로 종료되고 그때까지의 기록이 남는다.

## ✨ 주요 기능

| 영역 | 내용 |
|---|---|
| **방(협업 공간)** | 목표·기간을 가진 방 생성, 초대코드/카카오 공유로 참여, 여러 방 전환, 종료된 방 기록. **방장 개념 없이 멤버 전원 동일 권한** |
| **홈 대시보드** | D-day·팀 진행률, 팀원 아바타·개인 진행률, 주간 캘린더, 오늘 투두·자료 미리보기, **실시간 팀 활동 배너** |
| **투두** | 카테고리별 관리, 담당자 다중 지정(미지정 가능), 마감일, 완료 토글, 수동 드래그 정렬, **AI 투두 추천**, 미지정 처리 |
| **일정** | 공유 캘린더 기반 일정 생성·조회, 전날/디데이 알림 |
| **모아보기(자료)** | 링크·메모 아카이브, 폴더 정리, 핀·좋아요, **AI 자동 요약·태깅**, OS 공유시트로 외부 앱에서 바로 등록 |
| **마이페이지** | 프로필, **협업 캐릭터**(활동 기반 자동 판정), 로그인 수단, 알림 설정, 회원 탈퇴 |
| **동기부여** | 콕찌르기, 협업 캐릭터·진화, 팀 활동 피드 |
| **인증** | 소셜 로그인 4종(카카오·구글·애플·이메일) + Firebase Authentication |
| **알림** | Firebase Cloud Messaging 푸시(콕찌르기·일정·방 활동·담당 투두 등), 알림 내역 |

## 🛠 기술 스택

| 구분 | 스택 |
|---|---|
| **모바일** | Flutter (Dart) · 라우팅 `go_router` · 상태관리 `Riverpod` · 자체 디자인 시스템(디자인 토큰) |
| **백엔드** | Spring Boot 3.5.x (LTS) · Java 21 · PostgreSQL · 마이그레이션 Flyway · API 문서 springdoc-openapi(자동 생성) |
| **AI** | 서버에서 LLM 호출(**OpenAI 직접**, `gpt-5.4-nano`) — 투두 추천·아카이브 요약·자동 태깅. 옛 LLM 게이트웨이 경유였으나 프로젝트 종료로 2026-08-13 전환 |
| **인증/푸시** | Firebase Authentication(ID 토큰 JWT) + Admin SDK 검증, Firebase Cloud Messaging |
| **스토리지** | MinIO(프로필·방 커버·자료 썸네일 등 이미지, presigned URL 업로드) |
| **인프라** | GitHub · CI/CD **GitHub Actions**(`.github/workflows/ci.yml`) · 단일 **Oracle Cloud Ampere A1**(ARM aarch64, 4 OCPU/24GB)에 서버·PostgreSQL·Redis·MinIO·Caddy를 Docker로 운영 |
| **출시 대상** | **iOS 전용**(2026-08-13 확정). `app/android/`는 코드만 남아 있고 **CI·릴리스 경로가 없다** |

## 🏗 아키텍처 (요약)

```
[Flutter 앱]  ──(Firebase 로그인)──▶  Firebase Auth ──▶ ID 토큰(JWT)
     │                                                     │
     └──(ID 토큰 + API 요청)──▶  [Spring Boot 서버] ──(Admin SDK로 토큰 검증)
                                     │
                     ┌───────────────┼───────────────────┐
                 PostgreSQL       MinIO(이미지)      OpenAI API(LLM)
                 (도메인 데이터)   presigned URL      투두추천·요약·태깅
```

- **Firebase는 인증·푸시 전용**, 도메인 데이터는 전부 서버 DB에 둔다.
- **AI는 앱이 아니라 서버가** LLM API를 호출한다.
- 배포는 **단일 오라클 클라우드 인스턴스**(ARM)에 서버·DB·Redis·MinIO·Caddy를 Docker로 함께 운영한다.
  CI 는 서버 밖(GitHub Actions)에서 돌고, 배포만 SSH 로 들어와 서버에서 이미지를 만든다.

> 시스템 구조·인증 흐름·배포 상세: [`specs/0001-architecture.md`](./specs/0001-architecture.md)

## 📱 화면 구성

하단 **5탭** 셸: **홈 · 투두 · 일정 · 모아보기 · 마이**
(온보딩 → 소셜/이메일 로그인 → 방 생성/참여 → 5탭 진입. 하위 화면은 전체 화면으로 push.)

> 화면별 상세는 [`specs/`](./specs)의 `0004`~`0017` 문서, 디자인은 [`specs/design.md`](./specs/design.md).

## 👥 팀

**계속 운영하는 4명**이다(2026-08-13). 권한·자산을 누가 쥐고 있는지는
[`docs/TEAM.md`](./docs/TEAM.md) — 인계 없이 사람이 바뀌면 배포가 막히는 것들이 적혀 있다.

| 이름 | 역할 |
|---|---|
| 윤주하 | 프론트엔드 |
| 김예원 | 프론트엔드 |
| 박민영 | 백엔드 |
| 김주우 | 인프라 · 배포 · AI 서버 |

---

> 규칙·아키텍처·데이터 모델·네비게이션의 **단일 진실**은 [`CLAUDE.md`](./CLAUDE.md)와 [`specs/`](./specs)에 있다.
> 아래부터는 **로컬 실행·배포 가이드**다.

## 리포 구조

```
app/            Flutter 앱
server/         Spring Boot 서버
ai/             FastAPI AI 서버 (투두 추천 전용)
deploy/         운영 배포 (compose · Caddyfile · deploy.sh)
specs/          스펙 (디자인·아키텍처·데이터모델·네비게이션)
docs/api/       OpenAPI 명세 (자동 생성, 손으로 고치지 않음)
.github/workflows/  GitHub Actions CI/CD (ci.yml 한 파일)
```

## 사전 준비

**아래 버전은 CI(`.github/workflows/ci.yml`)에 못박은 값과 같아야 한다.** 한 곳만 올리면 안 된다.

| 도구 | 버전 | 확인 | CI 에서 고정하는 곳 |
|---|---|---|---|
| Flutter | **3.44.8** (stable) | `flutter --version` | `subosito/flutter-action` 의 `flutter-version` |
| JDK | **21** (Temurin 권장) | `java -version` | `actions/setup-java` |
| uv (AI 서버) | **0.11.26** | `uv --version` | `astral-sh/setup-uv` 와 `ai/Dockerfile` |
| Docker | 로컬 PostgreSQL·Redis 구동용 | `docker --version` | — |

> 🔴 **Flutter 버전이 다르면 로컬은 통과하고 CI 만 깨진다.** `dart format` 의 출력이 버전마다
> 달라서인데, CI 는 `dart format --output=none --set-exit-if-changed .` 로 **차이가 있으면 실패**
> 시킨다. 증상이 "내 코드는 멀쩡한데 포맷 잡이 빨감"이라 원인을 짚기 어렵다. 그래서 버전을
> `app/.fvmrc` 에 선언해 뒀다 — [fvm](https://fvm.app) 을 쓰면 그 버전이 자동으로 맞는다:
>
> ```bash
> dart pub global activate fvm     # 1회
> cd app && fvm install && fvm flutter --version   # .fvmrc 의 3.44.8 을 받아 쓴다
> ```
>
> fvm 을 쓰지 않아도 된다 — 대신 `flutter --version` 이 위 표와 같은지 직접 확인할 책임이 생긴다.
>
> 🔴 **`analyze`·`test` 만 돌리고 끝내지 말 것.** 이 검사는 **별개 명령**이라 그 둘을 통과해도
> 잡히지 않는다. 실제로 2026-08-13 에 그렇게 깨진 커밋이 들어왔다 — 문자열 치환으로 한 줄이
> 3자 늘어 80자를 넘겼는데, 치환 후 `analyze`·`test` 만 다시 돌려 통과로 보고했다.
> 커밋 전 게이트는 **셋이다**: `dart format --output=none --set-exit-if-changed .` ·
> `flutter analyze` · `flutter test`.
>
> 🔴 **그리고 그 셋을 CI 와 같은 Flutter 버전으로 돌려야 한다.** 같은 날 첫 CI 가 이것 때문에
> 깨졌다 — 로컬 3.44.8 에서 포맷 검사가 통과했는데 CI 는 3.44.7 로 고정돼 있어 실패했다.
> **`flutter-version`(ci.yml) · `.fvmrc` · 위 표 세 곳을 항상 같이 바꾼다.**

Windows에서 Flutter/JDK가 설치는 됐는데 PATH에 없다면 세션에서 한 번만 추가:

```powershell
$env:PATH = "C:\Users\<you>\flutter\bin;$env:PATH"
$env:PATH = "C:\Program Files\Eclipse Adoptium\jdk-21.x.x.x-hotspot\bin;$env:PATH"
```

### Windows/macOS 개발 환경 초기화

운영 비밀값은 만들거나 커밋하지 않고, 각 개발자의 로컬 템플릿만 한 번에 준비한다. 기존 로컬 파일은 덮어쓰지 않는다.

| 환경 | 스크립트 | 생성되는 로컬 파일 |
|---|---|---|
| macOS/Linux | `./scripts/setup-dev.sh` | `server/.env`, `ai/.env`, `app/env/dev.json`, macOS에서는 `app/ios/Flutter/Local.xcconfig` |
| Windows PowerShell | `./scripts/setup-dev.ps1` | `server/.env`, `ai/.env`, `app/env/dev.json` |

macOS:

```bash
chmod +x scripts/setup-dev.sh
./scripts/setup-dev.sh --print-fingerprints
```

Windows PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\setup-dev.ps1 -PrintFingerprints
```

Firebase 설정 파일까지 갱신할 때는 먼저 Firebase 콘솔에 팀원의 Android debug SHA-1을 추가한 뒤 다음 옵션을 붙인다:

```bash
# macOS/Linux
./scripts/setup-dev.sh --configure-firebase

# Windows PowerShell
.\scripts\setup-dev.ps1 -ConfigureFirebase
```

현재 Firebase 앱 식별자는 Android·iOS 모두 `com.nomara.modi.app`을 사용한다. `--configure-firebase`는 `modi-mara` 프로젝트에서 Android·iOS·Web 설정을 다시 생성한다. `deploy/.env`와 Firebase 서비스 계정 JSON은 운영/권한 파일이므로 개발자 초기화 스크립트가 만들지 않는다.

## app/ 실행

```bash
cd app
flutter pub get
flutter run
```

- 린트: `flutter analyze`
- 포맷 검사: `dart format --output=none --set-exit-if-changed .` (자동 정리는 `dart format .`)
- 테스트: `flutter test`

### Kakao 로그인 개발 설정

Kakao 로그인은 카카오 Flutter SDK가 받은 access token을 Spring의 `/auth/kakao`에서 Firebase Custom Token으로 교환한다. Kakao native app key와 Firebase 서비스 계정 키는 저장소에 커밋하지 않는다.

Android 실행:

```bash
cd app
flutter run -d <device> \
  --dart-define=KAKAO_NATIVE_APP_KEY=<kakao-native-app-key>
```

iOS 실행:

```bash
cd app
cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig
# Local.xcconfig의 KAKAO_NATIVE_APP_KEY 값을 실제 native app key로 교체
flutter run -d <device> \
  --dart-define=KAKAO_NATIVE_APP_KEY=<kakao-native-app-key>
```

`Local.xcconfig`는 iOS URL scheme용이고 `--dart-define`은 Dart SDK 초기화용이므로 같은 키를 두 곳에 넣어야 한다. `env/dev.json`을 사용한다면 `KAKAO_NATIVE_APP_KEY` 항목을 로컬 파일에 추가해도 된다.

서버에는 Firebase Admin SDK 서비스 계정이 필요하다. `server/.env`의 `FIREBASE_CREDENTIALS_PATH`가 해당 JSON 파일을 가리켜야 `/auth/kakao`가 Custom Token을 발급할 수 있다. 설정이 없으면 서버는 부팅되지만 해당 로그인 요청에 503을 반환한다. 카카오 access token이나 서비스 계정 private key를 채팅·소스·URL에 넣지 않는다.

### Apple 로그인 개발 설정

Apple 로그인은 별도 OAuth 패키지 없이 Firebase Authentication의 네이티브 `AppleAuthProvider`를 사용한다. 저장소에는 Apple credential·private key를 저장하지 않는다.

1. Apple Developer의 App ID `com.nomara.modi.app`에서 **Sign in with Apple** capability를 활성화하고, 변경된 provisioning profile을 Xcode에서 다시 받는다.
2. Firebase Console → Authentication → Sign-in method에서 **Apple** provider를 활성화한다. Firebase가 요구하는 Service ID, Apple Team ID, Key ID, private key는 Firebase Console에만 등록하고 `.p8` private key는 저장소나 채팅에 넣지 않는다.
3. `app/ios/Runner.xcworkspace`를 열어 Runner target의 Signing & Capabilities에서 Sign in with Apple이 켜져 있는지 확인한다. entitlement와 capability 선언은 저장소에 반영되어 있다.
4. Apple ID 2단계 인증과 iCloud가 설정된 iOS 실기기에서 로그인한다. 첫 승인 뒤 이름·이메일을 다시 제공하지 않을 수 있고, 이메일 비공개를 선택하면 `privaterelay.appleid.com` 주소가 사용된다.

### API 서버 주소 (실기기 vs 에뮬레이터)

`API_BASE_URL`은 `--dart-define`으로 오버라이드하는 컴파일타임 값이다(`lib/config/env.dart`). 기본값은 안드로이드 에뮬레이터 기준 `http://10.0.2.2:8080`(개발 머신 localhost를 가리키는 에뮬레이터 전용 주소).

- **에뮬레이터**: 기본값 그대로 `flutter run` — 별도 설정 불필요.
- **실기기(USB)**: `adb reverse tcp:8080 tcp:8080`로 폰의 localhost:8080을 PC의 8080에 연결한 뒤 `flutter run --dart-define=API_BASE_URL=http://localhost:8080` (VS Code에서는 `app (real device via USB)` 실행 구성 사용).

### VS Code에서 실행 (권장)

저장소를 **루트에서** 열면 `.vscode/`의 공유 설정이 그대로 적용된다. 서버는 IntelliJ에서 돌리고, VS Code는 앱 전용으로 쓴다.

1. 처음 열면 권장 확장(Dart, Flutter) 설치 알림이 뜬다 — 설치.
2. 하단 상태바에서 실행할 **기기 선택**(실기기 또는 에뮬레이터). `app/`에는 `android/`·`ios/`만 있어 웹·데스크톱 타깃은 없다.
3. `F5` → `app (debug)` 실행(핫 리로드). 프로파일/릴리즈는 실행 구성 드롭다운에서 `app (profile)` / `app (release)`.
4. `Ctrl+Shift+P` → **Tasks: Run Task** → `app: preflight` 로 커밋 전 게이트(포맷 검사 → analyze → test)를 CI와 동일하게 한 번에 돌린다. 개별 태스크(`app: pub get`/`format`/`analyze`/`test`)와 DB 태스크(`db: up`/`db: down`/`db: psql`)도 같은 목록에 있다.

- 디자인 토큰: `lib/design/tokens.dart`(색·타이포·스페이싱) / `lib/design/theme.dart`(ThemeData) — 하드코딩 금지, 반드시 여기 토큰만 사용.
- 라우트: `lib/routing/app_router.dart` — `specs/0003-navigation.md`가 단일 진실. 아직 미구현 화면은 `PlaceholderScreen`으로 스텁 처리돼 있음.

## server/ 실행

```bash
cd server
docker compose up -d          # 로컬 PostgreSQL(5432, modi/modi/modi) + Redis(6379, 초대코드 전용)
./gradlew bootRun
```

- 헬스체크: `GET http://localhost:8080/actuator/health`
- DB 접속: `docker exec -it modi-postgres psql -U modi -d modi` (컨테이너 이름은 `modi-postgres`로 고정)
- API 문서(Swagger UI): `http://localhost:8080/docs`
- 빌드+테스트: `./gradlew build`
- `docs/api/openapi.json`은 손으로 고치지 않는다 — `./gradlew test` 실행 시 `OpenApiExportTest`가 실제 `/v3/api-docs` 응답으로 재생성한다. 컨트롤러를 바꿨다면 테스트를 돌려 이 파일도 같이 커밋할 것(안 그러면 CI 의 OpenAPI 드리프트 검사 실패).
- 마이그레이션: `src/main/resources/db/migration/` (Flyway).
- `SchemaValidationTest`/`RoomServiceTest`(둘 다 Testcontainers)가 윈도우 + Docker Desktop 환경에서 `docker info` 호출에 HTTP 400을 받아 실패할 수 있음(Docker Desktop npipe 프록시 호환성 문제, `docker` CLI 자체는 정상). 코드 문제 아님 — CI(리눅스 러너)에서는 정상 통과한다. 로컬에서 급히 확인해야 하면 `docker compose up -d` 상태에서 `./gradlew bootRun` 실행 후 "Started ServerApplication" 로그 + `curl`/`psql`/`redis-cli`로 대체 확인 가능.

## 로컬 전용 파일 (커밋 안 됨, 각자 준비해야 함)

이 파일들은 `.gitignore`에 걸려 있어 저장소에 없다 — 아래 경로에 각자 준비해야 앱/서버가 정상 동작한다. 새 파일이 추가되면 이 표도 함께 갱신한다(CLAUDE.md 규칙).

| 파일 | 용도 | 발급 방법 |
|---|---|---|
| `app/android/app/google-services.json` | Firebase Android 클라이언트 설정(Google 로그인 OAuth 클라이언트 포함) — **이 파일만 복사해선 Google 로그인이 안 된다. 아래 "Google 로그인 SHA-1 지문 등록" 절을 반드시 함께 볼 것** | `flutterfire configure -p modi-mara --platforms=android -a com.nomara.modi.app -y` (`app/`에서 실행, `firebase login` 먼저 필요) — 아래 `firebase_options.dart`와 함께 자동 생성됨. 수동으로는 Firebase 콘솔 → 프로젝트 설정 → 내 앱(Android) → 다운로드. |
| `app/lib/firebase_options.dart` | FlutterFire용 `FirebaseOptions`(apiKey/appId/projectId 등) — `google-services.json`과 같은 값을 Dart 코드로 노출하므로 동일하게 로컬 전용 취급 | 위 `flutterfire configure` 명령 한 번으로 `google-services.json`과 같이 생성됨. **템플릿은 `app/lib/firebase_options.example.dart`(커밋됨)** — 이걸 복사해 쓰면 앱은 빌드되지만 Firebase 초기화가 실패해 로그인이 안 되므로, 개발용은 반드시 위 명령으로 생성할 것 |
| `app/ios/Runner/GoogleService-Info.plist` | Firebase iOS 클라이언트 설정 — iOS release 빌드와 Firebase 초기화에 필요 | Firebase 콘솔 → 프로젝트 설정 → 내 앱(iOS, `com.nomara.modi.app`) → `GoogleService-Info.plist` 다운로드. iOS 릴리스는 Mac 에서 수동으로 돌리므로 CI 주입이 없다 — 로컬에 두면 된다(`docs/ios-release.md`) |
| `app/ios/Flutter/Local.xcconfig` | iOS Kakao URL scheme에 쓰는 `KAKAO_NATIVE_APP_KEY` — 로컬 전용, 커밋 금지 | `cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig` 후 실제 native app key 입력 |
| `app/android/key.properties` | Android **release** 서명 자격증명. ⚠️ **출시 대상이 iOS 뿐이라 지금은 아무도 필요하지 않다** — 안드로이드는 코드만 남아 있고 CI·릴리스 경로가 없다(2026-08-13). 없으면 `build.gradle.kts`가 debug 키로 폴백하므로 `flutter run`은 그대로 된다 | 안드로이드 출시를 되살릴 때 `keytool -genkey`로 키스토어를 만들고 `app/android/key.properties.example`을 복사해 값 채우기 |
| `server/src/main/resources/firebase-service-account.json` | Firebase Admin SDK 서비스 계정 키 — 서버가 이걸로 클라이언트가 보낸 Firebase ID 토큰의 서명을 검증한다 | Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 → "새 비공개 키 생성" |
| `app/env/dev.json` | 앱이 붙을 개발 서버 주소(`API_BASE_URL`). PC의 IP는 개발자·네트워크마다 달라 커밋하지 않는다 | 저장소의 `app/env/dev.example.json`을 복사해 값만 수정 — 아래 "앱 → 개발 서버 주소" 절 참고 |
| `app/env/prod.json` | 운영 `API_BASE_URL`·`KAKAO_NATIVE_APP_KEY`. **두 군데서 쓴다** — ① TestFlight release 빌드(Mac 에서 수동, `docs/ios-release.md`) ② 로컬에서 운영 서버에 붙어 확인할 때(`.vscode/launch.json`의 `app (운영 서버 확인용)` 구성 — 배포 후 크롤링·이미지 등 환경 차이 확인 전용, 상시 개발용 아님). 커밋하지 않는다 | `app/env/prod.example.json`을 복사해 운영 API 주소와 Kakao Native App Key를 입력 |
| `ai/.env` | AI 서버 로컬 실행용 환경변수(`OPENAI_API_KEY`·`INTERNAL_API_KEY`·`LANGSMITH_*` 등) | 저장소의 `ai/.env.example`을 복사해 값 채우기. LangSmith 추적은 아래 "AI 서버 LangSmith 추적" 절 참고 |
| `server/.env` | 서버 로컬 실행용 환경변수(`FIREBASE_CREDENTIALS_PATH`·`MINIO_ENDPOINT`·`OPENAI_API_KEY`·`YOUTUBE_API_KEY`·`SPRING_MAIL_HOST` 등). `build.gradle`이 **`bootRun`에서만** 읽는다 | 저장소의 `server/.env.example`을 복사해 값 채우기 — 아래 "server/ 로컬 환경변수" 절 참고 |

아래 두 개는 개발 PC가 아니라 **배포 서버에만** 두는 파일이다 — 자세한 내용은 "배포" 절 참고.

| 파일 (서버 경로) | 용도 | 준비 방법 |
|---|---|---|
| `/home/ubuntu/maramodi/.env` | 운영 환경변수(DB 비번·`OPENAI_API_KEY`·`YOUTUBE_API_KEY`·`INTERNAL_API_KEY`·`SPRING_MAIL_HOST`/`USERNAME`/`PASSWORD` 등). compose와 `deploy/deploy.sh`가 `--env-file`로 읽는다 | 저장소의 `deploy/.env.example`을 복사해 값 채우기. `chmod 600` |
| `/home/ubuntu/maramodi/secrets/firebase-service-account.json` | 운영 서버의 Firebase Admin SDK 키. Spring 컨테이너가 읽기전용으로 마운트해 간다 | 개발용과 같은 파일(Firebase 콘솔 → 서비스 계정 → 새 비공개 키). `scp`로 올린다 |

### server/ 로컬 환경변수 — `server/.env` 하나로 모은다

서버는 Firebase 키 경로·MinIO 주소·게이트웨이 키를 환경변수로 받는다. 매번 커맨드라인에 나열하지 않고 **`server/.env` 한 파일**에 모아둔다(`ai/.env`·`deploy/.env`와 같은 포맷).

```bash
cd server
cp .env.example .env   # 값 채우기 — 안 쓸 항목은 비워두면 "설정 안 함"과 같다
docker compose up -d   # postgres + redis + minio
./gradlew bootRun      # 이게 전부. build.gradle이 .env를 읽어 넣는다
```

- **`./gradlew test`는 `.env`를 읽지 않는다.** 로더를 `bootRun` 태스크에만 걸어뒀다 — 개발자의 게이트웨이 키가 테스트로 새어들어가 실제 API를 호출해 크레딧을 태우고 "AI 없을 때 폴백" 검증을 무의미하게 만든 사고가 있었기 때문이다(`src/test/resources/application.yml`의 경고 참고). 검증: `.env`에 더미 게이트웨이 키를 넣고 `./gradlew test`를 돌려도 결과가 `.env` 없을 때와 동일한 `70 tests, 8 failed`(전부 아래 Testcontainers 이슈)이고 LLM 호출 흔적이 없다.
- **빈 값은 건너뛴다.** `OPENAI_API_KEY=`를 그대로 두면 "설정 안 함"과 똑같이 동작한다. 빈 문자열을 주입하면 `@ConditionalOnProperty`가 참이 되어 키 없는 빈이 만들어지고, `MINIO_ENDPOINT=`의 경우엔 부팅 자체가 깨진다.
- 값이 없을 때 각각 어떻게 동작하는지는 `server/.env.example`의 주석에 적혀 있다. 요약: Firebase 없으면 `/me` 등이 항상 401, MinIO 없으면 업로드 URL 발급만 503, 게이트웨이 없으면 태그가 빈 상태로 저장, SMTP(`SPRING_MAIL_HOST`) 없으면 이메일 인증코드 발송 API만 503, **`YOUTUBE_API_KEY` 없으면 유튜브 링크만 등록 실패**(다른 사이트는 정상 — 서버 로그에 `error`로 남는다).
- **유튜브는 HTML을 긁지 않고 YouTube Data API v3를 부른다**(2026-08-05). 운영 서버는 데이터센터 IP라 `youtube.com`이 구글 CAPTCHA에 막히기 때문이고(옛 EC2에서 실측했고 오라클도 같은 조건이다), **HTML 폴백은 없다**. 그래서 로컬에서 유튜브 링크를 테스트하려면 `YOUTUBE_API_KEY`가 반드시 필요하다 — 키에 IP 제한을 걸지 않은 이유가 이것이다(발급 절차는 `server/.env.example`).

셸 환경변수를 직접 쓰는 방식도 그대로 동작한다(`.env`의 빈 항목은 건너뛰므로 셸 값이 이긴다):

```bash
FIREBASE_CREDENTIALS_PATH="/path/to/firebase-service-account.json" ./gradlew bootRun
```

**`OPENAI_API_KEY` 값 자체는 이 문서에도 어디에도 기록하지 않는다** — 팀 채널에서 개별 전달받는다(구성 방식은 `specs/0001-architecture.md` "AI 기능 흐름").

**`MINIO_ENDPOINT`에는 `application.yml` 기본값이 없다.** 기본값을 두면 `MinioConfig`의 `@ConditionalOnProperty(minio.endpoint)`가 항상 참이 되어, MinIO가 없는 환경에서 "업로드만 503"이 아니라 **서버 부팅 자체가 깨진다**(2026-07-29 실측: 컨텍스트 초기화 실패 + okhttp 논데몬 스레드가 JVM을 붙잡아 프로세스는 살아 있는데 8080은 안 열리는 좀비 상태). `firebase.credentials-path`와 같은 패턴이다. `minio.access-key`/`secret-key`/`bucket`은 민감정보가 아니라 로컬 고정값(`minioadmin`/`minioadmin`/`modi`)이 기본값으로 있어 채우지 않아도 된다. MinIO 콘솔은 `http://localhost:9001`.

⚠️ **안드로이드 에뮬레이터로 테스트한다면 `MINIO_PUBLIC_BASE_URL=http://10.0.2.2:9000`을 함께 채운다**(2026-08-03). `MINIO_ENDPOINT`는 **서버가 MinIO에 접속하는 주소**이고 이 값은 **기기가 이미지를 받아갈 주소**인데, 로컬에서는 그 둘이 갈린다 — 에뮬레이터에서 `localhost`는 에뮬레이터 자신이라 개발 PC의 MinIO에 못 닿는다(`API_BASE_URL`이 `10.0.2.2:8080`인 것과 같은 이유). 비우면 `MINIO_ENDPOINT`를 그대로 쓰므로 **운영에서는 채울 필요가 없다**. ⚠️ 안 채웠을 때의 증상이 고약하다 — 업로드도 DB 저장도 성공해서 **서버 로그에 아무 흔적이 없고 앱에서 이미지만 안 뜬다.** 프로필 사진·방 대표 이미지·아카이브 썸네일 셋 다 해당한다.

### 앱 → 개발 서버 주소 (`app/env/dev.json`)

앱이 붙을 서버 주소는 **Dart가 실행 시 전달받은 값**을 기준으로 한다. Android 공유 화면은 `app/android/app/build.gradle.kts`가 Flutter의 `--dart-define`을 `BuildConfig.API_BASE_URL`로 전달하고, iOS Share Extension은 메인 앱이 같은 값을 App Group UserDefaults에 동기화한다. 주소를 네이티브 확장에 별도로 하드코딩하지 않는 이유다.

```bash
cd app
cp env/dev.example.json env/dev.json   # 값은 아래 표에서 골라 수정
flutter run --dart-define-from-file=env/dev.json
```

VS Code는 `app (real device)` / `(profile)` / `(release)` 구성이 이 파일을 자동으로 넘긴다. `app (debug)`는 파일 없이 실행돼 기본값(에뮬레이터용)을 쓴다.

| 실행 환경 | `API_BASE_URL` | 사전 준비 |
|---|---|---|
| 안드로이드 에뮬레이터 | `http://10.0.2.2:8080` (기본값 — 파일 없이도 동작) | 없음 |
| 실기기 · 같은 Wi-Fi | `http://<PC의 Wi-Fi IPv4>:8080` | 없음. 주소 확인: `(Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias Wi-Fi).IPAddress` |
| 실기기 · USB | `http://localhost:8080` | `adb reverse tcp:8080 tcp:8080` (USB 다시 꽂을 때마다 재실행) |

- **LAN IP는 Wi-Fi에 재접속하면 바뀐다.** 갑자기 연결이 안 되면 IP부터 다시 확인할 것. `ping`은 Windows 방화벽이 ICMP를 막아 실패하는 게 정상이니 진단 기준으로 쓰지 말고, `adb shell "curl -s http://<IP>:8080/actuator/health"`로 확인한다.
- 평문 HTTP는 **디버그 빌드에서만** 허용된다(`app/android/app/src/debug/res/xml/network_security_config.xml`). release는 차단되므로 배포 주소는 HTTPS여야 한다.
- **release 빌드는 `API_BASE_URL`을 안 넘기면 Gradle이 빌드를 실패시킨다** — 에뮬레이터 기본값이 그대로 배포되는 사고를 막기 위한 것이다. 배포용 값은 별도 파일로 넘긴다:

  ```bash
  flutter build apk --release --dart-define-from-file=env/prod.json
  ```

### AI 서버 LangSmith 추적 (`ai/.env` — 개발 환경 전용)

프롬프트 입력·출력·토큰·소요시간을 [LangSmith](https://smith.langchain.com) 화면에서 보기 위한 것이다. 프롬프트를 깎을 때 "왜 결과가 달라졌나"를 눈으로 확인하는 용도이며, **운영에서는 반드시 꺼야 한다** — 켜면 사용자 자료 본문이 제3자 SaaS로 전송되고, 개인정보 처리위탁 명시와 Play Console 데이터 보안 신고 대상이 된다(`ai/docs/DECISIONS.md`).

1. LangSmith 로그인 → **Settings → API Keys → Create API Key**
   - **Key Type = Personal Access Token** (Service Key는 CI/자동화용인데, 이 프로젝트는 CI에서 추적을 켜지 않는다)
   - Expiration은 기간을 정한다. `Never`는 쓰지 않는다
   - **키는 한 번만 표시된다.** 값은 이 문서에도 어디에도 기록하지 않는다
2. `ai/.env`에 채운다:

   ```bash
   LANGSMITH_TRACING=true
   LANGSMITH_API_KEY=<발급받은 키>
   LANGSMITH_PROJECT=modi-ai      # 생략 가능, 기본값이 modi-ai
   ```

- **`ai/.env`에 값을 적는 것만으로는 켜지지 않는다.** pydantic-settings는 `.env`를 `Settings` 객체에만 채우고 `os.environ`에는 넣지 않는데 LangSmith SDK는 `os.environ`만 본다. `modi_ai/tracing.py`의 `configure_tracing()`이 그 간극을 메우며, 서버 기동 시 자동으로 호출된다.
- **키가 비어 있으면 `LANGSMITH_TRACING=true`여도 켜지 않고 경고 로그만 남긴다** — `INTERNAL_API_KEY`·`OPENAI_API_KEY`와 같은 "키가 없으면 그 기능만 비활성" 패턴이다.
- 추적이 켜지면 기동 로그에 `LangSmith 추적 켜짐 (project=...)` 경고가 한 줄 남는다. 운영 로그에서 이 줄이 보이면 즉시 끌 것.

### Google 로그인 SHA-1 지문 등록 (팀원마다 1회 — 파일 복사만으론 안 된다)

위 파일들을 제자리에 넣어도 **Google 로그인은 실패한다.** Android의 Google 로그인은 앱이 제시하는 `(패키지명, 앱 서명 인증서 SHA-1)` 조합을 Firebase에 등록된 값과 대조하는데, debug keystore(`~/.android/debug.keystore`, Windows는 `%USERPROFILE%\.android\debug.keystore`)는 **Android SDK가 개발 머신마다 새로 생성**하므로 지문이 사람마다 다르다. 즉 남의 `google-services.json`에는 그 사람의 지문만 들어 있어서, 몇 번을 다시 복사해도 내 PC에서는 안 된다.

**증상**: 로그인 시도 시 `ApiException: 10`(`DEVELOPER_ERROR`). `flutter run` 콘솔이나 `adb logcat`에서 확인된다. 이 번호가 맞으면 원인은 지문 미등록으로 확정이다(다른 번호면 원인이 다르다).

1. 내 debug 지문 확인 — 출력에서 `Variant: debug`의 `SHA1:` 값:

   ```bash
   cd app/android && ./gradlew signingReport     # Windows: .\gradlew.bat signingReport
   ```

2. Firebase 콘솔 → 프로젝트 설정 → 내 앱 → Android(`com.nomara.modi.app`) → **디지털 지문 추가**에 붙여넣는다. **기존 지문은 지우지 않는다** — 팀원 수만큼 누적 등록하는 게 정상이다.

3. `google-services.json`을 **다시 생성**한다. 2단계만 하면 로컬 파일에는 옛 지문이 그대로라 계속 실패한다:

   ```bash
   cd app && flutterfire configure -p modi-mara --platforms=android -a com.nomara.modi.app -y
   ```

4. 완전 재빌드. `google-services.json`은 빌드 타임에 APK로 구워지므로 핫 리로드로는 반영되지 않는다:

   ```bash
   cd app && flutter clean && flutter run
   ```

> 새 팀원이 합류할 때마다 1~4를 반복한다. release 빌드용·스토어 배포용(Play App Signing) 지문은 debug와 별개로 추가 등록이 필요하며, 실제 배포를 시작하는 시점에 처리한다.

## 시연 모드 — 검수 노드 끄기 (임시, 반드시 되돌린다)

> 시연 요구: **한 번에 후보 6~8개 · 10초 이내.** 재본 결과 그 둘을 동시에 만족시키는 유일한
> 레버가 검수 노드였다.

```bash
# 서버에서 (ssh modi)
vi /home/ubuntu/maramodi/.env      # CRITIQUE_MAX_ATTEMPTS=0 추가
cd <repo>/deploy && ./deploy.sh    # 컨테이너 재기동
```

운영 방(자료 46건) 앱 실측:

| 값 | 후보 수 | 응답시간 | 부작용 |
|---|---|---|---|
| `1`(기본·운영) | 1~3개 | 10~13초 | — |
| `0`(시연) | 7~8개 | 5~9초 | `일정 짜기` 같은 **바로 실행 못 하는 후보**가 8개 중 1~2개 |

🔴 **시연이 끝나면 그 줄을 지우고 다시 배포한다.** 안 되돌리면 추천 품질이 조용히 나빠지고,
증상이 "가끔 이상한 후보가 섞인다"라서 아무도 원인을 못 찾는다.

관련 값 하나 더 — `TODO_SUGGESTION_EXCLUDE_RECENT`(기본 `false`)는 **임시가 아니라 확정**이다.
이미 보여준 후보를 다시 제외하지 않는다(반복 추천 허용). 되돌리려면 `true`.

## CI/CD

- 저장소는 **GitHub**, CI/CD 는 **GitHub Actions** — 워크플로 한 파일이다: `.github/workflows/ci.yml`.
- `app/**`·`server/**`·`ai/**` 중 **바뀐 쪽만** 해당 잡이 돈다(`dorny/paths-filter`).
- **`dev` 에 push 되면 자동으로 `api.maramodi.cloud` 에 배포된다.** `master` 는 배포하지 않는다.

### 왜 워크플로를 파일 하나로 뒀나

Jenkins 는 한 파이프라인의 스테이지라서 "테스트가 통과해야 배포가 돈다"가 공짜였다. 워크플로를
파일로 쪼개면 그 게이팅이 사라진다 — deploy 워크플로가 테스트 결과를 모른 채 push 만 보고
배포한다. `workflow_run` 으로 묶는 방법도 있지만 **경로 필터로 스킵된 워크플로는 애초에 실행되지
않아 트리거가 오지 않는다.** 그래서 잡을 한 파일에 두고 `needs` 로 묶었다.

| 잡 | 하는 일 |
|---|---|
| `changes` | 경로 필터. 아래 세 잡을 켜고 끈다 |
| `app` | Flutter **3.44.7** · `firebase_options` 템플릿 복사 · `dart format --set-exit-if-changed` · `analyze` · `test` |
| `server` | JDK 21 · `./gradlew build`(Testcontainers 로 Postgres·Redis 를 띄운다) · **OpenAPI 드리프트 검사** |
| `ai` | uv **0.11.26** · `uv sync --frozen` · `ruff format --check` · `ruff check` · `pytest` |
| `deploy` | `dev` push 일 때만. SSH → 서버에서 `git reset --hard origin/dev && ./deploy/deploy.sh` |

### deploy 잡의 `if` 를 건드리지 말 것

```yaml
if: always() && !failure() && !cancelled() && github.ref == 'refs/heads/dev' && github.event_name == 'push'
```

`always()` 가 필요한 이유: 경로 필터로 **스킵된 잡의 결과는 `skipped`** 인데, `needs` 의 기본
동작은 "의존 잡이 스킵되면 이쪽도 스킵"이다. 그대로 두면 **문서만 고친 커밋이 영영 배포되지
않는다.** 막고 싶은 것은 실패했을 때뿐이라 `!failure()` 로 좁혔다.

### 빌드는 러너가 아니라 서버에서 한다

운영 서버가 **ARM(aarch64)** 이라 x86_64 러너에서 만든 이미지는 거기서 뜨지 않는다. 그래서
`deploy` 잡은 소스를 서버로 보내기만 하고 `docker compose build` 는 서버에서 돈다.

### 소스는 러너가 서버로 rsync 한다 (서버는 GitHub 을 읽지 않는다)

**서버에 GitHub 자격증명이 하나도 없다.** 예전에는 서버가 GitHub 에서 직접 `git fetch` 했고
그러려면 읽기 전용 **deploy key** 가 필요했는데, 이 오가니제이션은 **정책으로 deploy key 를
금지**한다("Disabled by modintps", 2026-08-13 확인). 정책을 풀 수도 있었지만 방향을 뒤집는 쪽을
골랐다 — 러너는 이미 소스를 체크아웃했고 이미 서버 SSH 접근이 있으므로, 러너가 밀어 넣으면
자격증명이 **하나 줄어든다**("서버가 이 저장소를 상시 읽을 수 있는 상태"가 사라진다).

```sh
rsync -az --delete -e 'ssh -o StrictHostKeyChecking=yes' ./ ubuntu@<IP>:maramodi/repo/
ssh ubuntu@<IP> 'cd ~/maramodi/repo && ./deploy/deploy.sh'
```

- `--delete` — 저장소에서 지워진 파일이 서버에 남지 않는다. 운영 `.env` 와
  `active-upstream.conf` 는 **저장소 밖**(`~/maramodi/`)이라 안 건드린다.
- `-a` 가 **mtime 을 보존하는 것이 중요하다.** 안 그러면 매 배포마다 Docker 빌드 캐시가 전부
  무효화돼 ARM 4코어에서 빌드가 몇 분씩 길어진다.
- `.git` 도 함께 보낸다(checkout 이 shallow 라 작다). `deploy.sh` 가 배포 대상 커밋을 찍는 데
  쓰고, 서버에서 `git log`·`git status` 가 된다.

🔴 **대가: 서버에서 `git pull` 로 최신 코드를 받을 수 없다.** 사람이 최신 코드로 배포하려면
**Actions → CI → Run workflow**(`workflow_dispatch`)를 쓴다. 서버에 이미 있는 코드로 다시
배포하는 것은 `./deploy/deploy.sh` 만 돌리면 된다.

### 필요한 GitHub Secrets

| 이름 | 값 |
|---|---|
| `SSH_PRIVATE_KEY` | **배포 전용** 키의 비밀키. 개인 키(`~/.ssh/oracle`)를 넣지 않는다 |
| `SSH_HOST` / `SSH_USER` | 서버 공인 IP / `ubuntu` |
| `SSH_KNOWN_HOSTS` | 서버 호스트 키. `StrictHostKeyChecking=no` 로 열어두지 않는다 |

`SSH_KNOWN_HOSTS` 는 `ssh-keyscan` 대신 **서버에서 직접** 꺼내는 것이 맞다 — keyscan 은 중간자가
준 키를 그대로 믿는다:

```sh
# 서버에서
awk '{print "<IP> " $1 " " $2}' /etc/ssh/ssh_host_ed25519_key.pub
```

**서버 쪽 1회 설정** — 배포 전용 키를 새로 만들어 인가한다(개인 키를 시크릿에 넣지 않는다):

```sh
ssh modi
ssh-keygen -t ed25519 -f ~/.ssh/github_actions_deploy -N '' -C 'github-actions-deploy'
printf '\n' >> ~/.ssh/authorized_keys
cat ~/.ssh/github_actions_deploy.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
cat ~/.ssh/github_actions_deploy      # 이 전체(BEGIN~END)를 SSH_PRIVATE_KEY 에 넣는다
```

⚠️ `authorized_keys` 앞에 개행을 먼저 넣는 이유: 기존 파일이 개행으로 끝나지 않으면 append 가
**마지막 키를 망가뜨려** 서버에서 잠길 수 있다.

### 테스트를 강제로 전부 돌리기

Actions → **CI** → Run workflow → `force_all` 체크. 경로 필터를 무시하고 세 잡을 다 돌린다
(옛 Jenkinsfile 의 `FORCE_ALL` 파라미터를 그대로 옮긴 것이다).

### 옮기지 않은 것

- **Shorebird OTA 코드푸시 — 제거했다**(2026-08-13). 자동화 스테이지가 **안드로이드 전용**이었고
  iOS 는 원래 사람이 macOS 에서 수동으로 돌리는 절차뿐이었다. iOS 전용으로 좁히면서 자동화가
  0이 되므로 스크립트·CI 이미지·문서를 전부 걷어냈다. 다시 필요해지면 백업 히스토리
  (`modi-history-backup.git`)의 `scripts/shorebird-*`·`deploy/ci/shorebird/` 를 참고한다.
- **iOS TestFlight — 자동화하지 않았다.** 프라이빗 저장소의 macOS 러너는 분수를 10배로 소모하고,
  팀 Apple Developer 계정이 아직 없어 돌려볼 수도 없다. 절차는 [`docs/ios-release.md`](./docs/ios-release.md).
- **Mattermost 알림 — 제거했다.** 웹훅이 더 이상 우리 것이 아니다.

## 배포

### 구성

```
                       인터넷 (+ 사용자 휴대폰)
                              │
              ┌───────────────┴───────────────┐
        api.maramodi.cloud          storage.maramodi.cloud
              └────► Caddy :80/:443 ◄─────────┘   ← 외부에 열린 포트는 이 둘뿐
                            │
   ┌────────────────────────┼──────────────┐
   │  import active-upstream.conf          │
   ▼  (살아있는 색 한 줄)                   ▼              ▼
spring-blue:8080  ┊  spring-green:8080  minio:9000    (완전 내부)
   (한 색만 뜬다) ┊  (멈춘 채 롤백 대기)                 ai:8000
   ├─► postgres:5432
   ├─► redis:6379
   ├─► ai:8000
   └─► minio (presigned URL 발급 · 버킷 생성)
```

| | 파일 | 재시작 시점 |
|---|---|---|
| 인프라 층 | `deploy/docker-compose.infra.yml` (Caddy 하나) | **사람이 수동으로만** |
| 앱 층 | `deploy/docker-compose.app.yml` (spring **두 색**, ai, minio, postgres, redis) | `dev` push 마다 `deploy.sh` 가 |

### 무중단 배포 (blue/green) — 2026-08-13

Spring 은 `spring-blue`·`spring-green` **두 벌**로 정의돼 있고, **평상시 떠 있는 것은 한 색뿐**이다
(다른 색은 stop 상태로 남아 롤백용으로 쓰인다). 배포는:

1. 멈춰 있는 색을 빌드해 띄우고 **healthy 를 기다린다** ← 이 동안 옛 색이 계속 서비스한다
2. **활성 파일**(`~/maramodi/active-upstream.conf`) 한 줄을 새 색으로 바꾸고 `caddy reload`
   ← 여기가 전환 순간. reload 는 진행 중인 연결을 떨구지 않는다
3. 옛 색을 graceful 하게 세운다 (in-flight 요청을 끝내고 죽는다)

1에서 실패하면 **아무것도 전환하지 않고 종료한다** — 옛 색이 그대로 서비스한다.

어느 색이 살아있는지는 `docker ps` 로 바로 보인다.

**무중단이 성립하는 조건이 셋이고, 하나만 빠져도 조용히 깨진다.**
`BlueGreenDeployContractTest`(서버 테스트)가 세 파일을 묶어 검사한다:

| 조건 | 어디 | 빠지면 |
|---|---|---|
| `server.shutdown: graceful` | `application.yml` | 배포마다 그 순간의 요청이 **잘린다.** 클라이언트는 커넥션 끊김만 보고 서버 로그엔 아무것도 안 남는다 |
| `stop_grace_period` > `timeout-per-shutdown-phase` | compose vs `application.yml` | Docker 가 **SIGKILL 을 먼저** 보내 graceful 설정이 있는데도 효과가 없다 |
| 색 이름이 compose·활성 파일·`deploy.sh` 셋에서 같음 | 세 파일 | Caddy 가 upstream 을 못 찾아 **전부 502** |

🔴 **활성 파일은 저장소 밖(`~/maramodi/`)에 있다.** 저장소 안에 두면 배포 잡의
`git reset --hard origin/dev` 가 **매 배포마다 활성 색을 커밋된 값으로 되돌려**, 배포는 성공했다고
보고하면서 트래픽은 방금 세운 옛 색으로 간다.

🔴 **활성 파일은 `printf ... > 파일` 로 제자리 truncate 한다 — `sed -i`·`mv` 를 쓰지 않는다.**
리눅스에서 단일 파일 bind-mount 는 **inode 를 묶는** 것이라, 새 파일을 만들어 갈아치우는 도구를
쓰면 컨테이너가 옛 inode = **옛 내용을 계속 본다**(호스트에서 `cat` 하면 새 내용이라 원인을 짚기
어렵다). 운영 호스트가 리눅스라 이 규칙을 지킨다.

> ⚠️ **로컬(Docker Desktop for Windows/macOS)에서는 이 함정이 재현되지 않는다** — 파일 공유가
> inode 가 아니라 **경로**로 동작해서 `sed -i` 후에도 컨테이너가 새 내용을 본다(2026-08-13 실측:
> 호스트 inode 는 바뀌었는데 컨테이너는 새 내용을 봤다). 로컬에서 "괜찮네"를 확인하고 이 규칙을
> 지우면 운영에서만 터진다.

**AI 서버는 아직 blue/green 이 아니다.** 배포 중 몇 초 끊긴다 — 태깅·요약은 폴백이 있어 조용히
스킵되지만 **투두 추천은 사용자에게 실패로 보인다.**

**천장**: 단일 호스트다. 커널 업데이트·재부팅·클라우드 유지보수는 그대로 끊긴다. 이것은
"무중단 **배포**"이고 "무중단 **서비스**"가 아니다.

### 🔴 스키마 변경 규칙 (Flyway) — blue/green 의 진짜 제약

새 색이 **마이그레이션을 먼저 돌리고**, 그 뒤에도 옛 색이 몇십 초 트래픽을 받는다.
즉 그 구간에는 **옛 코드가 새 스키마 위에서 돈다.**

**파괴적 변경은 배포 두 번으로 쪼갠다** (V30 부터 적용):

| 하고 싶은 것 | 하지 말 것 | 대신 |
|---|---|---|
| 컬럼 삭제 | `DROP COLUMN` 을 코드 변경과 같은 배포에 | ① 코드에서 그 컬럼을 안 읽게 만들어 배포 → ② **다음 배포**에서 `DROP COLUMN` |
| 컬럼 이름 변경 | `RENAME COLUMN` | ① 새 컬럼 추가 + 양쪽 쓰기 → ② 읽기를 새 컬럼으로 → ③ 옛 컬럼 삭제 |
| `NOT NULL` 추가 | 기본값 없이 바로 | ① nullable 로 추가 + 백필 → ② `SET NOT NULL` |

⚠️ **롤백해도 마이그레이션은 되돌아오지 않는다.** DB 는 하나이고 진짜 blue/green(DB 분리)이 아니라
롤링이다. 옛 색을 되살려도 스키마는 새 것이다 — 그래서 위 규칙이 롤백 가능성의 전제다.

#### 🔴 이미 적용된 마이그레이션 파일은 **주석 한 글자도** 고치지 않는다

Flyway 는 파일 내용의 체크섬을 DB 의 이력 테이블과 비교하고, 다르면 `Validate failed` 로
**컨텍스트를 못 띄운다** — 기능이 하나 죽는 게 아니라 **부팅 자체가 안 된다.**

**2026-08-13 운영에서 실제로 그렇게 멈췄다.** 조직 흔적 제거 작업이 `V5`·`V6`·`V7`·`V10` 의
첫 주석 줄에서 **티켓 번호만** 지웠다(파일 크기 16·16·16·15바이트 감소, DDL 은 한 글자도 안 바뀜).
그런데 배포가 이렇게 죽었다:

```
Validate failed: Migration checksum mismatch for migration version 5
-> Applied to database : 1863795280
-> Resolved locally    : -26747768
```

**그 시점에 서버 테스트 774개가 전부 통과했다.** 이 계약은 저장소 파일과 **운영 DB** 사이에 있어서
단위·통합 테스트가 잡을 수 없다 — H2/Testcontainers 는 매번 빈 DB 로 시작하므로 마이그레이션이
그냥 처음부터 다시 적용되고 통과한다. 그래서 **"과거 파일이 바뀌었다"는 사실 자체**를 잡는
가드를 뒀다: `FlywayMigrationImmutabilityTest` + 커밋된 지문 목록
(`server/src/test/resources/db/migration-checksums.txt`).

**바꿔야 할 게 있으면 새 `V<다음번호>` 파일로 만든다.** 새 마이그레이션을 추가했으면:

```sh
./scripts/regen-migration-checksums.sh
```

되돌릴 수 없는 이유로 과거 파일을 정말 고쳤다면 **두 가지를 함께** 해야 한다:

1. **모든 환경 DB 에서 repair** — 이력 테이블의 checksum 을 새 값으로 교정. 안 하면 그 DB 는
   다음 배포에서 부팅이 깨진다. 운영에서 한 방법(Flyway 가 로그에 찍어 준 `Resolved locally` 값을 넣는다):
   ```sh
   docker exec maramodi-postgres pg_dump -U modi -d modi -t flyway_schema_history \
       > ~/maramodi/flyway_schema_history.bak.$(date +%Y%m%d).sql      # 먼저 백업
   docker exec maramodi-postgres psql -U modi -d modi \
       -c "UPDATE flyway_schema_history SET checksum = <Resolved locally> WHERE version = '<N>';"
   ```
2. `./scripts/regen-migration-checksums.sh` 로 지문 목록 갱신

두 층은 `maramodi-edge` external 네트워크로 연결된다. **층을 나눈 이유**: Caddy 가 발급받은
TLS 인증서를 볼륨에 들고 있어 앱 배포마다 흔들 이유가 없다.
(2026-08-13 까지는 인프라 층에 Jenkins 도 있었고, 그때의 이유는 "자기 자신이 든 compose 를
`up -d` 하면 배포 도중 스스로 죽는다"였다. CI 가 서버 밖으로 나가 그 제약은 사라졌다.)

TLS는 Caddy가 Let's Encrypt에서 자동 발급·자동 갱신한다(certbot 크론 없음). `postgres`/`redis`/`ai`는 호스트 포트를 바인딩하지 않아 보안 리스트를 잘못 열어도 인터넷에 노출되지 않는다.

`api.maramodi.cloud`에서 **Actuator(`/actuator/*`)는 404로 차단**하고, **Swagger/OpenAPI 문서는 Basic 인증**으로 감싼다(아래).

### Swagger/OpenAPI 문서는 Basic 인증 뒤에 있다

엔드포인트 46개는 전부 `FirebaseAuthFilter` 뒤에 있어서 문서가 열려도 그것만으로 무단 접근이 되는 건 아니다. 그래도 공격자에게 엔드포인트·파라미터명·스키마 전체를 공짜로 주는 셈이고, swagger-ui 자체도 과거 XSS CVE가 있었다. 도메인은 이미 봇에게 스캔되고 있다(Caddy 로그에서 확인).

**보호 경로가 셋이라는 점이 중요하다** — `/docs`는 진입점일 뿐이고 실제 UI는 다른 경로에 있다:

```
/docs                        → 302 로 /swagger-ui/index.html 로 보낸다 (진입점)
/swagger-ui/*                → 실제 UI·자산.  ★ 이걸 빼면 문서가 그대로 열린다
/v3/api-docs, /v3/api-docs/* → 전체 API 스키마 본문 (가장 민감)
```

비밀번호 설정 (서버에서):

```bash
docker run --rm caddy:2-alpine caddy hash-password --plaintext '실제비밀번호'
# 출력된 해시를 ~/maramodi/.env 의 DOCS_PASSWORD_HASH 에 넣는다 (DOCS_USER 기본값 modi)
cd ~/maramodi/repo && docker compose -f deploy/docker-compose.infra.yml --env-file ~/maramodi/.env up -d
```

평문 비밀번호는 저장소에도 `.env`에도 두지 않는다(해시만 `.env`에). 팀에는 채널로 전달한다.

- **값이 비면 fail-closed** — Caddy는 정상 기동하고 그 경로만 401이 된다. 실측: 자격증명 없음 / 빈 유저:빈 비번 / 아무 값 모두 401.
- **앱이 쓰는 API는 영향 없다.** 실측: `/rooms`·`/me`·`/rooms/1/todos`·`/invite-codes/*`·`/me/fcm-token` 모두 통과.
- Swagger UI의 "Try it out"은 Bearer 토큰을 쓰므로 그대로 동작할 것으로 보지만 브라우저로는 미검증이다.

### 로그 회전

Docker 기본 `json-file` 드라이버는 크기 제한이 없어 방치하면 디스크를 채운다. compose에 회전을 걸어뒀다.

| 서비스 | 설정 | 이유 |
|---|---|---|
| `caddy` | 50m × 3 | 요청 하나당 JSON 한 줄(2KB 내외). 봇 스캔까지 있어 가장 빨리 쌓인다 |
| `ai`·`minio`·`postgres`·`redis` | 10m × 3 | 장애 추적에 이력이 길게 필요하지 않다 |
| **`spring`** | **없음 (의도적)** | 애플리케이션 로그는 장애 원인 추적에 쓰므로 이력을 자르지 않는다 |

`spring`은 무한히 쌓이므로 `docker system df`로 가끔 확인할 것.

**액세스 로그(어떤 IP가 무엇을 호출했는지)는 Caddy가 이미 남긴다.** Spring에 Tomcat 액세스 로그를 따로 붙이지 않는 이유: 중복이고, 요청 추적이 필요해지면 로그 줄이 아니라 텔레메트리(OpenTelemetry 등)를 붙이는 쪽이 맞다.

### MinIO가 왜 인터넷에 노출되는가

`postgres`/`redis`와 달리 MinIO는 숨길 수 없다. 앱이 서버에서 받은 **presigned PUT URL로 MinIO에 직접 업로드**하고, 아바타도 `https://storage.maramodi.cloud/modi/profile/...` 고정 URL로 직접 받아간다(서버가 바이트를 중계하지 않는다). 대신 이렇게 좁혀뒀다:

- 쓰기는 **presigned PUT으로만** 가능하다(만료 있는 서명 URL).
- 익명 읽기는 **`profile/` 접두사만** 허용된다. 검증 결과: `/modi/profile/...` → `404`(정책 통과, 키 없음), `/modi/other/...` → `403`(차단). 정책은 `MinioConfig`가 기동할 때 자동으로 건다.
- **관리 콘솔(9001)은 인터넷에 열지 않는다.** `Caddyfile`에 블록이 없다. 필요하면 SSH 터널로 본다:

  ```bash
  ssh -L 9001:localhost:9001 modi \
      'docker run --rm --network maramodi-app_internal -p 9001:9001 alpine/socat tcp-listen:9001,fork tcp:minio:9001'
  ```

  더 간단하게는 서버에서 `docker exec maramodi-minio mc ...`로 직접 다루면 된다.

**Spring이 MinIO를 부르는 주소가 왜 `http://minio:9000`이 아닌가**: `MinioClient`는 자기 endpoint로 presigned URL을 만든다. 내부 주소를 주면 앱이 열 수 없는 URL이 나오므로 공개 도메인을 줘야 한다. 그런데 **인스턴스 안에서 자기 공인 IP로는 접속이 안 되므로**(EC2 시절 실측 — 클라우드가 인스턴스의 자기 공인 IP 헤어핀을 지원하지 않는다), Caddy 컨테이너에 `storage.maramodi.cloud` 네트워크 별칭을 달아 Docker 내부 DNS가 Caddy를 직접 가리키게 했다. ⚠️ **오라클에서도 이 별칭이 필요한지는 아직 확인하지 않았다** — DNS 전환 때 검증할 항목이다. 트래픽이 인터넷을 나가지 않고 SNI도 맞아 정상 인증서가 나온다. Caddy는 `reverse_proxy`가 원본 Host를 보존하므로 presigned URL의 SigV4 서명도 깨지지 않는다(nginx와 다른 점).

### 최초 구축 (1회)

**1. 오라클 보안 리스트 인그레스**(VCN → 서브넷 → Security Lists) — `22`(SSH), `80`, `443`만 연다.
`8080`/`5432`/`6379`는 **열지 않는다**. `80`은 Let's Encrypt HTTP-01 챌린지에 필요해서 닫으면
인증서 발급이 실패한다.

> ⚠️ **오라클은 인스턴스 안의 iptables 도 함께 막는다.** 보안 리스트만 열고 끝내면 안 되고,
> 우분투 이미지의 기본 `iptables` 규칙에 해당 포트를 허용해 `netfilter-persistent save` 해야 한다.

**2. DNS A레코드** (가비아) — 둘 다 서버 공인 IP로.

```
api.maramodi.cloud       A    <서버 공인 IP>
storage.maramodi.cloud   A    <서버 공인 IP>     ← MinIO. 없으면 프로필 사진 업로드가 안 된다
```

> `jenkins.maramodi.cloud` 레코드는 **지운다**(2026-08-13). Jenkins 가 없어졌고, 레코드만 남으면
> Caddy 가 그 호스트에 인증서를 발급하려다 실패한다.
>
> 전환할 때는 **하루 전에 TTL 을 300 으로 낮춰** 둔다. 그리고 `~/maramodi/.env` 의
> `MINIO_ENDPOINT` 가 공개 도메인(`https://storage.maramodi.cloud`)인지 확인한다 — 내부 주소
> (`http://minio:9000`)로 두면 앱이 열 수 없는 presigned URL 이 나간다.

**3. 시크릿 배치**

`~/.ssh/config` 에 별칭을 두고 쓴다(공인 IP 를 직접 치지 않는다 — 아래 "주의사항" 참고):

```bash
ssh modi
mkdir -p ~/maramodi/secrets
```

로컬에서:

```bash
scp deploy/.env.example modi:/home/ubuntu/maramodi/.env
scp server/src/main/resources/firebase-service-account.json \
    modi:/home/ubuntu/maramodi/secrets/
# 🔴 무중단 배포의 활성 색 파일. **이걸 안 올리면 Caddy 가 기동하지 않는다**(아래 4번 참고)
scp deploy/active-upstream.conf.example modi:/home/ubuntu/maramodi/active-upstream.conf
```

서버에서 값을 채운다:

```bash
chmod 600 ~/maramodi/.env && vi ~/maramodi/.env
```

**4. 인프라 층 기동**

🔴 **`~/maramodi/active-upstream.conf` 가 먼저 있어야 한다.** Caddyfile 이 그 파일을
`import` 하는데, 호스트에 없으면 Docker 가 그 경로에 **디렉터리를 만들고** Caddy 는 import 에
실패해 **기동하지 않는다**(= 사이트 전체 다운). 그래서 올리기 전에 검증한다:

```bash
git clone <저장소 URL> ~/maramodi/repo && cd ~/maramodi/repo

# Caddyfile + 활성 파일을 한 디렉터리에 모아 검증한다(import 를 포함해 본다)
mkdir -p /tmp/caddycheck && cp deploy/Caddyfile ~/maramodi/active-upstream.conf /tmp/caddycheck/
docker run --rm -v /tmp/caddycheck:/etc/caddy caddy:2-alpine \
    caddy validate --config /etc/caddy/Caddyfile        # → Valid configuration

docker network create maramodi-edge
docker compose -f deploy/docker-compose.infra.yml --env-file ~/maramodi/.env up -d --build
```

인증서 발급 확인 (`docker logs maramodi-caddy`에 `certificate obtained successfully`가 떠야 한다):

```bash
curl -I https://api.maramodi.cloud
```

**5. 앱 층 첫 배포**

```bash
cd ~/maramodi/repo && ./deploy/deploy.sh
```

**6. GitHub Actions 배선** — 자격증명은 **한 방향뿐이다**(GitHub → 서버).

**배포 전용** SSH 키를 새로 만들어 공개키를 서버 `~/.ssh/authorized_keys` 에 넣고, 비밀키를
`SSH_PRIVATE_KEY` 시크릿으로 등록한다. 개인 키를 시크릿에 넣지 않는다. 절차는 위
"CI/CD → 필요한 GitHub Secrets" 절.

**서버 → GitHub 방향은 없다.** 소스는 러너가 rsync 로 밀어 넣으므로 서버에 GitHub 자격증명이
필요하지 않다(위 "소스는 러너가 서버로 rsync 한다" 절 — deploy key 는 org 정책으로 금지돼 있다).

`ssh-keyscan <서버 공인 IP>` 결과를 `SSH_KNOWN_HOSTS` 로 넣어 호스트 키를 고정한다.

### 일상 운영

PR을 `dev`에 머지하면 끝이다. GitHub Actions 가 테스트 → SSH → 서버에서 이미지 빌드 → 컨테이너 교체 → 헬스체크까지 하고, 헬스체크가 240초 안에 통과하지 않으면 컨테이너 로그를 찍고 실패시킨다.

> 🔴 **새 환경변수를 추가한 PR은 머지 전에 서버 `.env`를 먼저 채운다.** `deploy/.env.example`을 고쳐도 서버의 `/home/ubuntu/maramodi/.env`는 **이미 존재하는 파일이라 덮이지 않고**, `deploy.sh`도 파일 존재만 확인할 뿐 필수 변수를 검증하지 않는다. 즉 머지하고 배포해도 **그 기능만 조용히 죽은 채로 뜬다**. 순서: ① 서버 `.env`에 값 추가(`nano ~/maramodi/.env` — `echo`로 붙이면 셸 히스토리에 값이 남는다) ② `docker-compose.app.yml`에 해당 서비스로 통과시키는 줄이 있는지 확인 ③ 머지. 배포 후 살아있는 색의 로그로 해당 기능의 경고가 없는지 본다: `docker logs "$(docker ps --filter name=maramodi-spring- --format '{{.Names}}')"`. ⚠️ **두 색 모두에 통과 줄이 있어야 한다** — `docker-compose.app.yml` 은 `x-spring` 앵커 하나로 정의하므로 거기에 넣으면 두 색이 함께 받는다. 색 블록에 직접 넣으면 다음 배포에서 색이 바뀔 때 그 기능이 조용히 꺼진다.

```bash
# 서버에 이미 있는 코드로 다시 배포 (자동 배포와 완전히 같은 스크립트다)
cd ~/maramodi/repo && ./deploy/deploy.sh
# ⚠️ `git pull` 은 안 된다 — 서버에 GitHub 자격증명이 없다(위 rsync 절 참고).
#    최신 코드로 배포하려면 Actions → CI → Run workflow 를 쓴다.

# 지금 살아있는 색 확인 (뜬 색이 하나뿐이라 바로 보인다)
docker ps --filter name=maramodi-spring- --format '{{.Names}}\t{{.Status}}'
cat ~/maramodi/active-upstream.conf          # Caddy 가 보고 있는 색

# 상태·로그
docker compose -f deploy/docker-compose.app.yml --env-file ~/maramodi/.env ps
docker logs -f "$(docker ps --filter name=maramodi-spring- --format '{{.Names}}')"
docker logs -f maramodi-caddy

# DB 접속
docker exec -it maramodi-postgres psql -U modi -d modi
```

**롤백 (10초)** — 옛 색 컨테이너가 stop 상태로 남아 있으므로 **재빌드도, 이미지 교체도 필요 없다.**
`spring-blue` 로 되돌리는 예:

```bash
docker start maramodi-spring-blue                                   # 이미 떠 있으면 생략
printf 'reverse_proxy spring-blue:8080\n' > ~/maramodi/active-upstream.conf
docker exec maramodi-caddy caddy reload --config /etc/caddy/Caddyfile
```

`printf > 파일` 이어야 한다 — 리눅스에서 `sed -i`·`mv` 는 inode 를 바꿔 **Caddy 가 옛 내용을 계속 본다**(위 "무중단 배포" 절의 실측 주석 참고).

⚠️ **롤백해도 Flyway 마이그레이션은 되돌아오지 않는다** (위 "스키마 변경 규칙").

두 색이 다 깨진 경우의 두 번째 그물 — `deploy.sh` 가 배포 전 이미지를 `:previous` 로 남겨 둔다:

```bash
docker tag maramodi-spring:previous maramodi-spring:latest
docker tag maramodi-ai:previous maramodi-ai:latest
docker compose -f deploy/docker-compose.app.yml --env-file ~/maramodi/.env up -d spring-blue ai
```

### 주의사항

- **`docker compose down -v`를 절대 쓰지 않는다.** `postgres-data`에 도메인 데이터 전부, `minio-data`에 업로드된 프로필 사진 전부가 들어 있다.
- **`Caddyfile`이나 `docker-compose.infra.yml`을 바꿨을 때는 배포가 반영해주지 않는다.** 배포는 앱 층만 건드린다. 서버에서 직접 `cd ~/maramodi/repo && git pull` 후 인프라 compose를 다시 `up -d --build` 해야 한다.
- **접속은 `ssh modi` 별칭으로 한다.** `~/.ssh/config` 의 `Host modi` 가 키와 주소를 함께 들고 있다. 공인 IP 로 직접 붙으면 키가 안 붙어 실패하고, 표준 포트만 허용하는 네트워크에서는 공인 IP:22 자체가 막힐 수 있다(그때는 Tailscale 경유가 유일한 경로다).
- **인스턴스를 중지하지 않는다.** 공인 IP 가 **ephemeral 이면 중지/시작 때 바뀌어 DNS 두 개가 동시에 깨진다.** Reserved public IP 로 승격했는지 확인해 둘 것(오라클 콘솔 → 인스턴스 → 연결된 VNIC → IPv4 주소).
- **A1 인스턴스를 지우지 않는다.** Ampere A1 용량은 리전에 따라 오래 잡히지 않는다 — 한 번 놓으면 며칠씩 `Out of capacity` 가 날 수 있다.
- **두 번째 A1 인스턴스를 만들면 즉시 과금된다.** 무료 한도는 인스턴스 수가 아니라 **월 시간 쿼터**(3,000 OCPU-h / 18,000 GB-h)이고, 지금 구성(4 OCPU/24GB) 한 대가 24시간 돌면 그 쿼터를 거의 다 쓴다.
- **`MINIO_ROOT_PASSWORD`를 나중에 바꾸면 기존 데이터에 접근할 수 없다.** MinIO 루트 계정은 데이터 디렉토리에 묶여 있다. 처음에 제대로 정하고 `.env`를 잃어버리지 말 것.
- 🔴 **`dev` 에 push 할 수 있는 사람 = 서버에서 임의 코드를 돌릴 수 있는 사람이다.** 배포 잡이
  SSH 로 들어와 저장소의 `deploy/deploy.sh` 를 그대로 실행하므로, 그 파일(과 compose)을 바꿀 수
  있으면 서버에서 무엇이든 돌릴 수 있다. 그래서:
  - `dev` 브랜치 보호를 켜 두고 직접 push 대신 PR 로 받는다.
  - 저장소에 외부인을 초대하지 않는다. 저장소는 **프라이빗**으로 둔다.
  - **CI 를 서버 밖으로 뺀 것 자체가 보안 개선이다** — 예전에는 Jenkins 컨테이너가 호스트
    `docker.sock` 을 들고 있어 잡 하나로 호스트 파일시스템 전체(`.env`·Firebase 키·SSH 키)에
    닿을 수 있었다. 이제 서버에는 그 소켓을 가진 컨테이너가 없다.
  - `deploy.sh` 가 `.env` 값을 로그에 찍지 않도록 유지할 것 — Actions 로그는 저장소 접근자가 본다.
- `caddy-data` 볼륨을 지우면 인증서를 재발급한다. Let's Encrypt에 도메인당 레이트리밋이 있으니 함부로 지우지 않는다.

## 커밋 전 로컬 게이트

```bash
# app/
dart format --set-exit-if-changed . && flutter analyze && flutter test

# server/
./gradlew build   # spotless/test 포함
```

시크릿 스캔·상세 규칙은 `.claude/hooks/pre-commit.md` 참고.
