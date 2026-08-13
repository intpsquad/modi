# 백엔드 핸드오프 — 투두 이미지 첨부 → 모아보기 "이미지" 탭 (2026-08-09 기획 확정)

> **2026-08-09 구현 완료.** 아래는 기획 원문 + 확정 계약이다. 실제 코드는
> `domain/todo/service/TodoImageService.java`(+`TodoService`의 `imageUrl` 배선),
> `domain/todo/controller/TodoImageController.java`, `V25__add_image_to_todos.sql`.

> **🔴 2026-08-09 후속 확정 — 아래 "이 기획으로 대체" 문장은 더 이상 유효하지 않다.**
> 사용자 요청으로 폴더 직접 업로드 이미지 자료 경로를 **별도로 신설**했다(대체가 아니라 추가) —
> `archive_items.image_url`(V28), `POST /rooms/{roomId}/archive/items/image/upload-url`,
> `ArchiveItemService.createItem`의 이미지 분기. 지금은 **두 경로가 공존**한다:
> 투두 첨부 이미지(이 문서, 방 전체 피드)와 폴더 직접 업로드 이미지(신규, 폴더 스코프) —
> 자세한 계약은 `docs/backend/archive-image-upload-handoff.md`(부활·갱신됨) 참고. 모아보기
> "이미지" 탭은 이제 두 소스를 섹션으로 나눠 보여준다(`archive_folder_items_screen.dart`
> `_buildImageTab`).

## 기획 (사용자 확정, 2026-08-09)
**투두에 이미지를 첨부하면 모아보기(아카이브)의 "이미지" 탭에 쌓인다.** 폴더 화면(S-25-A)의
링크/텍스트/이미지 3단 탭 중 이미지 탭이 이 피드를 보여준다(목업 제공됨: 2열 그리드, 사진
우상단 핀·우하단 담당자 아바타, 사진 아래 관련 투두 제목).

> ~~기존 `archive-image-upload-handoff.md`(이미지 "자료"를 폴더에 직접 업로드하는 안)는
> 이 기획으로 대체됐다 — 이미지의 출처는 폴더 등록이 아니라 투두 첨부다.~~
> **(2026-08-09 후속으로 이 문장은 철회— 위 상단 노트 참고. 두 경로가 공존한다.)**

## 확정한 계약 (2026-08-09)

| 항목 | 확정 |
|---|---|
| 저장 구조 | **`todos` 컬럼 재활용.** `todos.image_url`(V16, 2026-08-07 롤백으로 매핑만 걷어냈던 죽은 컬럼)을 다시 매핑하고, `image_pinned`·`image_attached_at`만 `V25`로 신규 추가. 투두 1개 = 사진 1장(앱도 1장만 지원). 피드 `id`는 곧 `todoId`다 — 별도 이미지 테이블 없음 |
| 업로드 경로 | **`POST /rooms/{roomId}/todos/image/upload-url`** — 투두 id 없이 발급한다. 앱이 투두를 만들기 **전에** 사진을 먼저 고르는 흐름이라 이 순서가 실제 UX와 맞다. 오브젝트 키는 `todos/{roomId}/{UUID}` |
| 폴더 스코프 | **방 전체 피드**(폴더 무관) — 모든 폴더의 이미지 탭이 같은 목록을 보여준다. FE 선구현과 동일 |
| AI 태깅/요약 | **대상 아님** — 투두 제목이 곧 라벨이다 |
| 삭제 | 사진은 투두에 종속 — 투두 삭제 시 함께 사라지고, 재첨부는 덮어쓰기(재첨부 시 `image_attached_at` 갱신 → 피드 최상단으로 재정렬). **피드에서 단독 삭제 API는 없다**(수정 요청에서 `imageUrl`을 비워 보내면 해제된다) |
| 대표 담당자 | 담당자가 여럿이면 **`userId` 오름차순 첫 번째**. `todo_assignees`에 배정 순서 컬럼이 없어 결정론을 위한 서버 판단 |

## API (구현 완료)

1. **투두 이미지 업로드**: `POST /rooms/{roomId}/todos/image/upload-url` (body 없음) →
   `{ "uploadUrl": "...", "publicUrl": "..." }`. `PUT <uploadUrl>`으로 바이트 직결 후
   `publicUrl`을 투두 생성/수정 요청의 `imageUrl`로 싣는다.
   `TodoResponse.imageUrl` 추가. **`PUT /rooms/{roomId}/todos/{todoId}`은 전체 교체**라
   `imageUrl`을 안 보내면 `dueDate`와 같은 규칙으로 사진이 해제된다.
2. **이미지 피드**: `GET /rooms/{roomId}/archive/todo-images` →
   ```json
   [{ "id": 10, "imageUrl": "...", "todoId": 10, "todoTitle": "...",
      "assignee": { "userId": "...", "nickname": "...", "profileImage": "..." } | null,
      "pinned": false, "createdAt": "..." }]
   ```
   - `id == todoId`.
   - `assignee`는 대표 담당자 1명(미지정 투두면 null, 여럿이면 `userId` 오름차순 첫 번째).
   - 정렬: `pinned desc, image_attached_at desc, id desc`(다른 아카이브 목록과 동일 규칙).
3. **핀 토글**: `PATCH /rooms/{roomId}/archive/todo-images/{todoId}/pin` `{pinned}` —
   자료 핀과 같은 idiom. 사진이 없는 투두 id로 부르면 404.

## FE 배선 상태 (2026-08-09 기준)
- `app/lib/features/archive/archive_api.dart` — `ArchiveTodoImage` 모델 + `fetchTodoImages` +
  `setTodoImagePinned` **선구현 완료, 위 계약과 일치**(그대로 붙는다).
- `archive_folder_items_screen.dart` — 이미지 탭 2열 그리드 **선구현 완료**.
- `app/lib/features/todos/todo_form_sheet.dart`의 사진 첨부는 **여전히 UI만** — `XFile? _image`를
  실제로 업로드(`POST .../todos/image/upload-url` 2단계 패턴, `SettingsApi.uploadProfilePhoto`와
  동일)하고 `imageUrl`을 create/update 요청에 싣는 배선은 **이번 스코프 밖**(후속 프론트 작업).
