import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'archive_api.dart';
import 'crawl_status_badge.dart';

/// 작은 원형 프로필 아바타(기본 24) — 상세 하단 반응 바의 등록자·댓글 시트의 작성자가 공유한다
/// (2026-08-09, 상세 화면 전용 `_AuthorAvatar`를 승격). `surface-strong` 원에 이니셜을 **항상
/// 깔고** 그 위에 사진을 얹는다 — `DecorationImage`로 배경에 넣으면 에러 폴백이 없어서, 프로필
/// URL은 있는데 못 불러올 때 글자도 사진도 없는 빈 회색 원이 남는다(2026-08-08 리뷰 지적).
///
/// [author]가 null이면(탈퇴 작성자) 이니셜 '?'만 그린다 — 자리를 완전히 비울지는 호출부가
/// 정한다(상세 하단 바는 비우고, 댓글 행은 '?'로 남긴다).
class ArchiveAuthorAvatar extends StatelessWidget {
  const ArchiveAuthorAvatar({
    super.key,
    this.author,
    this.size = 24,
    this.semanticsPrefix = '등록자',
  });

  final ArchiveItemCreator? author;
  final double size;

  /// 스크린리더 라벨 접두("등록자"/"작성자" 등).
  final String semanticsPrefix;

  @override
  Widget build(BuildContext context) {
    final nickname = author?.nickname ?? '';
    final image = author?.profileImage;
    final hasImage = image != null && image.isNotEmpty;
    return Semantics(
      label: '$semanticsPrefix ${nickname.isEmpty ? '알 수 없음' : nickname}',
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.surfaceStrong,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Text(
                nickname.isNotEmpty ? nickname[0] : '?',
                style: AppTypography.badge.copyWith(color: AppColors.muted),
              ),
            ),
            if (hasImage)
              Image.network(
                image,
                fit: BoxFit.cover,
                // 실패·로딩 중에는 아래 이니셜이 그대로 보인다.
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

/// 모아보기(아카이브) 공용 썸네일 — 이미지가 있으면 cover로, 없거나 로드 실패면
/// surfaceSoft 배경 + 회색 아이콘 플레이스홀더. specs/0010.
class ArchiveThumbnail extends StatelessWidget {
  const ArchiveThumbnail({
    super.key,
    required this.url,
    this.radius = AppRadius.card,
    this.placeholderIcon = Icons.link,
    this.placeholderIconSize = 32,
  });

  final String? url;
  final double radius;
  final IconData placeholderIcon;
  final double placeholderIconSize;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: AppColors.surfaceSoft,
        child: hasUrl
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, _, _) => _placeholder(),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Center(
    child: Icon(
      placeholderIcon,
      size: placeholderIconSize,
      color: AppColors.muted,
    ),
  );
}

/// AI 태그 칩 — **높이 20 고정**, 연한 회색 채움(#F7F7F7)·무테 + `#8B8B8B` 텍스트.
/// specs/design.md §6(태그 칩), specs/0010.
///
/// 규격(2026-08-08 폴더 자료 카드 리디자인): 높이 20 · 좌우 패딩 8 · `radius.pill` ·
/// **채움 `surface-soft`(#F7F7F7)·테두리 없음** · 라벨 `#…`(디자이너 지정 `#8B8B8B` 12pt medium
/// 톤 — 단 폭 측정 안정성을 위해 렌더는 `badge`(11) 크기·weight 500으로 둔다: 측정은 badge 600
/// 기준이라 실제 렌더가 더 좁아 오버플로 안전). *(폐지: 2026-08-05의 흰 채움 + 1px `border` +
/// `muted-soft` 텍스트.)*
///
/// [onDeleted]가 있으면 라벨 뒤에 X(14px, `color.border-strong`)를 붙인다.
///
/// ⚠️ 이 X는 design.md의 최소 44×44 터치 영역을 **의도적으로 벗어난다**(20px 칩 안에서는
/// 불가능하다). 지정된 치수를 살리는 쪽을 택한 이탈이며 design.md §6에 예외로 적어 뒀다.
class ArchiveTagChip extends StatelessWidget {
  const ArchiveTagChip({super.key, required this.label, this.onDeleted});

  final String label;
  final VoidCallback? onDeleted;

  static const double height = 20;
  static const double _deleteIconSize = 14;
  static const double _horizontalPadding = AppSpacing.sm;

  /// 라벨 색 — 디자이너 지정(#8B8B8B, design.md 팔레트 밖, 이 칩 전용).
  static const Color _labelColor = Color(0xFF8B8B8B);

  /// 텍스트 외 고정 폭 — [SingleLineChips]가 폭을 미리 재는 데 쓴다.
  /// 좌우 패딩 + (삭제 아이콘). **테두리가 없어졌으므로 border 보정(+2)은 빼야 한다.**
  static double extraWidthFor({required bool deletable}) =>
      _horizontalPadding * 2 +
      (deletable ? AppSpacing.xxs + _deleteIconSize : 0);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$label',
            style: AppTypography.badge.copyWith(
              fontWeight: FontWeight.w500,
              color: _labelColor,
            ),
          ),
          if (onDeleted != null) ...[
            const SizedBox(width: AppSpacing.xxs),
            GestureDetector(
              onTap: onDeleted,
              child: const Icon(
                Icons.close,
                size: _deleteIconSize,
                color: AppColors.borderStrong,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// [SingleLineChips]에 넣을 칩 하나 — **자기 폭을 계산할 재료**를 함께 들고 있다.
///
/// 폭을 미리 알아야 "들어가는 것만" 만들 수 있다. 그리지 않을 칩을 트리에 남겨 두는 방식
/// (`Flow`로 일부만 페인트)도 되지만, 그러면 화면에 없는 칩이 위젯 트리·시맨틱스에 남아
/// 스크린리더가 읽고 테스트도 존재 여부로 구분하지 못한다.
class ChipSpec {
  const ChipSpec({
    required this.text,
    required this.extraWidth,
    required this.build,
  });

  /// 태그 칩 — 규격은 [ArchiveTagChip]과 같아야 한다(아래 폭 상수도 그 위젯에서 가져온다).
  factory ChipSpec.tag(String label, {VoidCallback? onDeleted}) => ChipSpec(
    text: '#$label',
    extraWidth: ArchiveTagChip.extraWidthFor(deletable: onDeleted != null),
    build: () => ArchiveTagChip(label: label, onDeleted: onDeleted),
  );

  /// 분석 상태 배지 — 태그와 같은 줄에 온다(2026-08-05 요청).
  factory ChipSpec.crawlStatus(String status) => ChipSpec(
    text: CrawlStatusBadge.labelFor(status),
    extraWidth: CrawlStatusBadge.extraWidth,
    build: () => CrawlStatusBadge(status: status),
  );

  /// 폭 계산에 쓰는 텍스트(`badge` 스타일로 잰다).
  final String text;

  /// 텍스트 외 고정 폭 — 좌우 패딩, 삭제 아이콘 등.
  final double extraWidth;

  final Widget Function() build;
}

/// 자료 목록의 칩 줄 — **항상 한 줄**이고, 다 못 들어가면 끝에 `…`를 붙인다
/// (2026-08-05 요청: "칩이 2줄이 되면 안돼. 한줄 넘어가면 ...으로 표기").
///
/// `Wrap`은 두 줄로 흐르고 `Row`는 넘치면 오버플로 경고를 낸다. 그래서 폭을 직접 재서
/// 들어가는 칩만 만든다 — 잘린 칩은 트리에 아예 없다(시맨틱스·히트테스트도 깨끗하다).
class SingleLineChips extends StatelessWidget {
  const SingleLineChips({
    super.key,
    required this.chips,
    this.spacing = AppSpacing.xs,
    this.height = ArchiveTagChip.height,
  });

  final List<ChipSpec> chips;
  final double spacing;
  final double height;

  static const String ellipsis = '…';

  /// 칩 하나당 더해 두는 여유 폭.
  ///
  /// 🔴 **추정은 반드시 상한이어야 한다.** [textWidth]의 `TextPainter` 측정값이 실제로 렌더된
  /// `Text`보다 조금 작게 나온다(실측 1.25px). 과소평가하면 마지막 칩이 줄을 넘어 `Row`
  /// 오버플로 경고가 뜬다. 반대로 살짝 과대평가하면 아주 드물게 칩 하나가 일찍 `…`로
  /// 넘어갈 뿐이라, 그쪽으로 기울인다.
  static const double slack = 4;

  /// `badge` 스타일로 [text]의 렌더 폭을 잰다. 칩 위젯이 쓰는 스타일과 같아야 한다 —
  /// 어긋나지 않는지는 테스트가 "추정 ≥ 실제, 단 과하지 않게"로 확인한다.
  static double textWidth(String text, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: AppTypography.badge),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final widths = [
          for (final chip in chips)
            textWidth(chip.text, scaler) + chip.extraWidth + slack,
        ];
        final ellipsisWidth = textWidth(ellipsis, scaler);

        /// 오른쪽을 [reserve]만큼 비워 두고 앞에서부터 몇 개가 들어가는지.
        int fitCount(double reserve) {
          var used = 0.0;
          var count = 0;
          for (final w in widths) {
            final next = count == 0 ? w : used + spacing + w;
            if (next > maxWidth - reserve) break;
            used = next;
            count++;
          }
          return count;
        }

        // 먼저 말줄임 없이 다 들어가는지 본다 — 자리가 남으면 `…`를 붙이지 않는다.
        var count = fitCount(0);
        var truncated = false;
        if (count < chips.length) {
          count = fitCount(spacing + ellipsisWidth);
          truncated = true;
        }

        return SizedBox(
          height: height,
          child: Row(
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                chips[i].build(),
              ],
              if (truncated) ...[
                if (count > 0) SizedBox(width: spacing),
                Text(
                  ellipsis,
                  style: AppTypography.badge.copyWith(
                    color: AppColors.mutedSoft,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
