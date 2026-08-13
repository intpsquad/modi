# 백엔드 핸드오프 — 자료 상세 댓글 기능 (2026-08-08 디자인 · 2026-08-09 갱신 · 2026-08-09 수정/삭제 구현 완료)

모아보기 자료 상세(S-25-B) 하단 반응 영역의 댓글 기능.

## ✅ 완료된 것 (2026-08-09, 조회·작성·수정·삭제 전부 서버 구현 완료)
- `archive_item_comments` 테이블(`V23`) — `body VARCHAR(500)`, `author_user_id ON DELETE SET NULL`, `(item_id, created_at)` 인덱스.
- `GET /rooms/{roomId}/archive/items/{itemId}/comments` — 오래된순(ASC) 전체 목록, 응답 `{id, author{userId,nickname,profileImage}|null, body, createdAt}`.
- `POST .../comments` — 201, `{body}` (공백 400 "댓글을 입력해 주세요", 500자 초과 400 "댓글이 너무 길어요").
- **`PATCH /rooms/{roomId}/archive/items/{itemId}/comments/{commentId}`** — 본문 수정 `{body}`, 검증은 작성과 동일. 성공 시 갱신된 댓글 응답.
- **`DELETE .../comments/{commentId}`** — 204.
- **권한: 작성자 본인만** — 아니면 403(`NotCommentAuthorException`). 탈퇴한 작성자(author null)의 댓글은 본인 확인이 불가능해 아무도 수정·삭제할 수 없다. 다른 자료의 댓글 id로 접근하면 404(`ArchiveCommentNotFoundException`).
- `updated_at`/`edited` 플래그는 **넣지 않았다** — 요청서가 선택 사항으로 명시했고 FE도 아직 요구하지 않아, 스키마 변경 없이 끝낼 수 있는 쪽을 택했다(필요해지면 별도 마이그레이션으로 후속).
- `ArchiveItemDetailResponse.commentCount`.
- **프론트도 연결 완료(2026-08-09)** — 하단 반응 바 댓글 아이콘+카운트, 댓글 바텀시트(목록/작성).

## FE 후속 (서버는 끝났고 이제 FE 차례)
- 댓글 행에 **본인 댓글 한정** 수정/삭제 액션 UI를 붙인다 — 위 PATCH/DELETE 그대로 붙으면 된다.

## 화면 스펙 (구현 반영됨 — `app/lib/features/archive/archive_comments_sheet.dart`)
바텀시트(`showModalBottomSheet`, `useRootNavigator: true`): 딤 + 드래그 핸들 + 타이틀 "댓글"(`section`) + 목록(아바타 36 + 닉네임 + 본문 전체 표시, 오래된순=새 댓글이 아래) + 하단 입력바(내 아바타 + 둥근 필드 "댓글을 입력해주세요.", 키보드 액션으로 전송). 탈퇴 작성자는 '?' 아바타 + "(알 수 없음)".
