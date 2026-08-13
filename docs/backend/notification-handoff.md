# 🔔 알림 설정 — 백엔드 최종 전달안 (통합)

> 작성: 2026-08-08 (프론트/디자인) · 티켓 
> 프론트는 아래 3가지 모두 **배포 가능한 상태로 구현 완료**. 이 문서의 A·B·C가 반영돼야 **end-to-end 동작·테스트**가 됩니다.
> (상세 개별 문서: `notification-all-toggle-handoff.md`, `notification-deeplink-handoff.md`)
>
> **2026-08-09 A·B·C·D 전부 구현 완료.** A는 이번 세션 이전에 이미 반영돼 있었다(확인만 함). B·C·D는
> 이번에 구현. 아래 각 절의 "구현 완료" 표시 참고. E(실기기 end-to-end)는 여전히 사람 확인이 필요해
> 남아 있다.

---

## A. 발송 게이트 변경 — "전체 알림"을 마스터 차단기 → 일괄 스위치 — ✅ 구현 완료(확인)
**왜**: "모든 알림 받기"를 꺼도 개별을 골라 받게 한다(사용자 확정). 지금은 서버가 `allEnabled==false`면 개별 무시하고 전부 막는다.

**변경**: `server/.../global/notification/PushNotifier.java` **line 63·74**
```java
// 변경 전
.map(s -> s.isAllEnabled() && type.isEnabled(s))
// 변경 후 (개별 flag만으로 발송)
.map(s -> type.isEnabled(s))
```
- `all_enabled` 컬럼/DTO는 **그대로 둔다**(프론트가 "개별 전부 ON" 파생값으로 계속 전송). **스키마 변경 없음.**

---

## B. 푸시 문구 교체 (최종 카피) — ✅ 구현 완료(2026-08-09)
모두 서버 하드코딩 문자열. `{ }`는 동적. **제목 / 본문** 2줄.

| 발송 지점 | 제목 (최종) | 본문 (최종) |
|---|---|---|
| **PokeService** (POKE) | `{보낸사람}님이 콕! 👀` | `{방} · 아직 안 끝난 투두 확인해볼까요?` |
| **TodoService** (ASSIGNED_TODO_ADDED) | `새 투두가 도착했어요 📮` | `{방} · {투두제목}` |
| **ScheduleReminderService** (SCHEDULE_DAY_BEFORE) | `내일 일정 미리 알려드려요 📅` | 아래 *일정 본문 규칙* |
| **ScheduleReminderService** (SCHEDULE_DDAY) | `오늘이에요! 일정 잊지 마세요 ⏰` | 아래 *일정 본문 규칙* |
| **RoomService** (ROOM_MEMBER_JOINED) | `새 팀원이 왔어요 🎉` | `{참여자}님이 합류했어요 · {방}` |
| **RoomService** (ROOM_MEMBER_LEFT) | `{나간사람}님이 방을 나갔어요` | `{방}` |
| **ArchiveAnalysisNotifier** (ARCHIVE_ANALYSIS_DONE) | 아래 *자료 분석 제목 규칙* | `모아보기에서 확인해 보세요` (성공 0건이면 `링크는 저장돼 있어요. 모아보기에서 확인해 보세요`) |

**일정 본문 규칙** (⚠️ 현재는 방 이름만 넣음 → **시간·장소 포함으로 변경**):
- 1줄: `{일정제목} · {방이름}`
- 2줄(`\n`): `[시간]·[장소]` 중 **있는 것만** ` · `로 조인. 둘 다 없으면 2줄 생략.
- 시간 포맷: `오전/오후 h시`(분 있으면 `…h시 m분`).
- 예: `정기 회의 · 여름 알고리즘 스터디` / `오후 3시 · 강남역 스터디카페`

**자료 분석 제목 규칙** (건수·성패별):
| 상황 | 제목 |
|---|---|
| 1건 성공 | `「{제목}」 정리 완료 ✨` |
| 1건 실패 | `「{제목}」 못 가져왔어요 😢` |
| 여러 건 전부 성공 | `자료 {N}건 정리 완료 ✨` |
| 여러 건 전부 실패 | `자료 {N}건 못 가져왔어요 😢` |
| 성공+실패 혼합 | `자료 {M}건 완료 · {K}건 실패` |

> 참고: 기존 "콕찌르기"(붙여쓰기)는 새 카피에서 안 쓰이므로 자동 해소. 앱 UI는 "콕 찌르기"로 통일돼 있음.

---

## C. 푸시 `data` 페이로드 추가 (알림 탭 → 화면 이동) — ✅ 구현 완료(2026-08-09, `type`+`roomId`만. `scheduleId`/`todoId`/`archiveItemId`는 프론트 미소비라 보류)
**왜**: 프론트가 알림 탭 시 이동을 구현했는데, 이동 대상 정보가 푸시에 없다(현재 `notification`만, `data` 없음).

