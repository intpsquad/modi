# 0001 — 시스템 아키텍처

## 구성요소
- **Flutter 앱** (iOS/Android): UI, 로컬 캐시, Firebase 세션 보관, 서버 API 호출.
- **Spring Boot API** + **PostgreSQL**: 모든 도메인 데이터·비즈니스 로직. 아카이브 태깅은 LLM을 직접 호출하고, 투두 추천은 아래 AI 서버를 경유한다.
- **AI 서버 (FastAPI, `ai/`)**: **투두 추천(S-16-B) 전용**. 앱이 직접 호출하지 않고 Spring의 요청만 받으며, 외부에 포트를 열지 않는다(Docker 내부 네트워크). 도메인 DB를 직접 조회하지 않고 필요한 데이터는 Spring이 요청에 실어 보낸다. 마이크로서비스가 아니라 **Python 생태계(LangChain·평가 도구) 때문에 분리된 전용 워커**다 — 자체 DB도 도메인 경계도 없다(2026-07-28 확정, 근거는 `ai/docs/DECISIONS.md`).
- **Redis**: 초대코드 전용(room_id↔code, TTL 1일) — 도메인 데이터 아님, 휘발성 캐시로만 사용(2026-07-23, `specs/0002-data-model.md` 참고).
- **Firebase Authentication**: 인증 전용 (소셜 4종 + 이메일/비번). ID 토큰(JWT) 발급.
- **Firebase Cloud Messaging(FCM)**: 푸시 알림 전용(콕찌르기/재촉/마감임박). 앱 부팅 시 권한을 확인하고 로그인 사용자의 토큰을 `PUT /me/fcm-token`으로 등록한다. 콕찌르기 발송 파이프라인은 `global/notification/PushSender`를 통해 크리덴셜이 있을 때만 실제 발송하며, 마감임박 알림은 `specs/OPEN.md` 미결이다. 사용자별 수신 채널은 `notification_settings`에서 콕찌르기/재촉, 일정 전날/디데이, 방 멤버 입장/퇴장, 내 담당 투두 추가를 개별 관리한다. 실제 채널별 발송 트리거와 중복 방지 정책은 각 기능 구현에서 적용한다(`PUT /me/fcm-token` 및 `specs/0011-멤버-투두-콕찌르기.md` 참고).
- **YouTube Data API v3**: 유튜브 자료의 메타데이터(제목·채널명·설명·썸네일) 조회 전용(2026-08-05 확정). 페이지 HTML 을 긁던 것을 대체했다 — **운영 서버(데이터센터 IP)는 `youtube.com` 이 구글 봇 판정 CAPTCHA(`google.com/sorry`)에 302로 막힌다**(2026-08-04 실측, `specs/OPEN.md`). 새 시크릿(`YOUTUBE_API_KEY`)과 **쿼터**(`videos.list` 호출당 1 유닛 · 하루 10,000)를 갖는다는 점에서 성격이 `OPENAI_API_KEY` 와 같다. **HTML 폴백은 없다** — 키가 없으면 유튜브 링크만 등록에 실패하고 서버 로그에 `error` 가 남는다(`YouTubeUrlCrawler`). 인스타 크롤링은 공식 API 가 아니라 별도다(`specs/0010-아카이브-탭.md`).
- **MinIO(S3 호환 오브젝트 스토리지)**: 프로필 사진 등 이미지 업로드 전용(2026-07-29 확정, `specs/OPEN.md` 확정 기록 참고). 업로드는 서버가 발급한 **presigned PUT URL**로 클라이언트가 MinIO에 직접 올리고(서버는 바이트를 안 거침), 조회는 `profile/` 접두사만 **공개 읽기**로 열어 만료 없는 고정 URL을 그대로 쓴다(아바타처럼 자주·오래 노출되는 이미지에 presigned GET은 부적합 — 버킷 전체가 아니라 접두사만 여는 이유는 `specs/OPEN.md` 확정 기록 참고). 로컬은 `server/docker-compose.yml`의 `minio` 서비스(포트 9000 API/9001 콘솔), 서버는 `global/storage/ObjectStorage`(인터페이스)+`MinioObjectStorage` — `firebase.credentials-path`와 동일한 `@ConditionalOnProperty` 패턴이라 크리덴셜 없으면 업로드 API가 503만 내고 부팅은 안 깨진다.

