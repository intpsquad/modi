# MODI 홈 활동 배너 — 백엔드 요구사항 (활동 피드)

> 작성: 2026-08-06 (프론트/디자인) · 대상: 백엔드
> 관련 프론트: `app/lib/features/home/activity_banner.dart`(위젯 완료) · `home_screen.dart`(배선 완료)
> 관련 추적: `specs/OPEN.md`, `docs/backend/character-handoff.md`(협업 캐릭터도 같은 활동 데이터를 쓴다)

## 0. 배경

홈 상단에 **활동 캡슐 배너(라이브 티커)** 를 추가했다 — 스터디원 활동을 한 줄씩 4초 간격으로 롤링해 소셜 프루프를 유도. **프론트 위젯은 이미 완성**(모든 문구 타입 렌더·롤링·접근성 처리)이고, 지금은 대시보드로 **파생 가능한 메시지만**(팀 진행률·D-day) 실제로 노출 중이다.

**"ㅇㅇ님이 투두 3개를 완료했어요 🔥" 같은 per-user/소셜/자료 메시지는 활동 이벤트 데이터가 없어 아직 못 넣는다.** → 아래 활동 피드가 필요하다.

## 1. 필요한 것: 활동 피드 API

### 엔드포인트 (택1)
- **(A) 신규** `GET /rooms/{roomId}/activities?limit=20` — 방의 최근 활동 목록
- **(B) 기존 확장** `GET /rooms/{roomId}/dashboard` 응답에 `activities: [...]` 배열 추가 (홈에서 한 번에 받게 — **권장**, 요청 수 절약)

### 응답 형태 (구조화 권장 — 문구는 프론트가 조립)
> 서버가 완성된 문장 대신 **구조화된 데이터**를 주면, 카피 문구를 바꿀 때 백엔드 배포가 필요 없다.

```json
{
  "activities": [
    {
      "type": "TODO_COMPLETED",
      "actorNickname": "지훈",
      "actorUserId": "uid_123",
      "count": 3,
      "targetName": null,
      "createdAt": "2026-08-06T09:12:00Z"
    },
    { "type": "ARCHIVE_ADDED", "actorNickname": "서연", "targetName": "DP 정리 영상", "createdAt": "..." },
    { "type": "POKE", "actorNickname": "민재", "targetName": "서연", "createdAt": "..." }
  ]
}
```
- 정렬: **최신·중요순** (서버가 정렬해서 내려주면 프론트는 그대로 롤링만 함)
- 개수: 최근 **10~20개** 정도 (배너는 상위 몇 개만 순환)

## 2. 이벤트 타입 × 데이터 출처

| type | 문구(프론트 조립) | 데이터 출처(기존 테이블) |
|---|---|---|
| `TODO_COMPLETED` | `{actor}님이 투두 {count}개를 완료했어요 🔥` | `todos.completed_at`(최근 완료 집계, 담당=`todo_assignees`) — 담당자 0~1명일 때만 |
| `TODO_COMPLETED_SHARED` | `{대표닉} 외 {count-1}명이 함께 맡은 투두를 끝냈어요 🎉` | 담당자 2명 이상 완료 시(2026-08-08, `live-banner-copy-handoff.md` §2). `targetName`=대표닉(닉네임 최단), `count`=담당자 총원 — 새 필드 없이 기존 응답 필드 재사용 ✅ |
| `TODO_ALL_DONE` | `{actor}님이 맡은 투두를 다 끝냈어요 🎉` | 담당 완료율 100% 도달 시점 |
| `TODO_ADDED` | `{actor}님이 투두를 추가했어요` | `todos.created_at` (작성자 컬럼 필요 — 아래 ⚠️) |
| `SCHEDULE_ADDED` | `{actor}님이 새로운 일정을 등록했어요` | `schedules.created_at` (작성자 컬럼 필요 — 아래 ⚠️) |
| `SCHEDULE_SOON` | `곧 시작되는 일정이 있어요` | `schedules.date`/`time` 임박 |
| `ARCHIVE_ADDED` | `{actor}님이 {folder}에 자료를 추가했어요` | `archive_items.created_by` + `archive_folders.name` ✅ |
| `ARCHIVE_LIKE_MILESTONE` | `{actor}님 자료에 좋아요 {n}개 달성! ❤️` | `archive_likes` count 임계 도달 ✅ |
| `POKE` | `{actor}님이 {target}님을 콕 찔렀어요 👋` | `pokes(from_user, to_user)` ✅ |
| `POKE_ACCUMULATED` | `{actor}님 콕이 {n}개 쌓였어요` | `pokes` to_user 집계 ✅ |
| `MEMBER_JOINED` | `{actor}님이 방에 들어왔어요` | `room_members.joined_at` ✅ |
| `MILESTONE_PROGRESS` | `🎉 팀 진행률 {p}% 돌파!` | 대시보드 진행률 — **프론트가 이미 파생** |
| `DDAY` | `D-{n} · 마감 {n}일 전` | `rooms.end_date` — **프론트가 이미 파생** |
| `WEEKLY_SUMMARY` | `이번 주 완료 {n}개 (지난주 +{d}) 📈` | 주간 `completed_at` 집계(지난주 대비) |
| `NUDGE_NONE_TODAY` | `오늘 아직 완료가 없어요 🥹` | 오늘 완료 0건 |
| `NUDGE_QUIET_MEMBER` | `{actor}님이 {n}일째 조용해요.. 😓` | 완료/활동 공백 (접속 로그 있으면 정밀 — `character-handoff.md`) |
| `NUDGE_UNASSIGNED` | `{n}개의 투두가 주인을 찾고 있어요! 🙋` | 방의 담당자 없는(미지정) 미완료 투두 수(2026-08-08, `live-banner-copy-handoff.md` §4). `count`=n, n>0일 때만 |

