import 'package:flutter/material.dart';

import 'tokens.dart';

/// 밑줄형 라인 탭 (design.md §6). 흰 배경 위에 텍스트만 두고, 활성 탭은 하단 인디케이터 선으로
/// 구분한다. 탭 행 하단 전체에는 트랙(비활성) 선을 깔아 아래 콘텐츠와 분리한다.
///
/// 색·두께를 파라미터로 받아 두 가지 사용처를 모두 커버한다:
///  - **약관/정책(`/legal`)**: 활성 텍스트·인디케이터 모두 `primary`, 트랙 1px `border`(기본값).
///  - **모아보기 폴더(링크/이미지)**: 활성 텍스트 `foreground`(검정) + 인디케이터 `primary`(핑크),
///    트랙 2px `surface-strong`(#F2F2F2) — `LineTabs.underlineTrack(...)`으로 만든다.
class LineTabs extends StatelessWidget {
  const LineTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    this.textStyle,
    this.activeTextColor = AppColors.primary,
    this.inactiveTextColor = AppColors.muted,
    this.indicatorColor = AppColors.primary,
    this.trackColor = AppColors.border,
    this.indicatorHeight = 2,
    this.trackHeight = 1,
    this.verticalPadding = AppSpacing.sm,
  });

  /// 모아보기 폴더 스타일 프리셋 — 활성 텍스트 검정 + 핑크 인디케이터 + 회색(#F2F2F2) 2px 트랙.
  factory LineTabs.underlineTrack({
    Key? key,
    required List<String> tabs,
    required int selectedIndex,
    required ValueChanged<int> onChanged,
    TextStyle? textStyle,
  }) => LineTabs(
    key: key,
    tabs: tabs,
    selectedIndex: selectedIndex,
    onChanged: onChanged,
    textStyle: textStyle ?? AppTypography.body,
    activeTextColor: AppColors.foreground,
    inactiveTextColor: AppColors.mutedSoft,
    indicatorColor: AppColors.primary,
    trackColor: AppColors.surfaceStrong,
    trackHeight: 2,
  );

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// 탭 라벨 기본 스타일(색·굵기는 선택 상태에 따라 덮어쓴다). null이면 `body-small`.
  final TextStyle? textStyle;
  final Color activeTextColor;
  final Color inactiveTextColor;
  final Color indicatorColor;
  final Color trackColor;
  final double indicatorHeight;
  final double trackHeight;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // 탭 행 하단 전체 트랙 선 — 활성 탭의 인디케이터가 이 위를 덮는다.
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: trackColor, width: trackHeight),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) Expanded(child: _tab(i)),
        ],
      ),
    );
  }

  Widget _tab(int index) {
    final selected = index == selectedIndex;
    final base = textStyle ?? AppTypography.bodySmall;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? indicatorColor : Colors.transparent,
              width: indicatorHeight,
            ),
          ),
        ),
        child: Text(
          tabs[index],
          style: base.copyWith(
            color: selected ? activeTextColor : inactiveTextColor,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