## 인증 흐름 (핵심)
1. Google과 Apple은 Firebase Authentication의 네이티브 provider로 로그인하고, Kakao는 카카오 Flutter SDK로 OAuth access token을 받는다. Apple 로그인은 iOS Runner의 Sign in with Apple capability를 사용하며, Firebase 콘솔에서 Apple provider를 활성화해야 한다.
2. Kakao access token은 앱이 공개 `POST /auth/kakao`로 서버에 전달한다. Spring Boot가 Kakao 사용자 API로 토큰을 검증하고 프로필을 조회한 뒤, Firebase Admin SDK Custom Token을 발급한다. 앱은 `signInWithCustomToken`으로 Firebase 세션을 만든다.
3. Firebase가 ID 토큰(JWT)을 발급하고 앱이 세션을 보관·자동 갱신한다. 이후 모든 보호된 서버 호출은 `Authorization: Bearer <id-token>`을 사용한다.
   - Flutter 앱은 Access/Refresh Token을 별도 Secure Storage에 복제하지 않는다. Firebase Auth SDK가 로그인 세션과 갱신 토큰을 보관하고, 앱은 호출 시점의 ID 토큰만 요청한다.
   - 보호 API는 공통 `AuthenticatedHttpClient`가 Bearer 헤더를 주입한다. 최초 401에는 Firebase ID 토큰을 강제 갱신해 같은 요청을 한 번만 재전송하고, 재시도도 401이거나 갱신이 실패하면 Firebase 세션을 정리한다.
   - 앱 부팅의 `GET /rooms`는 라우팅 게이트 상태까지 함께 바꿔야 하므로 공통 클라이언트의 401 재시도를 끄고 `AppSession`이 기존 계약대로 갱신·재시도·로그아웃을 담당한다.
4. Spring Boot가 Firebase Admin SDK로 ID 토큰의 서명·만료를 검증하고 `uid`를 추출해 인가한다.
5. 첫 로그인 시 서버가 `users`에 프로필을 upsert한다. Kakao 신규 사용자는 제공된 프로필 닉네임·프로필 이미지를 기본값으로 사용하고, 프로필이 없거나 동의하지 않으면 닉네임은 `사용자` + 4자리 난수로 폴백한다. Google 신규 사용자는 Firebase가 제공한 이름·프로필 이미지를 기본값으로 한 번 저장한다. 기존 사용자의 설정 페이지 수정값은 덮어쓰지 않는다.
6. **이메일도 매번 upsert에 함께 채운다**(V29, 2026-08-12 확정 — 아래 참고). Google/Apple/이메일 자체가입은 `FirebaseAuthFilter`가 이미 뽑아둔 ID 토큰의 이메일 클레임을 그대로 쓰고(새 조회 없음), Kakao는 Custom Token 경로라 ID 토큰에 이메일이 안 실려 Kakao 사용자 API 응답(`kakao_account.email`, "이메일" 동의항목 필요)에서 직접 받는다. `login_provider`(신규 생성 시에만 기록)와 달리 이메일은 **값이 오고 기존과 다르면 매번 갱신**한다 — 계정 이메일이 바뀔 수 있고, 이 컬럼이 생기기 전 가입한 유저를 다음 로그인에서 자연히 백필하는 유일한 경로이기 때문이다. 값이 안 오면(대부분의 카카오 요청) 기존 값을 지우지 않는다.

**확정(2026-08-12 뒤집힘)**: `users.email` 컬럼을 추가했다(V29, nullable, UNIQUE 아님). **순수 정보성 조회용**(CS/관리자가 Firebase 콘솔 없이 uid→이메일을 알 수 있게)이며, 중복가입 판정·계정 병합에는 쓰지 않는다 — 그 판정은 여전히 Firebase Admin SDK(`FirebaseEmailAvailabilityChecker`) 기준이다(`specs/OPEN.md` 참고). 여러 provider로 가입한 동일인이 같은 이메일 값을 가질 수 있어 UNIQUE를 걸 수 없고, Apple 익명 릴레이 이메일(`specs/0007-온보딩.md`)을 일반 이메일 계정과 임의로 연결하지 않는다는 기존 원칙과도 충돌하지 않는다. 이전 확정("자체가입은 아이디를 이메일로 사용, 별도 이메일 필드 없음")은 폐기됐다 — `full_spec.md`/`specs/0002-data-model.md`의 원 용어 보존 절만 예외.

**원칙**: Firebase에는 도메인 데이터를 넣지 않는다(Firestore 등 미사용). 오직 인증·푸시만.

**범위**: 현재 OAuth는 Kakao·Google·Apple이며, Apple은 Apple Developer 계정 준비 후 구현한다. 네이버는 현재 범위에 포함하지 않는다. Kakao native app key와 Firebase 서비스 계정은 소스에 커밋하지 않는다. Firebase 서비스 계정이 없는 테스트/로컬 환경에서도 `/auth/kakao` 라우트는 문서화되며, 실제 호출은 안전하게 503으로 종료된다.

