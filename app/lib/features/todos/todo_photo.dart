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
/// 탭하면 크게 보기가 열린다(2026-08-25 사용자 확정). 완료·읽기전용 행의 흐림 처리는
/// 행 쪽(`Opacity`)이 담당하므로 여기에는 아무 상태도 없다.
class TodoRowThumbnail extends StatelessWidget {
  const TodoRowThumbnail({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '첨부 사진 크게 보기',
      child: GestureDetector(
        // 목록 행에서 제목·메모 탭은 인라인 편집이다. 썸네일에는 원래 제스처가 없어
        // 여기에만 탭을 붙여도 충돌하지 않는다(2026-08-25 #65).
        behavior: HitTestBehavior.opaque,
        onTap: () => showTodoPhoto(context, url),
        // 사진은 50×40이지만 **탭 영역은 50×44** — design.md §"최소 터치 영역 44×44".
        // 위아래 2씩 투명 여백으로 채운다(2026-08-25 리뷰).
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: SizedBox(
            width: 50,
            height: 40,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: ColoredBox(
                color: AppColors.surfaceSoft,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  // 표시 크기로만 디코드한다(2026-08-24 리뷰) — 없으면 원본(수천 px)이
                  // 통째로 메모리 캐시에 들어가고, 투두 목록은 비가상화 Column이라
                  // 화면 밖 행의 이미지까지 한꺼번에 로드된다.
                  cacheWidth: (50 * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  errorBuilder: (_, _, _) => const _PhotoFallback(size: 20),
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const _PhotoFallback(size: 20),
                ),
              ),
            ),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTodoPhoto(context, url, file: localFile),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox(
          height: 180,
          width: double.infinity,
          child: ColoredBox(color: AppColors.surfaceSoft, child: image),
        ),
      ),
    );
  }
}

/// 사진 크게 보기를 띄운다(2026-08-25 #65 사용자 확정 — "썸네일 누르면 크게보기").
///
/// 하단 네비 위를 덮어야 해서 루트 네비게이터에 올린다(앱의 바텀시트 관례와 같은 이유).
/// 사진이 없으면 아무 일도 하지 않는다.
Future<void> showTodoPhoto(
  BuildContext context,
  String? url, {
  XFile? file,
}) async {
  if (file == null && (url == null || url.isEmpty)) {
    return;
  }
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      // 불투명이라 아래 화면이 offstage 로 내려간다 — 투두 목록은 비가상화 Column 이라
      // 화면 밖 행까지 살아 있어서, 반투명으로 두면 그 전부를 계속 그린다(2026-08-25 리뷰).
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => TodoPhotoViewer(url: url, file: file),
    ),
  );
}

/// 사진 전체 화면 — 검은 바탕에 사진을 **잘리지 않게**(`contain`) 놓고, 손가락으로
/// 확대·이동할 수 있다. 배경을 탭하거나 좌상단 닫기를 누르면 닫힌다.
///
/// 사진 위에 얹는 것은 닫기 버튼뿐이다 — 스크림+텍스트 오버레이는 specs/design.md 가
/// 세 곳 한정으로 못 박아서 여기서 늘리지 않는다.
class TodoPhotoViewer extends StatelessWidget {
  const TodoPhotoViewer({super.key, this.url, this.file});

  final String? url;
  final XFile? file;

  @override
  Widget build(BuildContext context) {
    final localFile = file;
    // 확대해도 뭉개지지 않게 화면 폭의 2배까지 디코드한다. 상한을 안 두면 12MP 사진이
    // 통째로 메모리에 올라온다(2026-08-25 리뷰).
    final cacheWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context) *
                2)
            .round();
    final Widget image = localFile != null
        ? Image.file(
            File(localFile.path),
            fit: BoxFit.contain,
            cacheWidth: cacheWidth,
            errorBuilder: (_, _, _) => const _PhotoFallback(size: 40),
          )
        : Image.network(
            url ?? '',
            fit: BoxFit.contain,
            cacheWidth: cacheWidth,
            errorBuilder: (_, _, _) => const _PhotoFallback(size: 40),
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : const _PhotoFallback(size: 40),
          );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 🔴 InteractiveViewer 가 Center **바깥**이어야 한다. 안쪽에 두면 확대·이동
          // 영역이 사진 상자 크기로 줄어서, 세로 사진의 위아래 검은 여백에서 시작한
          // 손가락 제스처가 먹지 않고 확대한 사진도 그 상자에서 잘린다(2026-08-25 리뷰).
          InteractiveViewer(
            maxScale: 4,
            child: GestureDetector(
              // 사진이든 그 바깥 검은 여백이든 탭하면 닫힌다.
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: Center(child: image),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
            left: AppSpacing.sm,
            child: IconButton(
              key: const ValueKey('todo-photo-close'),
              icon: const Icon(Icons.close, color: AppColors.onPrimary),
              tooltip: '닫기',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
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
