import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../design/tokens.dart';

/// 투두 첨부 사진 표시 위젯 2종(2026-08-24, #65 — specs/design.md "투두 탭" 절).
///
/// 폼은 `ArchiveThumbnail`(archive_widgets.dart)과 같다 — 배경 `surface-soft` 를 항상
/// 깔고 로딩/실패 모두 중앙 아이콘 폴백. `DecorationImage` 로 배경에 넣는 방식은
/// 에러 폴백이 없어 금지된 반례다(archive_widgets.dart 머리말, 2026-08-08 리뷰).
/// 아카이브에서 import 하지 않고 여기 두는 이유: 피처 간 위젯 공유 전례가 없고,
/// `TodoPhotoPreview` 가 image_picker 의 `XFile` 을 받아 디자인 계층에 두기도 어색하다.

/// 행 썸네일 — 50×40, `radius.xs`(4). 치수는 specs/design.md 투두 탭 절 확정값.
///
/// 탭 동작 없음 — 확대뷰는 미결(specs/OPEN.md). 완료·읽기전용 행의 흐림 처리는
/// 행 쪽(`Opacity`)이 담당하므로 여기에는 아무 상태도 없다.
class TodoRowThumbnail extends StatelessWidget {
  const TodoRowThumbnail({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 40,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: ColoredBox(
          color: AppColors.surfaceSoft,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            // 표시 크기로만 디코드한다(2026-08-24 리뷰 P2-1) — 없으면 원본(수천 px)이
            // 통째로 메모리 캐시에 들어가고, 투두 목록은 비가상화 Column이라 화면 밖
            // 행의 이미지까지 한꺼번에 로드된다.
            cacheWidth: (50 * MediaQuery.devicePixelRatioOf(context)).round(),
            errorBuilder: (_, _, _) => const _PhotoFallback(size: 20),
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : const _PhotoFallback(size: 20),
          ),
        ),
      ),
    );
  }
}

/// 폼/상세 미리보기 — 폭 전체×180, `radius.card`. 치수는 아카이브 "자료 상세 사진
/// 카드"(specs/design.md §6)와 동일. 스크림 없음 — 이미지 위 오버레이는 design.md 가
/// 세 곳 한정으로 못 박았다.
///
/// [file](새로 고른 로컬 파일)이 있으면 그쪽을 그린다 — 저장 시 업로드되는 것도 그
/// 파일이므로 `_submit` 의 우선순위와 같다. 없으면 [url](기존 첨부)로 그린다.
class TodoPhotoPreview extends StatelessWidget {
  const TodoPhotoPreview({super.key, this.url, this.file});

  final String? url;
  final XFile? file;

  @override
  Widget build(BuildContext context) {
    final localFile = file;
    // 표시 폭(화면 전폭)으로만 디코드한다 — 위 TodoRowThumbnail 의 cacheWidth 와 같은 이유.
    final cacheWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    final Widget image = localFile != null
        ? Image.file(
            File(localFile.path),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            errorBuilder: (_, _, _) => const _PhotoFallback(size: 40),
          )
        : Image.network(
            url ?? '',
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            errorBuilder: (_, _, _) => const _PhotoFallback(size: 40),
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : const _PhotoFallback(size: 40),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: SizedBox(
        height: 180,
        width: double.infinity,
        child: ColoredBox(color: AppColors.surfaceSoft, child: image),
      ),
    );
  }
}

/// 로딩·실패·값 없음 공용 폴백 — surface-soft 면 + 중앙 이미지 아이콘.
/// 아카이브 `_PhotoPlaceholder` 와 같은 모양(아이콘 크기만 자리별로 다르다).
class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(Icons.image_outlined, size: size, color: AppColors.mutedSoft),
    );
  }
}
