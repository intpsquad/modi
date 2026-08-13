# 백엔드 핸드오프 — 라이브 배너 콕(POKE) 중복 제거

작성 2026-08-08 (QA, 프론트/디자인 요청). 대상: `ActivityService` 담당자.

## 문제
홈 라이브 배너(활동 피드)에서 **A가 B를 여러 번 콕 찌르면 그 횟수만큼 배너에 뜬다.** `PokeService`가 콕 1회마다 `activities`에 `POKE` 행을 하나씩 append하고, `ActivityService.groupAndMap`은 **`TODO_COMPLETED`만 (작성자+날짜)로 묶고 `POKE`는 안 묶기** 때문(현행 `ActivityService.java:125~138`). 게다가 `getRecentActivities`는 **최신 20건**만 보므로(`findByRoomIdOrderByCreatedAtDesc(roomId, 20)`), 콕 스팸이 그 20칸을 다 차지해 다른 멤버 활동이 밀려난다.

## 결정 (사용자 확정 2026-08-08)
- **시간 윈도우는 도입하지 않는다.** 현행 "최신 N건(20건)" 방식 유지.
- **콕은 "보낸 사람 → 받는 사람" 조합당 배너에 1건으로 합친다.** 횟수와 무관 — 14104번을 찔러도 1건. (옵션: 문구에 "N번" 표기 여부는 자유.)

## 구현 위치·방법
현행 그룹핑은 조회 후 후처리다: `getRecentActivities` → `activityRepository.findByRoomIdOrderByCreatedAtDesc(roomId, limit=20)` → `groupAndMap`. `groupAndMap`이 이미 `TODO_COMPLETED`를 `actorId + 날짜(KST)` 키로 `LinkedHashMap.merge`한다. **같은 패턴으로 `POKE`를 `actorId + targetId`(또는 `targetName`) 키로 합치면 된다** — 최신 `createdAt`을 대표로, 필요하면 count 합산.

⚠️ **주의 — 20칸 잠식**: 위 후처리만 하면 콕은 1건으로 줄지만, **최신 20행 조회가 이미 콕 스팸으로 채워진 뒤**라 다른 활동이 그 전에 잘려 나간다("콕 1건 + 다른 활동 거의 없음"). "콕 1건 **+** 다른 활동도 그대로"를 완전히 살리려면 **쿼리 단계에서 콕을 먼저 1건으로 줄이고 나서 20건을 세야** 한다. 택1:

- **(a) 후처리만** — `groupAndMap`에 POKE 합치기 추가. 가장 간단. 배너에 콕이 중복으로 보이는 문제는 해결되나, 스팸 시 다른 활동이 밀리는 부작용은 남는다. (요청의 핵심인 "1건만 보이게"는 충족.)
- **(b) 쿼리 단계 dedup(권장)** — 리포지토리에서 **(from_user, to_user)별 최신 POKE 1행 + 그 외 타입 전체**를 모아 정렬·limit. 예: POKE는 `GROUP BY (actor_user_id, target_user_id)` 후 `MAX(created_at)`, 나머지 타입은 그대로 UNION → 최신순 20건. 스팸이 20칸을 잠식하지 않는다.

권장은 **(b)** — "콕 1건 + 다른 활동도 그대로"라는 요청 취지를 완전히 만족한다.

## 부수 결정
- **`POKE_ACCUMULATED`(5의 배수마다 "콕 N개 쌓였어요")** 는 콕을 1건으로 합치면 성격이 겹칠 수 있다. 유지할지/폐기할지 함께 결정(폐기하면 `ActivityService.isMilestone`/`MILESTONE_STEP`의 POKE 분기와 `PokeService` 기록부 정리).
- **문구**: `POKE` = "{actor}님이 {target}님을 콕 찔렀어요 👋" 그대로. "N번" 표기 원하면 count를 실어 프론트 `homeActivityMessages`에 분기 추가(프론트가 대응).

## 프론트 영향
**없음.** 배너(`activity_banner.dart`)는 서버가 준 `activities[]`를 그대로 렌더한다. 서버에서 콕이 1건으로 오면 배너도 1건이다. (문구에 "N번"을 넣기로 하면 그때만 프론트 `home_activity_messages.dart` 소폭 수정.)
