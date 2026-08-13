# 📮 백엔드 요청서 — 미착수 작업 전체 정리 (2026-08-09)

프론트에서 이미 각 건별로 핸드오프 문서를 드렸는데, 아직 서버에 반영 안 된 것만 모아 우선순위순으로 정리했습니다. 각 항목은 링크된 상세 문서에 배경·근거가 더 있습니다. **이미 완료된 항목(알림 발송 게이트, 활동 피드, 협업 캐릭터, 콕 중복 제거 등)은 이 문서에 없습니다** — 새로 확인하실 필요 없습니다.

> **2026-08-09 — 1~4순위 전부 구현 완료.** 서버 테스트 750건·Flutter 테스트 600건 전체 통과. 상세는
> 각 절과 링크된 핸드오프 문서 참고.

---

## ✅ 1순위 — 투두 `important`·`imageUrl` 필드 복원 (완료)

**왜 급한가**: 프론트 투두 추가 폼에 "중요 표시" 토글과 "이미지 추가" UI가 **이미 배포돼 있는데**, 저장이 전혀 안 됩니다. 사용자가 체감하는 버그입니다(2026-08-07에 다른 이유로 걷어냈던 필드들).

**요청**:
1. ~~`todos`에 `important` 컬럼...~~ **2026-08-09 구현 완료** — `important BOOLEAN NOT NULL DEFAULT FALSE`(`V26`, V16의 `flagged`와는 별개 신규 컬럼) + `TodoResponse.important` + 생성/수정 API 바디 `important`(옵션, 기본 false). **정렬·필터는 요청서 범위 밖이라 반영 안 함.**
2. ~~투두 이미지 첨부 1장~~ **2026-08-09 구현 완료(`dev` 반영, 커밋 `75a1e14`)** — `POST /rooms/{roomId}/todos/image/upload-url`(투두 id 없이 발급, 이 항목 아래 `todo-form-handoff.md`가 제안한 경로 그대로. 위에 적힌 `{todoId}` 포함 경로는 이 요청서의 오타였다) → `{uploadUrl, publicUrl}`. `todos.image_url`(V16 죽은 컬럼 재매핑) + `image_pinned`/`image_attached_at` 신규 컬럼(`V25`) + `TodoResponse.imageUrl` + 생성/수정 바디 `imageUrl`(PUT은 전체 교체 — 생략 시 해제). 상세는 아래 갱신된 "AI/기획 판단 필요" 절 참고 — 그 항목도 같은 커밋으로 완료됨.
3. `imageUrl`·`important` 둘 다 생겼으니 투두 탭 행 인라인 썸네일(50×40)·확대 뷰·중요 토글 실제 저장까지 프론트가 바로 붙일 수 있습니다. **필드는 준비됨 — 프론트 배선은 여전히 남음.**

상세: `docs/backend/todo-form-handoff.md`, `docs/backend/todo-image-archive-handoff.md`

---

## ✅ 2순위 — 자료 댓글 수정·삭제 (완료)

**왜**: 조회·작성 API는 이미 배포돼 실동작 중인데, "내 댓글 수정·삭제"가 사용자 확정 요구사항으로 새로 생겼습니다(append-only로 설계됐던 걸 바꾸는 요청).

**요청 → 결과**:
1. ~~`PATCH .../comments/{commentId}`~~ **구현 완료** — 본문 수정 `{body}`(검증은 작성과 동일: 공백 불가·500자).
2. ~~`DELETE .../comments/{commentId}`~~ **구현 완료** — 204.
3. **권한은 작성자 본인만.** 아니면 403(`NotCommentAuthorException`). 탈퇴한 작성자(author null)의 댓글은 아무도 수정·삭제 못함. 다른 자료의 댓글 id로 접근하면 404.
4. (선택) `updatedAt`/`edited` 플래그는 **넣지 않았음** — 요청서가 선택 사항으로 명시했고 스키마 변경 없이 끝낼 수 있는 쪽을 택함. 필요해지면 별도 요청 주세요.

상세: `docs/backend/archive-comments-handoff.md`

---

## ✅ 3순위 — 알림 문구 교체 + 푸시 딥링크 `data` (완료)

**같이 처리하면 좋은 이유**: 둘 다 같은 지점(`PushNotifier.notify`/`notifyEach`와 5개 호출부)을 건드립니다. 방금 알림 내역 기능 작업으로 그 지점에 `Room room` 파라미터를 이미 한 번 추가해뒀어서, 지금 손대면 두 번 건드리는 걸 한 번으로 줄일 수 있습니다.

**3-1. 문구 교체 → 전부 최종 카피로 교체 완료**:

