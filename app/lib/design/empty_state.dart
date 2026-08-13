import 'package:flutter/material.dart';

import 'tokens.dart';

/// 빈 상태 공용 컴포넌트.
///
/// 은은한 라인 아이콘 + 안내 문구 + (선택) primary 텍스트 버튼을 **필요한 부분만**
/// 골라 중앙 정렬로 보여준다(design.md §빈 상태). 세 조각은 모두 선택이며, 화면 맥락에
/// 맞춰 조합한다.
/// - **full**: 아이콘 + 문구 + `+ 라벨` 버튼 (예: 모아보기).
/// - **액션-only**: 버튼만 (예: 홈 투두/일정 — 아이콘·문구 없이 `+ 추가하기`만 중앙).
/// - **문구-only**: 문구만 (예: 일정탭 — 추가 버튼이 우상단에 따로 있어 여기선 안내만).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionIcon = Icons.add_rounded,
    this.verticalPadding = AppSpacing.xl,
  }) : assert(
         icon != null ||
             message != null ||
             (actionLabel != null && onAction != null),
         '아이콘·문구·액션 중 최소 하나는 있어야 한다',
       );

  final IconData? icon;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData actionIcon;

  /// 상하 여백. 히어로형(아이콘+문구)은 기본 `xl`, 홈처럼 버튼만 넣는
  /// 액션-only는 더 작게(`sm`) 넘겨 위아래 간격을 줄인다.
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    final children = <Widget>[];
    if (icon != null) {
      children.add(Icon(icon, size: 40, color: AppColors.mutedSoft));
    }
    if (message != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.md));
      }
      children.add(
        Text(
          message!,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (hasAction) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: AppSpacing.sm));
      }
      children.add(
        TextButton.icon(
          onPressed: onAction,
          icon: Icon(actionIcon, size: 18),
          label: Text(actionLabel!),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: AppTypography.button,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
