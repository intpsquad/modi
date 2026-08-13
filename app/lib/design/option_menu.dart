import 'package:flutter/material.dart';

import 'tokens.dart';

/// 옵션창 한 항목 — specs/design.md §6.
class OptionMenuItem<T> {
  const OptionMenuItem({
    required this.label,
    required this.value,
    this.icon,
    this.danger = false,
  });

  final String label;
  final T value;

  /// 있으면 라벨 왼쪽에 20px로 그린다. 한 메뉴 안에서 아이콘 유무를 섞지 않는 편이 좋다.
  final IconData? icon;

  /// 삭제처럼 되돌리기 어려운 항목 — `accent-danger`로 그린다.
  final bool danger;
}

/// **누른 버튼 바로 아래**에 옵션창을 띄운다(2026-08-05 사용자 확정).
///
/// [anchorKey]는 트리거 위젯(⋯·⋮ 버튼)의 `GlobalKey`다 — 그 사각형을 기준으로 위치를 잡아
/// "어떤 항목의 옵션인지"가 위상으로 드러난다. 화면 아래쪽 버튼이면 위로 뒤집는다.
///
/// 뒷배경은 `scrim` 40% + 바깥 탭으로 닫힘(투두 탭 ⋮ 더보기가 쓰던 패턴을 일반화했다).
/// 고른 값을 돌려주고, 바깥을 탭해 닫으면 null이다.
Future<T?> showOptionMenu<T>({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<OptionMenuItem<T>> items,
  bool preferAbove = false,
}) {
  final anchorBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(
            context,
            rootNavigator: true,
          ).overlay!.context.findRenderObject()!
          as RenderBox;
  // 앵커를 못 찾으면(트리거가 이미 사라졌다면) 화면 우상단으로 폴백한다.
  final anchor = anchorBox == null
      ? Rect.fromLTWH(overlay.size.width - 48, 0, 48, 48)
      : Rect.fromPoints(
          anchorBox.localToGlobal(Offset.zero, ancestor: overlay),
          anchorBox.localToGlobal(
            anchorBox.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        );

  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: '옵션 닫기',
    barrierColor: AppColors.scrim.withValues(alpha: 0.4),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, _, _) => _OptionMenuLayer<T>(
      anchor: anchor,
      overlaySize: overlay.size,
      items: items,
      preferAbove: preferAbove,
    ),
    transitionBuilder: (context, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

/// 앵커 기준으로 카드를 배치하는 층. 카드 높이를 미리 알 수 없어 `CustomSingleChildLayout`
/// 으로 **실측 뒤** 위치를 정한다(아래로 넘치면 위로 뒤집기 때문에 높이가 필요하다).
class _OptionMenuLayer<T> extends StatelessWidget {
  const _OptionMenuLayer({
    required this.anchor,
    required this.overlaySize,
    required this.items,
    this.preferAbove = false,
  });

  final Rect anchor;
  final Size overlaySize;
  final List<OptionMenuItem<T>> items;
  final bool preferAbove;

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
      delegate: _AnchoredDelegate(
        anchor: anchor,
        overlaySize: overlaySize,
        preferAbove: preferAbove,
      ),
      child: OptionMenuCard<T>(items: items),
    );
  }
}

class _AnchoredDelegate extends SingleChildLayoutDelegate {
  _AnchoredDelegate({
    required this.anchor,
    required this.overlaySize,
    this.preferAbove = false,
  });

  final Rect anchor;
  final Size overlaySize;

  /// true면 앵커 **위**에 띄우는 걸 우선하고 공간이 없을 때만 아래로 뒤집는다.
  final bool preferAbove;

  /// 앵커와 카드 사이 간격.
  static const double _gap = AppSpacing.sm;

  /// 화면 가장자리에서 최소로 남길 여백.
  static const double _margin = AppSpacing.sm;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // 오른쪽 정렬 — 트리거가 보통 행/앱바의 오른쪽 끝에 있다.
    var x = anchor.right - childSize.width;
    x = x.clamp(
      _margin,
      (size.width - childSize.width - _margin).clamp(_margin, double.infinity),
    );

    double y;
    if (preferAbove) {
      // 위 우선 — 위 공간이 부족하면 아래로 뒤집는다.
      y = anchor.top - _gap - childSize.height;
      if (y < _margin) y = anchor.bottom + _gap;
    } else {
      // 아래 우선 — 아래로 넘치면 위로 뒤집는다.
      y = anchor.bottom + _gap;
      if (y + childSize.height + _margin > size.height) {
        y = anchor.top - _gap - childSize.height;
      }
    }
    y = y.clamp(
      _margin,
      (size.height - childSize.height - _margin).clamp(
        _margin,
        double.infinity,
      ),
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_AnchoredDelegate oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.overlaySize != overlaySize ||
      oldDelegate.preferAbove != preferAbove;
}

/// 옵션창 카드 — 규격(2026-08-05 지정): 좌우 패딩 **22** · 상하 패딩 **18** ·
/// `radius 20` · 약한 그림자(§5 float 티어) · **좌측 정렬** ·
/// 아이콘 **20** · 텍스트 **16** · 아이콘↔텍스트 gap **10**.
class OptionMenuCard<T> extends StatelessWidget {
  const OptionMenuCard({super.key, required this.items});

  final List<OptionMenuItem<T>> items;

  static const double radius = 20;
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 22,
    vertical: 18,
  );
  static const double iconSize = 20;
  static const double gap = 10;

  /// 항목 사이 간격 — 규격에 없어 `spacing.base`(16)를 쓴다. 상하 패딩 18과 어울리고
  /// 항목 높이(20)와 합쳐 손가락이 헷갈리지 않을 만큼 떨어진다.
  static const double _itemGap = AppSpacing.base;

  @override
  Widget build(BuildContext context) {
    // 그림자는 §5의 `float` 토큰(BoxShadow 3층)을 그대로 쓴다 — Material의 숫자 elevation은
    // 같은 자리에서 딱딱한 검정 테두리처럼 번져 "약한 그림자"와 어긋난다(실측 확인).
    // `floatMaterial`은 BoxShadow를 못 받는 위젯 전용 근사값이라 여기서는 쓰지 않는다.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppElevation.float,
      ),
      // 투명 Material — 배경·그림자는 위 Container가 그리고, 이건 **텍스트 스타일 컨텍스트**를
      // 위해 있다. 없으면 `Text`가 DefaultTextStyle을 못 찾아 디버그용 노란 밑줄이 그려진다
      // (실측으로 발견 — Material을 Container로 바꾼 직후 전 항목에 밑줄이 생겼다).
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: _itemGap),
                _OptionMenuRow<T>(item: items[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionMenuRow<T> extends StatelessWidget {
  const _OptionMenuRow({required this.item});

  final OptionMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final color = item.danger ? AppColors.accentDanger : AppColors.foreground;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(item.value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.icon != null) ...[
              Icon(item.icon, size: OptionMenuCard.iconSize, color: color),
              const SizedBox(width: OptionMenuCard.gap),
            ],
            Text(item.label, style: AppTypography.body.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