## AI 기능 흐름
- 앱은 LLM을 직접 부르지 않는다.
- **제공자**: Claude API가 아니라 **OpenAI(OpenAI 호환 `chat/completions`)**.
  - **~~옛 LLM 게이트웨이 경유~~(2026-07-27 확정) → 2026-08-13 `api.openai.com` 직접 호출.** 원 프로젝트 종료로 **게이트웨이 키가 2026-08-14에 회수**돼 그 경로 자체가 사라졌다. 결제 주체도 팀의 OpenAI 플랫폼 계정으로 바뀌었다. 주소는 `.env` 한 줄로 갈아끼운다(`SPRING_AI_OPENAI_BASE_URL` / AI 서버 `OPENAI_BASE_URL`) — 코드 변경 없이 제공사를 바꿀 수 있게 2026-08-12에 통과 줄을 넣어뒀다(`deploy/docker-compose.app.yml`).
  - **⚠️ 키 환경변수(`OPENAI_API_KEY`) 이름을 바꿀 때는 운영 `.env`를 같은 배포에서 함께 바꿔야 한다** — 어긋나면 값이 안 들어와도 **부팅은 성공하고 AI 기능만 조용히 꺼진다**(아래 `@ConditionalOnProperty` 설명이 그 이유다). 로그에 흔적이 없어 발견이 늦는다. 2026-08-13에 옛 게이트웨이 이름을 딴 변수명·클래스명(`GmsAi*`)에서 개명할 때 실제로 그렇게 했다.
  - **모델은 세 기능 모두 `gpt-5.4-nano`**(2026-08-13 통일). 자동 태깅만 `gpt-5-nano`였는데, 그걸 정당화한 유일한 축이 게이트웨이 크레딧 등급이라 게이트웨이와 함께 사라졌다 → `ai/docs/EXPERIMENTS.md` #34. ⚠️ 여기 값을 적어두면 드리프트한다(실제로 그랬다 — 2026-08-02 리뷰에서 잡혔다). **단일 진실은 `ai/docs/DECISIONS.md`**이고, 프로퍼티가 셋으로 갈려 있는 것은 한 기능만 바꿔 재보기 위한 것이다.
  - 서버는 Spring AI(`spring-ai-starter-model-openai`)의 클라이언트 클래스(`ChatClient`)만 사용하고, 자동설정(`OpenAiChatAutoConfiguration` 등)은 전부 끈 뒤 `FirebaseConfig`와 동일하게 `@ConditionalOnProperty(spring.ai.openai.api-key)`로 감싼 빈을 직접 구성한다(`config/OpenAiConfig.java`) — 키(`OPENAI_API_KEY` env var) 없는 로컬/CI 환경에서는 그 빈이 생성되지 않고 호출부가 빈 태그로 폴백한다.
- **경로가 둘로 갈린다.** 태깅은 Spring이 LLM API를 직접 부르고, 추천은 AI 서버(FastAPI)를 경유한다(2026-07-28 확정, `ai/docs/DECISIONS.md`).
  ```
  투두 추천   앱 → Spring → AI 서버(FastAPI) → OpenAI
  자동 태깅   앱 → Spring ───────────────────→ OpenAI
  ```
