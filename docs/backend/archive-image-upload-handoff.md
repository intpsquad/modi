# 백엔드 핸드오프 — 모아보기 이미지 자료 (2026-08-08 기획, 2026-08-09 구현 완료)

> **2026-08-09 구현 완료.** 아래는 원래 열려 있던 질문에 대한 확정 답 + 구현된 계약이다. 실제 코드는
> `domain/archive/service/ArchiveItemService.java`(`createItem` 이미지 분기, `createImageUploadUrl`),
> `domain/archive/controller/ArchiveItemController.java`, `domain/archive/entity/ArchiveItem.java`
> (`imageUrl` 필드 + `imageDone` 팩토리), `V28__add_image_url_to_archive_items.sql`.

모아보기 폴더 화면(S-25-A)의 "이미지" 라인 탭에 사용자가 **폴더에 직접 사진을 올릴 수 있다** —
투두에 사진을 첨부하면 쌓이는 기존 경로(`docs/backend/todo-image-archive-handoff.md`, 방 전체
피드)와는 **별개의, 폴더 스코프 경로**다(2026-08-09 사용자 확정 — "별도 이미지 자료 경로 신설").
두 경로는 공존하며, 모아보기 이미지 탭은 두 소스를 섹션으로 나눠 보여준다("이 폴더에 올린 사진" /
"투두에 첨부된 사진").

## 열려 있던 질문 → 확정 답 (2026-08-09)

| 질문 | 확정 |
|---|---|
| 업로드인가, 이미지 URL 붙여넣기인가? | **업로드**(갤러리/카메라). 투두 이미지·프로필 사진과 같은 presigned PUT 2단계 패턴 |
| 저장소 | **MinIO**(`ObjectStorage`), 기존 인프라 재사용. 오브젝트 키 `archive/images/{roomId}/{UUID}`(2026-08-10 수정 — 원래 `archive-images/`였으나 `MinioConfig`의 공개 읽기 정책이 `archive/*`만 허용해 업로드는 성공하고 조회만 403이 나는 버그가 있었다. `archive/` 하위로 옮겨 기존 정책을 그대로 재사용) |
| AI 태깅/요약 대상인가? | **대상 아님** — 투두 첨부 이미지와 같은 원칙. 등록 즉시 `crawlStatus=DONE`, 크롤러·요약기·임베더·태깅 클라이언트를 전혀 타지 않는다 |
| `archive_items`에 종류 컬럼 추가 vs. 별도 테이블? | **`archive_items` 재사용**, 종류 컬럼은 추가하지 않음. 기존 관례(`url != null` → 링크, `url == null` → 텍스트)를 그대로 확장해 `image_url != null` → 이미지. 셋 중 정확히 하나만 채워진다 |
| 개수 제한 | 링크/텍스트 자료와 동일 — 폴더당 무제한(다른 자료 종류와 같은 규칙, 별도 상한 없음) |

## 확정한 계약

| 항목 | 확정 |
|---|---|
| 저장 구조 | `archive_items.image_url`(V28, nullable VARCHAR(2048)) 신규 컬럼. 별도 이미지 테이블 없음 — 핀·좋아요·댓글·태그·삭제·폴더이동이 링크/텍스트 자료와 완전히 같은 인프라를 그대로 쓴다 |
| 업로드 경로 | `POST /rooms/{roomId}/archive/items/image/upload-url` — 폴더 id 없이 방 스코프로 발급(투두 업로드 URL과 같은 이유: 앱이 사진을 먼저 고르는 흐름) |
| 등록 경로 | 기존 `POST /rooms/{roomId}/archive/folders/{folderId}/items`를 그대로 쓴다. `CreateArchiveItemRequest`에 `imageUrl`(업로드로 받은 공개 URL)·`title`(선택, 이미지 자료 전용) 필드 추가 |
| 제목 | 사용자가 비우면 서버가 `"사진"`으로 기본값을 채운다(링크가 URL로 프리필되는 것과 같은 원칙) |
| 폴더 스코프 | 등록한 폴더에만 속한다(링크/텍스트와 동일) — 투두 첨부 이미지(방 전체 피드)와 스코프가 다르다는 점이 핵심 차이 |
| AI 태깅/요약/임베딩 | 대상 아님 — `imageUrl`이 채워지면 `dispatchCrawl`을 아예 호출하지 않는다 |
| 핀/삭제/폴더이동/댓글/태그 | 링크/텍스트 자료와 완전히 동일한 엔드포인트(`/rooms/{roomId}/archive/items/{itemId}/...`)를 그대로 쓴다 — 별도 API 없음 |

## API

1. **업로드 URL 발급**: `POST /rooms/{roomId}/archive/items/image/upload-url` (body 없음) →
   `{ "uploadUrl": "...", "publicUrl": "..." }`(`ArchiveImageUploadUrlResponse`). `PUT <uploadUrl>`로
   바이트 직결 후 `publicUrl`을 자료 등록 요청의 `imageUrl`로 싣는다.
2. **자료 등록**: `POST /rooms/{roomId}/archive/folders/{folderId}/items`
   `{ "imageUrl": "...", "title": "..." (선택) }` — `url`/`text`/`imageUrl` 중 정확히 하나만 채워야
   한다(그 외는 400). 응답(`ArchiveItemDetailResponse`)에 `imageUrl` 필드 포함, `crawlStatus`는
   즉시 `"DONE"`.
3. **목록 조회**: 기존 `GET /rooms/{roomId}/archive/folders/{folderId}/items` 응답
   (`ArchiveItemResponse`)에 `imageUrl` 필드가 추가됐다 — 링크/텍스트 자료는 `null`.
4. **핀/삭제/폴더이동 등**: 기존 자료 엔드포인트 그대로(`itemId` 기준) — 신규 없음.

## FE 배선 상태 (2026-08-09 기준)
- `app/lib/features/archive/archive_api.dart` — `ArchiveItem.imageUrl`, `ArchiveItemDetail.imageUrl`,
  `createItem(imageUrl:, title:)`, `uploadArchiveImage` **구현 완료**.
- `archive_item_register_sheet.dart` — `ArchiveRegisterMode.image`(사진 선택 박스 + 선택적 제목
  입력) **구현 완료**.
- `archive_folder_items_screen.dart` — ＋ 버튼 "이미지 추가"가 등록시트를 이미지 모드로 열고,
  이미지 탭이 "이 폴더에 올린 사진"(신규)/"투두에 첨부된 사진"(기존) 두 섹션으로 렌더 **구현 완료**.
