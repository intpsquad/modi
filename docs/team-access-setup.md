# MODI 계속 운영 — 계정·접근 설정 안내

> 프로젝트가 끝나면서 인프라를 **우리 것으로** 옮겼습니다. 각자 해야 하는 설정을 정리했습니다.
> 모르는 게 있으면 그냥 물어보세요 — 잘못 누르면 돈이 나가거나 서버가 멈추는 항목이 섞여 있어서,
> **"절대 하지 말 것"만 먼저 읽어주세요.**

**담당**: 인프라·배포·AI 서버 = 김주우 / 프론트 = 윤주하·김예원 / 백엔드 = 박민영

---

## 0. 지금 상황 한 장 요약

| | 전 | 후 |
|---|---|---|
| 서버 | 부트캠프 EC2 (회수됨) | **오라클 클라우드** ARM 4코어/24GB (도쿄) |
| 저장소 | GitLab | **GitHub (프라이빗)** |
| CI/CD | Jenkins | **GitHub Actions** |
| AI | 부트캠프 게이트웨이 (키 회수됨) | **OpenAI 직접** (팀 계정 결제) |
| 출시 | Android + iOS | **iOS 전용** |

서버는 이미 오라클에서 돌고 있습니다. **남은 건 도메인(DNS)을 새 서버로 돌리는 것뿐**이고,
그때까지는 앱이 아직 옛 서버를 바라봅니다.

---

## 🔴 절대 하지 말 것

오라클 콘솔에 들어가면 보이는 것들입니다. 하나라도 하면 복구가 어렵거나 돈이 나갑니다.

1. **인스턴스를 Terminate(종료)하지 않기.** 이름이 `modi-prod`입니다. ARM(Ampere A1) 용량은
   한 번 놓으면 며칠씩 다시 못 잡습니다 — 실제로 만들 때 `Out of capacity`를 여러 번 겪었습니다.
2. **인스턴스를 Stop(중지)하지 않기.** 공인 IP가 바뀌어서 도메인 두 개가 동시에 죽습니다.
3. **두 번째 인스턴스를 만들지 않기.** 무료 한도는 "인스턴스 개수"가 아니라 **월 사용시간**
   (3,000 OCPU-시간 / 18,000 GB-시간)이고, 지금 서버 한 대가 24시간 돌면 그걸 거의 다 씁니다.
   하나 더 만들면 **그 순간부터 과금**입니다.
4. **부트 볼륨을 지우지 않기.** DB와 업로드된 사진이 전부 그 안에 있습니다.
5. 서버에서 **`docker compose down -v`를 치지 않기.** `-v`가 볼륨을 지웁니다 = 데이터 전체 삭제.

> 그래서 아래 오라클 초대는 **"켜고 끄기는 되지만 만들고 지우기는 안 되는"** 권한으로 드립니다.
> 실수로 3번을 하는 걸 권한으로 막는 겁니다. 새로 만들 일이 생기면 김주우에게 얘기하세요.

---

## 1. 서버 접근 (SSH) — **전원 필요**

일상적으로 실제로 쓰는 건 오라클 콘솔이 아니라 이겁니다. 로그 보기·배포 확인이 여기서 됩니다.

### 1-1. 각자 키를 만들어 **공개키만** 보내주세요

**macOS / Linux:**
```bash
ssh-keygen -t ed25519 -f ~/.ssh/modi -C "이름@기기"    # 예: joowoo@mac
cat ~/.ssh/modi.pub
```

**Windows (PowerShell):**
```powershell
ssh-keygen -t ed25519 -f $HOME\.ssh\modi -C "이름@기기"
Get-Content $HOME\.ssh\modi.pub
```

- 암호구문(passphrase)은 물어보면 그냥 엔터로 비워도 됩니다.
- 출력된 **`ssh-ed25519 AAAA...` 한 줄을 그대로** 보내주세요 (팀 채널 아무 곳이나 괜찮습니다).
- 🔴 **`.pub`이 붙은 것만 보냅니다.** 확장자 없는 `~/.ssh/modi`(비밀키)는 **절대 보내지 마세요.**
  그건 비밀번호와 같습니다.

### 1-2. 등록되면 접속 설정