> **✅ 표시 = 지금 스키마로 바로 됨.** `MILESTONE_PROGRESS`·`DDAY`는 프론트가 이미 하므로 서버가 안 줘도 됨(중복 피하려면 서버는 나머지 이벤트만 줘도 OK).

### ⚠️ 부족한 컬럼 2개
- `todos`에 **작성자(created_by)** 없음 → `TODO_ADDED`의 actor를 못 낸다. (완료 이벤트는 `todo_assignees`로 가능)
- `schedules`에 **작성자(created_by)** 없음 → `SCHEDULE_ADDED`의 actor를 못 낸다.
- 둘 다 넣을지 결정 필요. 안 넣으면 해당 두 타입은 actor 없이(또는 제외).

## 3. 구현 방식 (택1)
- **(a) 이벤트 테이블** `activity(id, room_id, type, actor_user_id, target_user_id NULL, target_name NULL, count NULL, created_at)` — 각 도메인 액션에서 append. 조회 단순·빠름. (협업 캐릭터의 `user_activity`와 통합 가능 → `character-handoff.md` 참고)
- **(b) 온디맨드 집계** — 조회 시 각 테이블에서 최근 것들을 모아 정렬. 테이블 추가 없음, 대신 쿼리 복잡·무거움.
- → **(a) 이벤트 테이블 권장** (활동은 append-only라 자연스럽고, 캐릭터 판정용 로그와 한 몸으로 갈 수 있음).

## 4. 주의
- **개인정보/노이즈**: 방 내부 한정, 너무 잦은 이벤트(예: 투두 1개씩)는 묶어서(“3개 완료”) 노출.
- **콕(POKE) 중복**: "보낸 사람→받는 사람" 조합당 배너에 1건(횟수 무관, 2026-08-08 확정). `ActivityRepository.findRecentByRoomIdWithPokesDeduped`가 정렬·limit 전에 쿼리 단계에서 줄여, 콕 스팸이 최근 20건 창을 잠식해 다른 활동을 밀어내지 않는다. `POKE_ACCUMULATED`(5배수 마일스톤)는 성격이 달라 그대로 유지. 상세는 `docs/backend/activity-poke-dedup-handoff.md`.
- **중복**: `MILESTONE_PROGRESS`·`DDAY`는 프론트 파생과 겹치지 않게(서버가 주면 프론트 파생 제거).
- **볼륨**: append-only면 증가 빠름 → 최근 N일/롤업 고려.

---

### 요약 (바로 요청용)
1. **활동 피드**: `GET /rooms/{roomId}/dashboard`에 `activities[]` 추가(또는 `/activities` 신규). 구조화 응답(type·actor·count·targetName·createdAt), 최신순 10~20개.
2. **이벤트 타입 12종**: 대부분 기존 테이블(todos/archive/pokes/room_members)로 가능. `TODO_ADDED`·`SCHEDULE_ADDED` actor만 컬럼 부족 → 넣을지 결정.
3. **저장 방식**: `activity` 이벤트 테이블 권장(협업 캐릭터 `user_activity`와 통합 가능).
4. 프론트는 문구 조립·롤링·접근성 완료 → **데이터만 주면 바로 붙는다.**