- **투두 추천(S-16-B)**: 앱 → 서버 `POST /rooms/{roomId}/todos/ai-suggest` → Spring이 (방 목표 + 카테고리 + 기존 투두 + 아카이브 본문·태그)를 모아 AI 서버 `POST /v1/todo-suggestions`로 전달 → 후보 반환. Spring은 `TodoSuggestionClient`(인터페이스) + `HttpTodoSuggestionClient`(RestClient) + `config/AiServerConfig`로 구성되며, 태깅의 `AiTaggingClient`/`OpenAiConfig`와 같은 3분할 패턴이다.
  - 내부 호출 검증은 `X-Internal-Key`(양쪽 `INTERNAL_API_KEY` 환경변수). 비어 있으면 검증을 건너뛴다(로컬 개발).
  - AI 서버 실패·타임아웃은 **502**로 올린다 — 태깅과 달리 조용히 빈 결과로 폴백하지 않는다(추천은 그 화면의 본체라 앱이 재시도 UI를 띄워야 한다).
  - **이미 노출한 후보 제외(`excluded_todos`) 구현 완료**(2026-07-30). 후보를 반환할 때 제목을 `todo_suggestion_exposures`(`V6`)에 남기고, 다음 요청에 **방별 최근 50개**를 실어 보낸다. AI 서버는 원래부터 이를 지원했다 — 프롬프트에 싣고(`ai/src/modi_ai/suggest.py`) `filter_candidates`가 코드로 한 번 더 거른다. 비어 있던 것은 Spring의 저장소뿐이었다.
    - **아는 구멍**: 기록 시점이 "생성해 반환할 때"이므로 사용자가 응답을 받기 전에 이탈하면 **못 본 후보도 제외된다.** 앱이 "실제로 보여줬다"를 되보고하는 대안은 기각했다(엔드포인트·앱 변경이 늘고, 그 보고가 실패하면 막으려던 중복이 그대로 재발한다). 50개가 롤오버되면서 되살아나므로 영구 손실은 아니다.
    - 기록 실패는 삼킨다 — 후보는 이미 만들어졌으므로 응답은 그대로 낸다(태깅·요약 실패 폴백과 같은 방향). 단 **삼키는 범위를 DB 계열 예외로 좁혔다** — `catch (Exception)`이면 프로그래밍 버그까지 함께 삼켜 "추천은 되는데 중복만 나오는" 원래 증상으로 조용히 되돌아간다. 로그도 `error`로 올려 알람 대상이 되게 했다.
    - ~~**⚠️ 후보가 마르는 부작용**(2026-07-30 리뷰에서 발견)~~ → **2026-08-03 해결.** 실사용에서 실제로 터졌다 — 후보가 8개에서 1~2개로 떨어졌고 후보 1개당 비용이 5~10배가 됐다. **원인은 역할 중복이었다**: 채택한 후보는 이미 `existing_todos`(방의 투두 전체, 상한 없음)로 영구 제외되는데 노출 기록이 같은 일을 한 번 더 하면서 **채택하지 않은 후보까지 영구히 막았다**(관측된 방: 채택 2개 vs 제외 50개). 제외 창을 **50 → 16**(회당 상한 8개 × 직전 2회차)으로 좁혀 단기 중복 방지 전용으로 되돌렸다 — 같은 방 데이터로 3회씩 재보니 후보 평균이 2.0 → 6.0 으로 회복했다(`ai/docs/EXPERIMENTS.md` #24). 앱 빈 상태 문구도 원인을 단정하지 않게 고쳤다(`자료를 더 담거나, 잠시 후 다시 시도해 주세요`) — 빈 결과의 원인이 둘인데 시트는 어느 쪽인지 모르기 때문이다. **제외 창을 비우는 수단은 만들지 않았다** — 창이 줄면서 자연히 풀리므로 앱·서버 양쪽에 기능을 더할 이유가 없었다.
  - **의미 중복 후보 제외**(2026-07-30) — 위 `excluded_todos`는 **글자가 같은** 재노출만 막는다. 실측에서 정규화 기준 24/24 전부 고유인데도 같은 할 일이 3회차 내내 반복됐다(`ai/docs/EXPERIMENTS.md` #17). 그래서 AI 서버가 후보 제목과 `excluded_todos`를 임베딩해 **코사인 유사도 0.65 이상이면 버린다.** 저장하지 않는다 — 요청 시점의 짧은 문자열이라 배치 1회(실측 24개 2.73초)로 끝나고, 자료 임베딩(RAG 2단계)과는 별개다.
    - **⚠️ 이 층은 문제를 절반도 해결하지 못한다.** 라이브 실측(6회차 29개)에서 진짜 중복은 `0.578~0.698`, 비중복은 `0.604`까지 올라와 구간이 겹친다 — 짧은 한국어 제목은 같은 도메인 안에서 코사인이 좁은 띠에 몰린다. 0.65는 `오탐 0`(비중복 최대와 여유 0.046)을 지키면서 잡을 수 있는 최대이고, **라이브 중복 8건 중 3건만 잡는다.** 처음 0.70으로 배선했을 때는 **하나도 잡지 못했다**(최대 관측 0.698). 자세한 수치와 대안 후보는 `ai/docs/EXPERIMENTS.md` #17.
    - 임베딩 호출이 실패하면 문자열 중복 제거 결과를 그대로 반환하고 `error`를 남긴다(추천 자체를 죽이지 않는다). 임베딩 타임아웃은 **Spring의 read timeout 60초 예산 안에** 들어와야 한다 — 최악 20초로 잡았다(10초 × 재시도 1회).
    - **응답 시간이 늘어난다**: 2회차 이후는 임베딩 왕복(실측 2.73초)이 LLM 시간 위에 더해진다. 이는 `ai/docs/DECISIONS.md`의 미확정 항목 "추천 응답 동기 유지 여부"에 직접 영향을 준다.
    - **후보가 마르는 문제를 앞당긴다** — 아래 "후보가 마르는 부작용"과 같은 구멍이고, 이 층이 후보 수를 더 줄이므로 빈 화면이 더 빨리 온다.
  - **트랜잭션은 셋으로 나뉜다**(2026-07-30) — 재료 읽기(readOnly) → **LLM 호출은 트랜잭션 밖** → 노출 기록(write). 원래는 하나의 `readOnly` 트랜잭션이 LLM 호출까지 감싸 실측 7~9초 동안 DB 커넥션을 붙잡고 있었다(`ai/docs/EXPERIMENTS.md` #10). 자기 호출은 프록시를 타지 않으므로 `TodoSuggestionPayloadLoader`·`TodoSuggestionExposureStore`를 별 빈으로 뽑았다.
- **아카이브 자동 태깅(S-25-C, 구현 완료)**: 앱 → 서버 자료 등록 → 서버가 본문 텍스트 확보(링크는 크롤링, 텍스트는 그대로) 후 LLM API로 태그 생성 → 저장(사용자 편집 가능). 태깅 실패/타임아웃 시 태그 없이 등록 진행(`specs/OPEN.md` 2026-07-27 확정).
- 서버에서: API 키 보호(env var, 커밋 금지), 입력 크기 제한(크롤링 본문 4000자로 잘라 프롬프트에 전달), 비용/레이트 제어(태그 최대 5개), 프롬프트 인젝션 방어(시스템 프롬프트로 본문 내 지시 무시 지시).
- **링크 크롤링(S-25-C)의 SSRF 방어**: http/https 스킴만 허용, 사설/루프백/링크로컬/멀티캐스트 IP 차단, 리다이렉트 미추종, 연결/읽기 타임아웃 5초, 응답 크기 상한 2MB — `archive/JsoupUrlCrawler.java`.
  - 🔴 **"리다이렉트 미추종"의 유일한 예외: `NaverUrlCrawler`** *(2026-08-05)*. 네이버 지도 앱의 공유 버튼이 단축 주소(`naver.me/…`)를 주는데 그게 3xx 라 위 규칙에 걸려 등록 자체가 안 됐다. 이 크롤러만 **한 홉**을 따라가되, **목적지 호스트를 허용 목록으로 잠근다**(`modi.archive.naver.allowed-hosts`, 기본 `naver.com,naver.me`). 두 번째 홉(업종 경로)도 같은 검사를 받는다. **넓히지 말 것** — 넓히면 단축 주소가 서버를 임의 호스트로 보내는 통로가 되어 위 방어가 통째로 무의미해진다. 장소가 아닌 목적지는 `JsoupUrlCrawler` 로 넘겨 스킴·IP 검증을 **다시** 받게 한다(도메인 검사와 IP 검사가 상보적으로 걸린다). 다른 사이트 크롤러(유튜브·인스타)는 여전히 추종하지 않고 URL 을 재조립한다.

## 실시간 (확정: 폴링)
- 진행률·콕찌르기·멤버 상태는 **폴링 + 당겨서 새로고침**으로 처리(MVP). 웹소켓/서버 푸시는 도입하지 않는다. 알림만 푸시(FCM/APNs)로 보완.

## 공유 익스텐션 (네이티브, S-25-D)
- iOS Share Extension(Swift/SwiftUI) + Android `ACTION_SEND` intent-filter를 처리하는 네이티브 Activity(Kotlin) — 둘 다 Flutter 엔진을 띄우지 않는다. iOS는 익스텐션 메모리 제한(약 120MB) 때문에 네이티브가 필수이고, Android도 플랫폼 일관성을 위해 동일하게 네이티브로 구현한다(2026-07-27 확정). iOS 구현은 `app/ios/ShareExtension` 별도 타깃에서 URL/텍스트만 받고, 서버 등록 응답 후 확장을 닫는다.
- **인증(Android)**: Firebase Auth Android SDK가 로그인 세션을 앱 프로세스 전역(네이티브 SharedPreferences)에 영속화하므로, 같은 앱 모듈의 순수 네이티브 `ShareActivity`가 `FirebaseAuth.getInstance().currentUser.getIdToken(false)`로 최신 ID 토큰을 얻는다(만료 시 SDK가 내부적으로 자동 갱신).
- **인증(iOS)**: Share Extension은 별도 프로세스라 Firebase Auth의 Dart 세션을 직접 읽지 않는다. Flutter `ShareAuthSync`가 `idTokenChanges()`의 최신 ID 토큰과 API 주소를 MethodChannel로 `AppDelegate`에 전달하고, 메인 앱과 확장이 공유하는 `$(AppIdentifierPrefix)group.com.nomara.modi` Keychain access group에 토큰을 저장한다. API 주소만 App Group UserDefaults에 두며, 확장은 Flutter 엔진·Firebase SDK 없이 이를 읽어 보호 API를 호출한다. 토큰 저장 실패·부재·401은 등록하지 않고 앱 로그인 안내로 종료한다.
- 화면 흐름·데이터·엣지케이스 상세: `specs/0014-외부-공유-등록.md`.

## 나중 네이티브 확장 경계 (지금은 구조만)
- **위젯**: `home_widget` 패키지 + iOS WidgetKit / Android App Widget 네이티브.
- **Live Activity**: `live_activities` 패키지 + iOS ActivityKit 네이티브.
- **배경화면 자동화**: Android는 직접(WallpaperManager), **iOS는 앱이 배경화면을 못 바꿈 → 단축어(Shortcuts) 우회만 가능**.
- 이들은 platform channel로 붙으므로, 앱을 기능(feature) 단위로 모듈화해 나중에 확장 타깃을 끼울 수 있게 유지.

## 배포 (확정: 단일 인스턴스, 2026-07-22 / 도메인 2026-07-29 / **인프라 이관 2026-08-13**)
- 저장소: **GitHub**(프라이빗). CI/CD: **GitHub Actions**(`.github/workflows/ci.yml` 한 파일).
- 서버·PostgreSQL·Redis·AI 서버·MinIO·Caddy를 **단일 오라클 클라우드 Ampere A1**(ARM aarch64, 4 OCPU / 24GB, Ubuntu 24.04, ap-tokyo-1)에서 전부 Docker로 함께 운영. DB 마이그레이션은 Flyway.
  - **⚠️ 아키텍처가 ARM 이다.** 앱 층 이미지(temurin·postgres·redis·caddy·minio·uv-python)는 전부 멀티아치라 그대로 뜨지만, **x86_64 전용 툴체인은 못 뜬다** — Flutter 리눅스 타르볼과 Android build-tools(aapt2/d8)가 그렇다. 그래서 앱 CI 는 서버가 아니라 GitHub Actions 에서 돈다. 배포도 러너가 아니라 **서버에서 이미지를 만든다.**
  - **⚠️ PostgreSQL 데이터 디렉토리는 아키텍처 간 복사하지 않는다.** x86_64 → aarch64 이관은 `pg_dump -Fc` 논리 덤프로만 한다(2026-08-12 이관 시 그렇게 했다).
  - *(2026-08-13 이전: 단일 EC2 4 vCPU/15GB + 같은 박스의 Jenkins. 원 프로젝트 종료로 회수됐다.)*
- **도메인(2026-07-29)**: `maramodi.cloud`(가비아). `api.maramodi.cloud` → Spring API, `storage.maramodi.cloud` → MinIO. 루트 도메인 용도는 미정.
  - `jenkins.maramodi.cloud` 는 **2026-08-13에 폐기**했다(Jenkins 제거). A레코드도 지운다 — 남으면 Caddy 가 그 호스트에 인증서를 발급하려다 실패한다.
- **TLS·리버스 프록시**: **Caddy**. Let's Encrypt 인증서를 자동 발급·자동 갱신한다(certbot 크론 없음). 외부에 열린 포트는 **80·443뿐**이며, 80은 HTTP-01 챌린지에 필요하다.
  - `api.maramodi.cloud`는 Swagger UI(`/docs`)와 `/v3/api-docs`를 통과시키고, **Actuator(`/actuator/*`)는 404로 차단**한다 — 헬스체크는 컨테이너 내부에서만 호출한다.
  - `postgres`·`redis`·`ai`는 **호스트 포트를 바인딩하지 않는다**(compose 내부 네트워크 전용). AI 서버를 외부에 노출하지 않는다는 위 원칙이 인프라 수준에서 강제된다.
- **MinIO 노출(2026-07-29 확정)**: MinIO는 `postgres`/`redis`와 달리 **숨길 수 없다** — 앱이 presigned PUT URL로 직접 업로드하고 아바타도 `https://storage.maramodi.cloud/modi/profile/...` 고정 URL로 직접 받아간다(서버가 바이트를 중계하지 않는 설계의 필연적 결과). 대신 범위를 좁힌다: 쓰기는 presigned PUT만, 익명 읽기는 `profile/` 접두사만(`MinioConfig`가 기동 시 정책을 건다 — 실측 `profile/` → 404, 그 외 → 403), **관리 콘솔 9001은 프록시하지 않아 인터넷에서 닫혀 있다**.
  - **Spring이 쓰는 `MINIO_ENDPOINT`는 내부 주소가 아니라 공개 도메인이다.** `MinioClient`가 자기 endpoint로 presigned URL을 만들기 때문에 `http://minio:9000`을 주면 앱이 열 수 없는 URL이 나온다. 그런데 인스턴스 안에서 자기 공인 IP로는 접속이 안 되므로(클라우드가 인스턴스의 자기 공인 IP 헤어핀을 지원하지 않는다 — EC2 시절 실측) **Caddy 컨테이너에 `storage.maramodi.cloud` 네트워크 별칭**을 달아 Docker 내부 DNS가 Caddy를 직접 가리키게 했다. ⚠️ 오라클에서도 이 별칭이 필요한지는 미검증이다(DNS 전환 시 확인). Caddy의 `reverse_proxy`는 원본 Host를 보존하므로 presigned URL의 SigV4 서명도 깨지지 않는다.
  - **`minio.endpoint`는 `application.yml`에 기본값을 두지 않는다**(2026-07-29 수정). 기본값이 있으면 `@ConditionalOnProperty(minio.endpoint)`가 항상 참이 되어 MinIO 없는 환경에서 "업로드만 503"이 아니라 **부팅 자체가 깨진다**(실측: 컨텍스트 초기화 실패 + okhttp 논데몬 스레드가 JVM을 붙잡아 컨테이너는 `Up`인데 8080은 안 열리는 좀비 상태 → `restart` 정책도 안 걸리고 헬스체크만이 잡아낸다). `firebase.credentials-path`와 동일하게 환경변수로만 주는 패턴으로 통일했다.
- **compose 2층 구조**(`deploy/`): 인프라 층(`docker-compose.infra.yml` — **Caddy 하나**)과 앱 층(`docker-compose.app.yml` — spring·ai·postgres·redis·minio)을 `maramodi-edge` external 네트워크로 잇는다. **분리 이유는 TLS 인증서다** — Caddy가 발급받은 인증서를 볼륨에 들고 있어 앱 배포마다 흔들 이유가 없다. 배포는 앱 층만 교체하므로 **Caddyfile·인프라 compose 변경은 서버에서 수동 반영해야 한다**(배포가 반영해주지 않는다).
  - *(2026-08-13 이전: 인프라 층에 Jenkins도 함께 있었고, 그때의 분리 이유는 "Jenkins가 자기 자신이 든 compose를 `up -d`하면 배포 도중 스스로 죽는다"였다. CI가 서버 밖으로 나가 그 제약은 사라졌지만 인증서 때문에 분리는 유지한다.)*
- **배포 트리거(2026-07-29 확정)**: **`dev` 브랜치 머지 시 자동 배포**. `master`는 배포하지 않는다. 서버가 하나라 이 서버가 개발 서버 겸 데모 서버다.
- **이미지 전달**: 컨테이너 레지스트리를 쓰지 않는다. **GitHub Actions의 `deploy` 잡이 SSH로 트리거만 하고, `docker compose build`는 서버에서 돈다**(`deploy/deploy.sh`) — 러너는 x86_64, 서버는 ARM이라 러너에서 만든 이미지는 서버에서 뜨지 않는다.
- **무중단 배포 = blue/green (2026-08-13 확정)**: Spring을 `spring-blue`·`spring-green` 두 서비스로 정의하고(`docker-compose.app.yml`의 `x-spring` 앵커 하나로 공유) **평상시 한 색만 띄운다**. 배포는 ① 멈춘 색을 빌드·기동해 healthy 대기 → ② **활성 파일**(`${MARAMODI_STATE_DIR}/active-upstream.conf`, 내용은 `reverse_proxy spring-<색>:8080` 한 줄)을 바꾸고 `caddy reload` → ③ 옛 색을 graceful 정지. ①에서 실패하면 전환하지 않고 옛 색이 계속 서비스한다. `caddy reload`는 진행 중인 연결을 떨구지 않는다.
  - **왜 두 색을 Caddyfile에 함께 적고 `lb_policy first`로 페일오버하지 않는가**: 멈춘 색은 Docker 내부 DNS에 없어서 헬스체크가 주기적으로 실패 로그를 쌓고, 패시브 실패 상태(`fail_duration`)가 남아 전환 순간에 502가 날 창이 생긴다. **살아있는 색만 알려주면 두 문제가 아예 없다.**
  - 🔴 **활성 파일은 저장소 밖에 둔다.** 배포 잡이 `git reset --hard origin/dev`를 하므로 저장소 안에 있으면 **매 배포마다 활성 색이 커밋된 값으로 되돌아가** 트래픽이 방금 세운 옛 색으로 간다.
  - 🔴 **활성 파일은 `printf > 파일`로 제자리 truncate한다.** 리눅스의 단일 파일 bind-mount는 **inode를 묶는** 것이라 `sed -i`·`mv`로 inode가 바뀌면 **Caddy는 옛 내용을 계속 본다**(호스트에서는 새 내용으로 보인다). ⚠️ 이 함정은 **Docker Desktop(Windows/macOS)에서는 재현되지 않는다** — 파일 공유가 경로 기반이다(2026-08-13 실측). 로컬 확인으로 이 규칙을 기각하면 운영에서만 터진다.
  - 성립 조건 셋 — `server.shutdown: graceful` · compose `stop_grace_period` > `spring.lifecycle.timeout-per-shutdown-phase` · 색 이름이 compose·활성 파일·`deploy.sh` 셋에서 동일. 하나만 빠져도 조용히 깨지므로 `BlueGreenDeployContractTest`가 파일들을 묶어 검사한다.
  - **롤백**: 옛 색 컨테이너가 stop 상태로 남아 있어 `docker start` + 활성 파일 한 줄 + `caddy reload`로 끝난다(재빌드 없음). 두 색이 다 깨진 경우의 두 번째 그물로 배포 전 이미지를 `:previous`로 태깅해 둔다.
  - ⚠️ **DB는 하나다 — 진짜 blue/green이 아니라 롤링이다.** 새 색이 Flyway 마이그레이션을 먼저 돌린 뒤에도 옛 색이 몇십 초 트래픽을 받으므로 **옛 코드가 새 스키마 위에서 돈다.** 파괴적 변경(`DROP COLUMN`·rename·`NOT NULL` 추가)은 배포 두 번으로 쪼갠다(expand→contract). **롤백해도 마이그레이션은 되돌아오지 않는다.** 규칙은 `README.md` "배포 → 스키마 변경 규칙".
  - ⚠️ **AI 서버는 아직 단일이다** — 배포 중 몇 초 끊긴다. 태깅·요약은 폴백이 있어 조용히 스킵되지만 투두 추천은 사용자에게 실패로 보인다.
  - ⚠️ **천장**: 단일 호스트라 커널 업데이트·재부팅·클라우드 유지보수는 그대로 끊긴다. 무중단 **배포**이고 무중단 **서비스**가 아니다.
  - ⚠️ **`dev`에 push할 수 있는 사람 = 서버에서 임의 코드를 돌릴 수 있는 사람이다.** 배포 잡이 저장소의 `deploy/deploy.sh`를 그대로 실행하므로, 그 파일을 바꿀 수 있으면 서버에서 무엇이든 돌릴 수 있다. 그래서 저장소는 프라이빗이고 `dev`는 브랜치 보호 뒤에 둔다.
  - **소스는 러너가 `rsync` 로 서버에 밀어 넣는다**(2026-08-13 변경). 원래는 서버가 GitHub 에서 직접 `git fetch` 하고 그러려면 read-only **deploy key** 가 필요했는데, 이 오가니제이션은 **정책으로 deploy key 를 금지**한다. 정책을 푸는 대신 방향을 뒤집었다 — 러너는 이미 소스를 체크아웃했고 이미 서버 SSH 접근이 있으므로, **서버에 GitHub 자격증명이 하나도 없는 상태**가 된다(자격증명이 줄었으므로 보안 개선이기도 하다). 대가는 서버에서 `git pull` 로 최신 코드를 받을 수 없는 것이고, 사람이 최신 코드로 배포하려면 `workflow_dispatch`(Actions → Run workflow)를 쓴다.
- **시크릿**: 서버의 `/home/ubuntu/maramodi/.env`(compose `--env-file`) + `secrets/firebase-service-account.json`(읽기전용 볼륨 마운트, `FIREBASE_CREDENTIALS_PATH`로 지정). 이미지에 굽지 않는다. 목록·발급 방법은 `README.md`가 단일 진실.
- 앱: EAS 아님(Flutter) → Codemagic 또는 Fastlane으로 빌드/서명/제출(서버 인프라와 무관, 변경 없음). 앱의 `API_BASE_URL`은 release에서 `https://api.maramodi.cloud`를 쓴다.