김주우가 등록했다고 알려주면, `~/.ssh/config`(Windows는 `C:\Users\<사용자>\.ssh\config`)에
아래를 **추가**합니다(파일이 없으면 새로 만듭니다):

```
Host modi
    HostName 193.123.166.89
    User ubuntu
    IdentityFile ~/.ssh/modi
```

접속:
```bash
ssh modi
```

`ubuntu@modi-prod:~$` 프롬프트가 나오면 성공입니다.

### 1-3. 안 되면 (Connection timed out)

**서버가 죽은 게 아닙니다.** 네트워크가 22번 포트를 막는 경우가 있습니다(회사·학교·일부 공용
와이파이). 실제로 부트캠프 네트워크에서 겪었고, `github.com:22`조차 막혀 있었습니다.

이럴 때는 **Tailscale**로 우회합니다 — 막히면 443으로 우회하는 VPN이라 어디서든 붙습니다.

1. 김주우에게 Tailscale 초대를 요청합니다(이메일로 옵니다).
2. [tailscale.com/download](https://tailscale.com/download) 에서 설치 후 로그인.
3. `~/.ssh/config`의 `HostName`을 **`100.91.147.28`** 로 바꿉니다(Tailscale 내부 주소).
4. 다시 `ssh modi`.

> `Connection refused`(거부)와 `Connection timed out`(시간초과)은 다릅니다.
> refused = 서버는 닿았는데 그 포트가 안 열림 / timed out = 패킷이 중간에 막힘 → Tailscale 필요.

### 1-4. 서버에서 자주 쓰는 것

```bash
# 컨테이너 상태 (전부 healthy 여야 정상)
docker ps

# 로그 보기 (Ctrl+C 로 나옴)
# Spring 은 blue/green 두 벌이라 살아있는 색을 찾아서 봅니다(뜬 색은 하나뿐입니다)
docker logs -f "$(docker ps --filter name=maramodi-spring- --format '{{.Names}}')"
docker logs -f maramodi-caddy

# 배포 (보통은 GitHub Actions 가 자동으로 합니다. 손으로 할 때만)
cd ~/maramodi/repo && ./deploy/deploy.sh

# DB 접속
docker exec -it maramodi-postgres psql -U modi -d modi
```

---

## 2. 오라클 클라우드 콘솔 초대 — **필요한 사람만**

인스턴스 상태 확인·재시작·요금 확인이 필요한 사람만 받으면 됩니다. 코드만 만지면 1번(SSH)으로
충분합니다.

### 2-1. 받는 사람이 할 일
초대 메일이 오면 링크를 눌러 비밀번호를 정하고, **MFA(2단계 인증)를 켭니다.**
이 계정으로 서버를 지울 수도 있는 환경이라 MFA는 선택이 아닙니다.

### 2-2. 김주우가 할 일 (관리자 절차)

> 오라클 콘솔은 화면 구성이 자주 바뀝니다. 메뉴 이름이 다르면 검색창에 그 단어를 치면 나옵니다.

1. **사용자 만들기**
   콘솔 → **Identity & Security → Domains** → 도메인(보통 `Default`) → **Users** → *Create user*
   → 이름·이메일 입력. 초대 메일이 발송됩니다.

2. **그룹 만들고 넣기**
   같은 도메인 → **Groups** → *Create group* → 이름 `modi-ops` → 위 사용자들을 추가.

3. **정책(Policy) 주기** — 여기가 핵심입니다
   콘솔 → **Identity & Security → Policies** → 루트 컴파트먼트에서 *Create policy* →
   Statements 를 수동 입력:

   ```
   Allow group modi-ops to read all-resources in tenancy
   Allow group modi-ops to use instance-family in tenancy
   ```

   **왜 `use`이고 `manage`가 아닌가**: `use`는 시작/정지/재부팅까지만 됩니다.
   `manage`를 주면 **인스턴스를 새로 만들거나 지울 수 있게** 되고, 그게 위의
   "절대 하지 말 것 1·3"(용량 상실 / 즉시 과금)입니다. 권한으로 막는 게 안내문보다 확실합니다.

4. **예산 알림 확인**
   콘솔 → **Billing & Cost Management → Budgets** 에 알림이 걸려 있습니다(월 $1 초과 시 메일).
   과금이 시작되면 이게 먼저 알려줍니다. 받는 주소에 팀원 메일을 추가해두면 좋습니다.

### 2-3. Tailscale 초대 (김주우)
Tailscale 관리 콘솔 → **Users → Invite users** → 팀원 이메일. 초대받은 사람이 설치하고
로그인하면 `100.x.x.x` 주소로 서버에 붙을 수 있습니다.

---

## 3. 가비아 (도메인 `maramodi.cloud`)

### 3-0. 먼저 확인해야 하는 것 — **누구 계정인가**
도메인은 부트캠프가 아니라 **우리가 직접 결제한 것**이라 회수되지 않습니다. 다만 **어느 가비아
계정으로 결제했는지가 기록에 없습니다.** 결제한 사람이 누구인지 알려주세요. 이게 안 밝혀지면
DNS를 못 바꾸고, 그러면 앱이 계속 옛 서버(곧 사라짐)를 바라봅니다.

계정을 찾으면 함께 확인할 것:
- **만료일**과 **자동갱신 설정** — 만료되면 도메인을 잃고, 남이 선점할 수 있습니다.
- **소유자/담당자 이메일** — 만료 안내가 그 주소로 갑니다. 살아 있는 주소인지 확인.
- 계정 비밀번호는 공유하지 말고, 관리 담당 한 명을 정하는 편이 낫습니다(가비아는 팀 권한 기능이
  약합니다).

### 3-1. DNS 레코드 변경 (전환 당일)

**My가비아 → 서비스 관리 → 도메인 → 해당 도메인 → DNS 정보 → DNS 관리** 로 들어가면
레코드 표가 나옵니다(메뉴 이름은 조금씩 다를 수 있습니다).

**하루 전에** 먼저 할 것 — 기존 레코드의 **TTL을 `300`(5분)으로 낮춥니다.**
TTL은 "이 주소를 얼마나 캐시해도 되는지"입니다. 기본값(보통 3600 이상)이면 전환 후에도
최대 그 시간만큼 옛 서버로 가는 사람이 남습니다.

**당일** 바꿀 내용:

| 타입 | 호스트 | 값 | 비고 |
|---|---|---|---|
| A | `api` | `193.123.166.89` | 서버 API |
| A | `storage` | `193.123.166.89` | 이미지(MinIO). **없으면 프로필 사진이 안 보입니다** |
| A | `jenkins` | — | 🔴 **레코드 삭제.** Jenkins를 안 씁니다 |

- 가비아는 호스트 칸에 `api`만 넣으면 됩니다(뒤에 `.maramodi.cloud`는 자동으로 붙습니다).
- `jenkins`를 안 지우면, 서버의 Caddy가 그 도메인 인증서를 발급하려다 계속 실패합니다.
- 전환 뒤 확인:
  ```bash
  nslookup api.maramodi.cloud
  curl -I https://api.maramodi.cloud
  ```
  IP가 위 값으로 나오고 HTTP 응답이 오면 끝입니다. 인증서는 Caddy가 자동 발급합니다.
- 전환이 안정되면 TTL을 다시 `3600`으로 올려도 됩니다.

> ⚠️ **전환 순서가 있습니다.** 김주우가 서버 설정 한 줄(`MINIO_ENDPOINT`)을 공개 도메인으로
> 되돌린 뒤에 DNS를 바꿔야 이미지 업로드가 정상 동작합니다. 혼자 진행하지 말고 같이 하세요.

---

## 4. Apple Developer — iOS 출시 준비

**출시 대상을 iOS 하나로 정했습니다.** 안드로이드 코드는 남아 있지만 릴리스 경로가 없습니다.

### 4-1. 지금 급한 것 — 번들 ID가 잠겨 있는지 확인
**옛 Apple Developer 계정에 접근이 남아 있는 사람이 지금 확인해주세요.** 접근이 끊기면 확인
자체가 불가능해지고, 그러면 $99를 결제한 뒤에야 알게 됩니다.

확인할 식별자 **3개** (앱 하나에 번들 ID 하나가 아닙니다):

| 식별자 | 무엇 |
|---|---|
| `com.intpsquad.modi` | 앱 본체 |
| `com.intpsquad.modi.ShareExtension` | 공유 확장(다른 앱에서 "공유"로 저장하는 기능) |
| `group.com.intpsquad.modi` | App Group (앱과 확장이 로그인 정보를 공유하는 통로) |

**순서:**

1. **App Store Connect 먼저** — [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
   → **나의 앱**에 MODI 레코드가 있는지 봅니다.
   - **있으면 → 그 번들 ID는 영구히 못 씁니다.** 앱 레코드를 지워도 Apple이 문자열을 잠급니다.
     새 번들 ID로 가야 합니다(4-2 참고).
   - 없으면 → 2번으로.

2. **Developer 포털** — [developer.apple.com/account](https://developer.apple.com/account)
   → **Certificates, Identifiers & Profiles → Identifiers**
   - 드롭다운 **App IDs**: 위 번들 ID 두 개 검색
   - 드롭다운 **App Groups**: `group.com.intpsquad.modi` 검색
   - 있으면 클릭해서 **켜져 있는 capability를 스크린샷**으로 남겨주세요
     (Push Notifications / Sign in with Apple / App Groups). 새 계정에서 그대로 다시 만듭니다.

3. **판단**
   - App Store Connect 레코드 없음 + 포털에만 등록됨 → 포털에서 지우면 새 계정에서 다시 등록될
     **가능성**이 있습니다(Apple이 보장하지는 않습니다).
   - 아무것도 없음 → 그대로 쓰면 됩니다. 가장 좋은 경우.

### 4-2. 새 번들 ID로 가야 한다면
`cloud.maramodi.app` 을 제안합니다. 역방향 도메인 관례상 **실제로 소유한 도메인**을 써야 하고,
우리가 가진 건 `maramodi.cloud`입니다. App Group은 `group.cloud.maramodi`가 됩니다.
코드·설정 십여 곳과 **Firebase iOS 앱 재등록**이 따라오는데, 그건 김주우가 반영합니다.

### 4-3. 계정 결제
- Apple Developer Program **$99/년** (4명이 나누면 1인당 연 $25 정도)
- 결제 후 **Team ID**(10자)를 알려주세요 — 빌드 설정에 넣어야 합니다.
- 그 전까지 **시뮬레이터 빌드는 정상**이고, 실기기·TestFlight 빌드만 안 됩니다.

---

## 5. Firebase 콘솔 — **프론트 2명 + 백엔드 1명 필요**

로그인(소셜 4종 + 이메일)과 푸시가 전부 Firebase입니다. **콘솔 초대 없이는 앱이 아예 안 뜹니다** —
`firebase_options.dart`가 커밋되지 않는 파일이라 각자 만들어야 하고, 만들려면 프로젝트 권한이
필요합니다.

### 5-1. 초대 (김주우가 함)

Firebase 콘솔 → 프로젝트 `modi-mara` → ⚙️ 프로젝트 설정 → **사용자 및 권한** → 구성원 추가

| 사람 | 역할 | 이유 |
|---|---|---|
| 윤주하 · 김예원 | **편집자** | `flutterfire configure` 가 앱 등록·SHA-1 지문 추가를 하므로 읽기 전용으론 안 됩니다 |
| 박민영 | **편집자** | 서비스 계정 키(Admin SDK) 발급 |

> ⚠️ **소유자를 늘리지 마세요.** 소유자는 프로젝트를 삭제할 수 있고, 지우면 **모든 사용자 계정이
> 사라집니다**(도메인 데이터는 우리 DB에 있지만 로그인 자체가 불가능해집니다).

### 5-2. 프론트(윤주하·김예원)가 받은 뒤 할 일

```bash
cd app
dart pub global activate flutterfire_cli      # 1회
firebase login                                # 초대받은 계정으로
flutterfire configure -p modi-mara --platforms=ios,android -a com.intpsquad.modi -y
```

이 한 줄이 세 파일을 만듭니다 — `lib/firebase_options.dart` · `android/app/google-services.json` ·
`ios/Runner/GoogleService-Info.plist`. **세 개 다 커밋하지 않습니다**(.gitignore가 막고 있습니다).

🔴 **Google 로그인은 이 파일들만으로 안 됩니다.** 각자 PC의 **debug 서명 SHA-1 지문**을 Firebase에
등록해야 합니다(사람마다 키가 달라서, 파일 복사로는 해결이 안 됩니다). 절차는 저장소
`README.md`의 **"Google 로그인 SHA-1 지문 등록"** 절에 있습니다 — **새 팀원마다 1회** 필요합니다.

### 5-3. 백엔드(박민영)가 할 일

콘솔 → ⚙️ 프로젝트 설정 → **서비스 계정** → "새 비공개 키 생성" →
`server/src/main/resources/firebase-service-account.json` 으로 저장.

> 🔴 이 키는 **모든 사용자로 위장할 수 있는 권한**입니다. 커밋·채팅·이메일로 보내지 마세요.
> 서버가 이 키로 앱이 보낸 ID 토큰의 서명을 검증합니다.

---

## 6. 개발 환경 (프론트/백엔드)

저장소가 GitHub으로 옮겨졌으니 remote를 바꿔야 합니다:

```bash
git remote set-url origin <GitHub 저장소 주소>
git fetch origin
```

- 저장소가 **프라이빗**이라 GitHub 계정이 초대돼 있어야 합니다(김주우에게 요청).
- 기본 브랜치는 `dev`입니다. 작업은 브랜치를 따서 **PR**로 올립니다(전엔 MR이라고 불렀던 것).
  - 🔴 **`dev`에 머지되면 그 즉시 운영 서버에 배포됩니다.** 스테이징이 없습니다.
  - PR을 열면 체크리스트가 자동으로 붙습니다(`.github/pull_request_template.md`).
    빈 칸으로 두지 말고, 해당 없으면 취소선 + 한 줄 이유를 남겨주세요.
- **도구 버전을 CI와 맞춰야 합니다.** Flutter `3.44.8` · JDK `21` · uv `0.11.26`.
  Flutter 버전이 다르면 **로컬은 통과하고 CI 만 포맷 검사에서 깨집니다** — `dart format` 출력이
  버전마다 달라서입니다. `cd app && fvm install` 로 `.fvmrc`의 버전을 자동으로 맞출 수 있습니다.
- 로컬에서 각자 준비해야 하는 파일(`.env`·Firebase 설정 등)은 저장소 `README.md`의
  **"로컬 전용 파일"** 절에 목록·발급 방법이 있습니다. 값 자체는 팀 채널로 받습니다.
- AI 기능을 로컬에서 쓰려면 `OPENAI_API_KEY`가 필요합니다(팀 OpenAI 계정 키, 김주우에게 요청).
  없어도 서버는 정상 부팅되고 **태그·요약만 비어서 저장**됩니다.

### 6-1. 첫 실행 순서 (한 번만)

```bash
# 백엔드
cd server && cp .env.example .env        # 값 채우기 (README "server/ 로컬 환경변수")
docker compose up -d                      # 로컬 PostgreSQL + Redis
./gradlew test                            # 여기까지 초록이면 환경 준비 끝

# 프론트
cd app && cp env/dev.example.json env/dev.json    # API_BASE_URL 을 자기 PC IP 로
flutter pub get && flutter test           # 여기까지 초록이면 환경 준비 끝
flutter run
```

---

## 7. 브랜치 보호 — 🔴 **지금 플랜에서는 불가능하다** (2026-08-14 확인)

> **먼저 읽을 것.** 아래 설정은 **현재 켤 수 없다.** 오가니제이션 `modintps` 가 **Free 플랜**이고,
> GitHub 은 **프라이빗 저장소의 브랜치 보호·Ruleset 을 유료 플랜에서만** 허용한다. API 로 확인:
>
> ```
> GET /repos/modintps/modi/branches/dev/protection  → 403
> GET /repos/modintps/modi/rulesets                 → 403
> "Upgrade to GitHub Pro or make this repository public to enable this feature."
> ```
>
> 선택지는 셋이다:
> 1. **GitHub Team 플랜으로 올린다** (인당 월 $4 수준) — 아래 표대로 설정 가능해진다
> 2. **저장소를 public 으로 돌린다** — 무료로 가능해지지만 코드가 공개된다
> 3. **규칙 없이 운영한다** — 지금 상태다. `dev` 직접 push 가 막히지 않으므로
>    **CLAUDE.md 의 "push 전 `git fetch` → `git merge origin/dev`" 규칙을 사람이 지켜야 한다.**
>    (2026-07-30 에 이 규칙을 어겨 배포 설정이 통째로 사라진 사고가 실제로 있었다.)
>
> 아래 표는 **1번을 선택했을 때** 그대로 쓰면 되는 설정이다.

`dev`에 push할 수 있는 사람은 **서버에서 임의 코드를 돌릴 수 있는 사람**입니다(배포 잡이 SSH로
들어와 저장소의 `deploy/deploy.sh`를 그대로 실행합니다). 그래서 직접 push를 막습니다.

GitHub → Settings → Branches(또는 Rules) → `dev`:

| 항목 | 설정 |
|---|---|
| Require a pull request before merging | ✅ |
| Require status checks to pass | ✅ → **`gate` 하나만** 선택 |
| Require approvals | 지금은 **0**, 팀원이 합류한 뒤 **1** |
| Do not allow bypassing the above | ✅ |

> 🔴 **`app`·`server`·`ai` 를 필수 체크로 걸지 마세요.** 이 셋은 바뀐 영역만 도는 잡이라
> 문서만 고친 PR에서는 **스킵**됩니다. 스킵된 체크를 필수로 지정하면 그 PR이 영구히 머지
> 대기에 걸릴 수 있습니다. `gate` 잡이 "셋 중 실패한 게 없다"를 대신 보고하도록 만들어 뒀습니다.
>
> ⚠️ 체크 목록에는 **워크플로가 한 번 돌아본 뒤에야** 나타납니다. 첫 push 뒤에 설정하세요.

---

## 요약 체크리스트

**전원**
- [ ] SSH 키 만들어 **공개키(`.pub`)** 보내기 → 등록되면 `ssh modi` 확인
- [ ] GitHub 저장소 초대 수락 + `git remote set-url` + **GitHub 사용자명 알려주기**
      (CODEOWNERS에 넣어야 리뷰어가 자동으로 붙습니다)
- [ ] 도구 버전 확인 — Flutter `3.44.8` / JDK `21` (`flutter --version`, `java -version`)

**프론트 (윤주하 · 김예원)**
- [ ] Firebase 콘솔 초대 수락 → `flutterfire configure` → **debug SHA-1 지문 등록**
- [ ] `app/env/dev.json` 만들기 → `flutter test` 초록 확인

**백엔드 (박민영)**
- [ ] Firebase 콘솔 초대 수락 → 서비스 계정 키 발급 → `server/.env` → `./gradlew test` 초록 확인

**해당자**
- [ ] 오라클 콘솔 초대 수락 + **MFA 켜기** (인스턴스 확인이 필요한 사람)
- [ ] Tailscale 초대 수락 (SSH가 timeout 나는 네트워크를 쓰는 사람)
- [ ] **가비아 결제 계정이 누구인지 알려주기** ← 이게 막히면 DNS 전환을 못 합니다
- [ ] **Apple Developer 옛 계정 접근이 있으면 번들 ID 3개 확인** ← 접근 끊기기 전에

**김주우**
- [ ] 받은 공개키를 서버 `authorized_keys`에 등록
- [ ] 오라클 사용자·그룹·정책(`use instance-family`) 설정
- [ ] Tailscale 초대 발송
- [ ] **Firebase 콘솔에 3명 편집자로 초대**
- [ ] GitHub 저장소 초대 + **CODEOWNERS의 `@TODO-이름` 을 실제 핸들로 교체**
- [ ] GitHub Secrets **4개**(`SSH_HOST`·`SSH_USER`·`SSH_PRIVATE_KEY`·`SSH_KNOWN_HOSTS`) → **배포 1회 초록 확인**
      (deploy key 는 필요 없다 — org 정책으로 금지돼 있고, 소스는 러너가 rsync 로 보낸다)
- [ ] `dev` 브랜치 보호 (필수 체크 `gate`) ← 첫 push 뒤에
- [ ] DNS 전환 (가비아 계정 확보 후, `MINIO_ENDPOINT` 원복과 함께)
