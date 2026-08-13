import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../room/default_cover.dart';
import 'home_api.dart';

/// 홈 아카이브 미리보기 캐러셀 — specs/0005-홈-대시보드.md.
/// 가로 스크롤(카드 단위 Snap) + 16px 라운딩 텍스트 오버레이 카드.
class ArchiveCarousel extends StatelessWidget {
  const ArchiveCarousel({
    super.key,
    required this.items,
    required this.onTapItem,
  });

  final List<ArchiveBrief> items;
  final void Function(ArchiveBrief item) onTapItem;

  static const double _cardWidth = 168;
  static const double _cardHeight = 132;
  static const double _gap = AppSpacing.cardGap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const _SnapScrollPhysics(itemExtent: _cardWidth + _gap),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: _gap),
        itemBuilder: (context, index) {
          final item = items[index];
          return _ArchiveOverlayCard(
            item: item,
            width: _cardWidth,
            onTap: () => onTapItem(item),
          );
        },
      ),
    );
  }
}

class _ArchiveOverlayCard extends StatelessWidget {
  const _ArchiveOverlayCard({
    required this.item,
    required this.width,
    required this.onTap,
  });

  final ArchiveBrief item;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumbnail = item.thumbnail;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox(
          width: width,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 썸네일 또는 **기본 커버**(2026-08-05 요청 — 회색 채움만 두면 빈 카드처럼 보였다).
              // 커버는 항목 id로 정해진다: 리빌드마다 무작위로 뽑으면 스크롤할 때 깜빡인다.
              if (thumbnail != null && thumbnail.isNotEmpty)
                Image.network(
                  thumbnail,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _DefaultCover(seed: item.id),
                )
              else
                _DefaultCover(seed: item.id),
              // 텍스트 가독성용 하단 스크림.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x99000000)],
                    stops: [0.45, 1.0],
                  ),
                ),
              ),
              // 핀/좋아요 뱃지.
              if (item.pinned || item.likeCount > 0)
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: Row(
                    children: [
                      if (item.pinned)
                        const Icon(
                          Icons.push_pin,
                          size: 14,
                          color: AppColors.onPrimary,
                        ),
                      if (item.likeCount > 0) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.favorite,
                          size: 14,
                          color: AppColors.onPrimary,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${item.likeCount}',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              // 제목 오버레이.
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Text(
                  item.title,
                  style: AppTypography.title.copyWith(
                    color: AppColors.onPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 카드 단위 Snap 물리 — itemExtent(카드폭+간격) 배수에 정착시킨다.
class _SnapScrollPhysics extends ScrollPhysics {
  const _SnapScrollPhysics({required this.itemExtent, super.parent});

  final double itemExtent;

  @override
  _SnapScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnapScrollPhysics(itemExtent: itemExtent, parent: buildParent(ancestor));

  double _targetPixels(ScrollMetrics position, double velocity) {
    final tol = toleranceFor(position);
    var page = position.pixels / itemExtent;
    if (velocity < -tol.velocity) {
      page -= 0.5;
    } else if (velocity > tol.velocity) {
      page += 0.5;
    }
    return (page.roundToDouble() * itemExtent).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tol = toleranceFor(position);
    final target = _targetPixels(position, velocity);
    if ((target - position.pixels).abs() < tol.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tol,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// 썸네일이 없을 때 채우는 기본 커버 — `assets/images/covers/` 다섯 장 중 [seed]로 정해진 한 장.
/// 에셋 로드가 실패하면 원래의 옅은 채움으로 되돌아간다(카드가 검게 비지 않게).
class _DefaultCover extends StatelessWidget {
  const _DefaultCover({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      defaultCoverAsset(seed),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) =>
          const ColoredBox(color: AppColors.surfaceStrong),
    );
  }
}
