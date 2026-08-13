# 알림 탭 → 화면 이동(딥링크) — 백엔드 요구사항

> 작성: 2026-08-08 (프론트/디자인) · 대상: 백엔드 · 티켓 후속
> 관련: `server/.../global/notification/{PushNotifier,FirebaseCloudMessagingPushSender,PushSender}.java`, 프론트 `app/lib/features/notifications/{fcm_service,notification_router}.dart`
>
> **2026-08-09 구현 완료.** `data`엔 `type`+`roomId`만 싣는다 — `scheduleId`/`todoId`/`archiveItemId`는
> 이 문서 스스로 "지금은 프론트가 안 씀"이라 명시한 선택 항목이라 만들지 않았다(필요해지면 그때 추가).
> `ARCHIVE_ANALYSIS_DONE`은 방 컨텍스트가 없는 알림이라(`room=null`, `PushNotifier` 참고) `data`에
> `type`만 실린다 — 이 문서의 "roomId 필수" 표는 방 컨텍스트가 있는 나머지 6종 기준이다.

## 배경
프론트는 이제 알림을 **탭하면 해당 화면으로 이동**하도록 배선했다(종료/백그라운드/포그라운드 모두). 하지만 이동하려면 푸시에 **어디로 갈지 정보(`data`)**가 필요한데, **현재 서버는 `notification`(title/body)만 보내고 `data`를 안 싣는다**(`PushSender.send(fcmToken, title, body)`). → `data`를 추가해줘야 탭 이동이 동작한다.

프론트는 **전방 호환**이다: `data`가 없으면 탭해도 그냥 앱만 열린다(크래시·회귀 없음). 그래서 타입별로 **점진적으로** 추가해도 된다.

## 계약 — 푸시 `data`에 아래를 넣어준다 (값은 전부 문자열)
| 키 | 값 | 필수 |
|---|---|---|
| `type` | `PushType` 이름 그대로 — `POKE` / `SCHEDULE_DAY_BEFORE` / `SCHEDULE_DDAY` / `ROOM_MEMBER_JOINED` / `ROOM_MEMBER_LEFT` / `ASSIGNED_TODO_ADDED` / `ARCHIVE_ANALYSIS_DONE` | ✅ |
| `roomId` | 그 알림이 속한 방 id | ✅ (방 컨텍스트가 있는 알림) |
| `scheduleId`/`todoId`/`archiveItemId` 등 | 상세 딥링크용(선택) | ⬜ 지금은 프론트가 안 씀. 넣어두면 추후 상세 화면 이동에 활용 |

**프론트가 하는 매핑(FYI)** — `type` → 이동 탭, `roomId` → 방 전환:
- `POKE`, `ASSIGNED_TODO_ADDED` → 투두 탭(`/todos`)
- `SCHEDULE_DAY_BEFORE`, `SCHEDULE_DDAY` → 일정 탭(`/schedule`)
- `ROOM_MEMBER_JOINED`, `ROOM_MEMBER_LEFT` → 멤버·초대(`/mypage/members`)
- `ARCHIVE_ANALYSIS_DONE` → 모아보기 탭(`/archive`)

## 필요한 서버 변경
1. **`PushSender.send(...)`에 `Map<String,String> data` 인자 추가**, `FirebaseCloudMessagingPushSender`에서 `Message.builder()....putAllData(data)`.
2. **`PushNotifier.notify/notifyEach`가 `type`을 이미 알고 있으니 `data`에 `type=type.name()`을 자동 포함**하고, 호출부가 넘긴 `roomId`(+선택 ids)를 합쳐 sender에 전달.
3. **각 호출부**(콕 찌르기 `PokeService`, 일정 `ScheduleReminderService`, 방 입·퇴장 알림, 담당 투두 추가, 자료 분석 완료 `ArchiveAnalysisNotifier`)가 **해당 `roomId`**(가능하면 상세 id도)를 넘기도록 시그니처 확장.

> iOS는 `data`-only 메시지도 알림 탭 라우팅에 문제 없다(현재도 `notification` 동봉이라 배너는 그대로 뜬다). Android 포그라운드 배너는 프론트가 로컬 알림으로 띄우며 `data`를 payload로 실어 탭 이동을 처리한다.

---

# 📋 알림 관련 백엔드 할 일 — 전체 요약 (2026-08-09 전부 완료)

1. ~~**[전체/개별] 발송 게이트 변경**~~ ✅ — 이미 반영돼 있었음(확인).
2. ~~**[딥링크] 푸시 `data` 추가**~~ ✅ — `type`+`roomId`.
3. ~~**[정리] `knock_enabled` 잔재 제거**~~ ✅ — 서버+앱 같은 커밋(`docs/backend/notification-handoff.md` §D 참고, 앱 응답 파싱 크래시 리스크가 진짜 위험이었다).
