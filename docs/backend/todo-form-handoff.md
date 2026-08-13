# 투두 추가 폼 — 백엔드 핸드오프 (중요·이미지)

> 작성: 2026-08-08 (프론트) · 대상: 백엔드
> 관련: `specs/0006-투두-탭.md`, 앱 `app/lib/features/todos/todo_form_sheet.dart`(리디자인)
>
> **2026-08-09 구현 완료 — 아래 두 요청 모두 백엔드 반영됨.** `important BOOLEAN NOT NULL DEFAULT false`(`V26`,
> `flagged`(V16)와는 별개의 새 컬럼) + `imageUrl`(`todos.image_url`, V16 죽은 컬럼 재매핑 + `V25`의
> `image_pinned`/`image_attached_at`) 둘 다 `TodoResponse`·생성/수정 API 바디에 포함됐다. 이미지 업로드
> URL 발급·모아보기 이미지 탭 피드는 `docs/backend/todo-image-archive-handoff.md` 참고. **앱 쪽 배선
> (실제 저장 연결, 행 인라인 썸네일)은 아직 안 됐다** — 필드는 준비됐다.

## 배경
투두 추가 바텀시트를 재디자인하면서 디자인 시안에 **중요(토글)** 와 **이미지 추가** 요소가 포함됐다.
그러나 현재 `createTodo`(`POST /rooms/{roomId}/todos`)에는 두 필드가 **없다**(2026-08-07 롤백으로 제거됨).
그래서 앱은 두 요소를 **UI만** 붙이고 **저장하지 않는 로컬 상태**로 뒀다 — 백엔드가 필드를 다시
지원해야 실제로 저장된다.

## 요청 (둘 다 프론트가 이미 UI는 준비됨 → 백엔드 필드만 있으면 바로 연결)

### 1. 중요 표시 (important)
- `todos`에 `important BOOLEAN NOT NULL DEFAULT false` 컬럼(새 Flyway 마이그레이션).
- `TodoResponse`에 `important` 포함.
- 생성/수정 API 요청 바디에 `important`(옵션, 기본 false) 추가:
  - `POST /rooms/{roomId}/todos`
  - `PUT /rooms/{roomId}/todos/{todoId}`
- (선택) 목록 정렬·필터에 중요 반영할지는 별도 논의 — 이번 요청은 저장/반환까지.

### 2. 이미지 첨부 (image)
- 투두당 이미지 1장 첨부. 방 커버·프로필과 같은 **presigned PUT 업로드 → 공개 URL 저장** 패턴 재사용 제안.
  - 예: `POST /rooms/{roomId}/todos/image/upload-url` → `{uploadUrl, publicUrl}` (MinIO `todos/` 접두사)
  - `todos.image_url TEXT NULL` 컬럼 + `TodoResponse.imageUrl` + 생성/수정 바디 `imageUrl`(옵션).
- 앱은 이미 `image_picker`로 로컬 선택까지 구현돼 있고(`todo_form_sheet.dart`의 `_pickImage`), 업로드 엔드포인트가 생기면 방 커버(`room_cover_image_field.dart`)와 동일한 2단계 업로드로 연결한다.
- **2026-08-09 추가 — 투두 탭 행 인라인 표시**: `imageUrl`이 생기면 투두 탭 행(`_TodoListRow`)에서 제목/메모 아래에 **썸네일 50×40, `radius` 4**로 보여주고(요구 1), 탭하면 **확대 뷰 → 다시 탭 원복**(요구 4)을 붙인다. 지금은 `TodoItem.imageUrl` 필드가 없어 행 인라인 사진 자체가 미구현 상태(제목/메모 인라인 편집만 로 완료). 필드만 오면 표시/확대는 프론트에서 바로 추가.

## 확정되면 앱 쪽 변경(참고)
- `createTodo`/`updateTodo` 시그니처에 `important`·`imageUrl` 추가 → `_submit`에서 전달.
- 현재 로컬 상태(`_important`, `_image`)를 그대로 실제 저장에 연결(추가 UI 작업 없음).

## 스펙 갱신 필요
- `specs/0002-data-model.md`(todos 컬럼·ERD), `specs/0006-투두-탭.md`(폼 필드), OpenAPI 재생성.