**변경**:
1. `PushSender.send(fcmToken, title, body)` → `Map<String,String> data` 인자 추가, `FirebaseCloudMessagingPushSender`에서 `Message.builder()....putAllData(data)`.
2. `PushNotifier.notify/notifyEach`에서 `data`에 **`type=type.name()`을 자동 포함** + 호출부가 넘긴 `roomId` 합침.
3. 각 호출부가 **`roomId`** 전달(가능하면 상세 id도).

**계약** (값은 전부 문자열):
| 키 | 값 | 필수 |
|---|---|---|
| `type` | PushType 이름 (`POKE`/`SCHEDULE_DAY_BEFORE`/`SCHEDULE_DDAY`/`ROOM_MEMBER_JOINED`/`ROOM_MEMBER_LEFT`/`ASSIGNED_TODO_ADDED`/`ARCHIVE_ANALYSIS_DONE`) | ✅ |
| `roomId` | 해당 방 id | ✅ |
| `scheduleId`/`todoId`/`archiveItemId` | 상세 딥링크용(선택, 지금 프론트 미사용) | ⬜ |

프론트 매핑(FYI): POKE·ASSIGNED_TODO_ADDED→투두, SCHEDULE_*→일정, ROOM_MEMBER_*→멤버·초대, ARCHIVE_ANALYSIS_DONE→모아보기. `roomId`로 방 전환 후 이동. **`data` 없으면 앱만 열림(전방 호환, 크래시 없음)** — 타입별 점진 적용 가능.

---

## D. (선택) `knock_enabled` 잔재 정리 — ✅ 구현 완료(2026-08-09, 서버+앱 같은 커밋)
콕찌르기/재촉 통일 후 남은 `notification_settings.knock_enabled` 컬럼·DTO·`PokeType.KNOCK`·CHECK 제약 제거(`V27__drop_knock_enabled.sql`). **실제 위험은 문서가 짚은 요청 DTO `@NotNull` 쪽이 아니라 응답 쪽이었다** — `app/lib/features/settings/settings_screens.dart`가 `json['knockEnabled'] as bool`로 non-null 캐스팅하고 있어, 응답에서 필드를 빼면 구버전 앱이 설정 화면 파싱에서 크래시났다(요청 쪽은 Spring 기본 Jackson 설정이 초과 필드를 조용히 무시해 실제로는 안전했다). 그래서 **앱 모델(`NotificationSettings`)의 `knockEnabled`도 같은 커밋에서 제거**해 배포 순서 문제를 근본적으로 없앴다 — 단, 서버 배포와 앱스토어 배포 사이에 낀 기존 구버전 앱은 여전히 영향받으므로, 실제 배포는 앱 심사 통과 후 서버를 내보내는 순서를 권장.

---

## E. 실제 알림 동작 테스트까지 부탁드려요 (구현 후 검증)
문구·설정 저장은 프론트에서 확인되지만, **실제로 푸시가 규칙대로 발송되는지는 서버에서만 검증 가능**합니다(발송 게이트·문구·data가 전부 서버 쪽). 아래를 **실기기 또는 FCM 테스트 발송으로 end-to-end 확인**해 주세요:

- [ ] **게이트(A)**: 전체 ON → 개별 7종 모두 수신 / **전체 OFF + 개별 일부만 ON → 켠 것만 수신**(핵심 회귀 포인트) / 특정 개별 OFF → 그 타입만 미수신.
- [ ] **문구(B)**: 타입별로 실제 도착 알림의 **제목·본문이 최종 카피와 일치**. 특히 일정은 **시간·장소가 본문에 포함**되는지, 자료 분석은 건수·성패별 5갈래가 맞는지.
- [ ] **딥링크(C)**: 푸시에 `data.type`(+`roomId`)가 **실제로 실려 오는지**(수신 로그/페이로드 확인). 앱 탭 시 이동은 프론트가 검증.
- [ ] 기존 발송 트리거(콕 찌르기·일정 배치·방 입퇴장·담당 투두·자료 분석)가 변경 후에도 정상 발송되는지 회귀 확인.

> 서버에서 발송까지 확인되면 알려주세요. 프론트는 그 시점에 실기기로 수신·표시·탭 이동을 함께 확인하겠습니다.

## 우선순위 — A·B·C·D 전부 완료(2026-08-09), 남은 것은 E뿐
1. ~~**A (게이트)**~~ ✅
2. ~~**B (문구)**~~ ✅
3. ~~**C (딥링크)**~~ ✅
4. ~~**D (정리)**~~ ✅

> A·B·C 반영 완료 — 프론트 실기기 end-to-end 테스트(E) 진행 요청.