| 지점 | 현재 | 최종 카피 |
|---|---|---|
| `PokeService.java` | `"{}님의 콕찌르기"` / `"{방} 방에서 투두를 확인해보세요"` | `"{보낸사람}님이 콕! 👀"` / `"{방} · 아직 안 끝난 투두 확인해볼까요?"` |
| `TodoService.notifyNewAssignees` | `"{}님이 담당 투두를 추가했어요"` | `"새 투두가 도착했어요 📮"` (본문은 이미 `{방} · {제목}`로 일치) |
| `RoomService`(입장) | `"{}님이 방에 들어왔어요"` / 방이름 | `"새 팀원이 왔어요 🎉"` / `"{참여자}님이 합류했어요 · {방}"` |
| `RoomService`(퇴장) | `"{}님이 방에서 나갔어요"` | 그대로 유지(어미만 통일 확인) |
| `ScheduleReminderService` | `"오늘/내일 일정: {제목}"` / 방이름만 | 제목 고정 카피(📅/⏰) + 본문에 **시간·장소 조합 규칙** 추가 |
| ~~`ArchiveAnalysisNotifier`~~ | ~~`"「{}」 분석이 끝났어요"` 등~~ | **✅ 완료(2026-08-09, 이 표의 이모지 제안과 다르게 확정)** — 1건 성공은 제목 고정 문구 `"AI로 자료 분석이 끝났어요"` + 본문 `"{자료 제목}의 내용을 {방 이름} 모아보기에서 확인해보세요"`. 1건 실패·여러 건은 기존 규칙 유지. 상세: `specs/0015-알림-트리거.md` §자료 분석 완료·실패 |

**3-2. 푸시 `data` 페이로드 → 구현 완료** — `type`(항상)+`roomId`(방 컨텍스트 있을 때만)만 실었습니다. `scheduleId`/`todoId`/`archiveItemId`는 두 문서 모두 "지금 프론트 미사용"이라 명시해 스코프에서 뺐습니다(필요해지면 요청 주세요). `ARCHIVE_ANALYSIS_DONE`은 방 컨텍스트가 없는 알림이라(`room=null`) `data`엔 `type`만 실립니다.

상세: `docs/backend/notification-handoff.md`, `docs/backend/notification-deeplink-handoff.md`

---

## ✅ 4순위 (선택) — `knock_enabled` 잔재 정리 (완료)

콕찌르기/재촉이 통일된 지 오래됐는데 `notification_settings.knock_enabled` 컬럼·DTO·`PokeType.KNOCK`이 안 지워져 있었습니다. **`V27__drop_knock_enabled.sql`로 전부 제거했습니다.** 조사해보니 원래 우려하신 위험(요청 DTO `@NotNull`이라 옛 앱이 400)은 Spring 기본 설정상 실제로는 문제없었고, **진짜 위험은 반대쪽**이었습니다 — 앱이 응답의 `knockEnabled`를 non-null로 캐스팅하고 있어 필드를 빼면 구버전 앱이 설정 화면에서 크래시났습니다. 그래서 **앱 모델도 같은 커밋에서 정리**해 배포 순서 문제 자체를 없앴습니다(다만 서버·앱스토어 배포 사이에 낀 기존 구버전은 여전히 영향받으니, 앱 심사 통과 후 서버 배포를 권장드립니다).

상세: `docs/backend/notification-handoff.md` §D, `specs/OPEN.md`

---

## ⚪ AI/기획 판단 필요 (서버 코드 작업 아님)

- **자료 상세 AI 요약 서식** — 지금 요약이 서식 없는 평문 한 덩어리라 읽기 어렵다는 디자인 피드백. 문장 사이 단락 구분자(`\n\n`)를 프롬프트가 넣게 할지, 마크다운 강조를 허용할지 AI/서버 팀 판단 필요. 상세: `docs/backend/archive-summary-formatting-handoff.md`
- ~~**투두 이미지 → 모아보기 "이미지" 탭 피드**~~ **2026-08-09 구현 완료** — `GET /rooms/{roomId}/archive/todo-images`(방 전체·폴더 무관, 핀 우선→최신 첨부순) + `PATCH .../todo-images/{todoId}/pin`. 프론트 선구현 계약과 그대로 일치. 상세: `docs/backend/todo-image-archive-handoff.md`

---

## 참고 — 구현 확인 방법 (재현용, 전부 구현 완료 후 기준으로 갱신)
- 문구: `PokeService.java`·`TodoService.java`(`notifyNewAssignees`)·`RoomService.java`(`joinRoom`/`leaveRoom`)·`ScheduleReminderService.java`·`ArchiveAnalysisNotifier.java`의 문자열 리터럴 — 전부 최종 카피로 교체됨.
- `data` 페이로드: `global/notification/PushSender.java`(`Map<String,String> data` 인자 추가됨), `FirebaseCloudMessagingPushSender.java`(`.putAllData(data)`), `PushNotifier.java`의 `data(PushType, Room)` 헬퍼.
- `important`/`imageUrl`: `domain/todo/entity/Todo.java`에 필드 있음(`V26`/`V25`).
- 댓글 수정/삭제: `ArchiveCommentController.java`에 PATCH/DELETE 추가됨, `domain/archive/exception/{ArchiveCommentNotFoundException,NotCommentAuthorException}.java` 신규.
- `knock_enabled`: `server/src/main/resources/db/migration/V27__drop_knock_enabled.sql`, `app/lib/features/settings/settings_screens.dart`의 `NotificationSettings`에서 필드 제거됨.
