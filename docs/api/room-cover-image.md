# 방 대표 이미지 업로드 — 백엔드 요구사항

프론트(설정·방 생성 화면)가 대표 이미지를 넣을 수 있도록 하는 **2단계 업로드** 계약. FE·백엔드 모두 구현 완료(2026-08-01).

## 왜 2단계인가
방 생성 화면은 방이 아직 없으므로(roomId 없음) 업로드가 방에 묶이면 안 된다. 그래서 **방에 묶이지 않은 범용 업로드 엔드포인트**가 URL만 반환하고, 그 URL을 기존 방 생성/설정의 `coverImage` 문자열 필드로 저장한다.

## 신규 — 이미지 업로드 엔드포인트
```
POST /rooms/cover-image
Authorization: Bearer <Firebase ID Token>
Content-Type: multipart/form-data
  - image: <이미지 파일>   (필드명 "image")
```
- **응답** `201`:
  ```json
  { "coverImage": "https://.../rooms/cover/xxxx.jpg" }
  ```
- **저장(구현 완료)**: 프로필 사진과 동일한 MinIO 인프라를 재사용한다. 단 프로필 사진은 presigned PUT(클라이언트가 직접 업로드)이고, 이 엔드포인트는 **서버가 바이트를 받아 직접 `putObject`**(`RoomCoverImageService`, `ObjectStorage.put`). 오브젝트 키는 `rooms/cover/{UUID}.{ext}`(유저별 고정키가 아니라 업로드마다 새 키 — 방 생성 전 호출이라 방에 묶을 수 없음). MinIO 버킷 정책에 `rooms/cover/*` 공개 읽기를 추가해 반환 URL을 인증 없이 `Image.network`로 로드할 수 있다.
- **검증(서버, 구현 완료)**: 매직바이트로 JPEG/PNG/WEBP 여부를 판별(FE가 explicit Content-Type 파트 헤더를 붙이지 않으므로 `getContentType()`/파일명 확장자는 신뢰하지 않는다) → 미인식 형식·빈 파일은 `400`. **최대 5MB**(`spring.servlet.multipart.max-file-size` + `RoomCoverImageService.MAX_FILE_SIZE_BYTES`) 초과도 `400`.
- 인증: 로그인 필요(Bearer, `FirebaseConfig`가 `/rooms/*`에 이미 필터 등록). 방 멤버십 검사는 불필요(생성 전에도 호출) — 구현도 멤버십 체크 없음.
- MinIO 미설정 환경(로컬/CI, `MINIO_ENDPOINT` 없음)에서는 프로필 사진 업로드와 동일하게 `503`.

## 기존 재사용 — 변경 없음
- `POST /rooms`(방 생성), `PATCH /rooms/{id}`(방 설정)는 **이미 body에 `coverImage` 문자열을 받는다**. FE는 위에서 받은 URL을 그 필드로 전달한다. (설정 저장이 예전엔 `coverImage: null`을 하드코딩했으나 FE에서 제거함 — 이제 실제 값/기존 값을 전송.)

## 별건(이미 전달) — 홈 표시용
- 대시보드 응답 `room.coverImage` 노출(홈 히어로 배경). `docs`/홈 티켓 참고.

## FE 구현 위치(참고)
- 업로드 호출: `app/lib/features/room/room_api.dart` `uploadCoverImage()` → `POST /rooms/cover-image`.
- multipart: `app/lib/features/auth/authenticated_http_client.dart` `sendMultipart()`(Bearer + 401 재시도).
- UI: `app/lib/features/room/room_cover_image_field.dart`(설정·생성 공용).
