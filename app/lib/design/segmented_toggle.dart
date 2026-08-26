import 'package:flutter/material.dart';

import 'tokens.dart';

/// 분리형 선택 컨트롤 (design.md §6). 트랙 위에서 **알약 하나가 좌우로 미끄러지는** 방식이다.
///
/// 원래 투두 탭(`todos_screen.dart`)의 private 위젯("내 투두만 / 전체보기")이었다. 피드백 폼(#70)의
/// 유형 선택(버그 / 문의 / 제안)이 같은 컨트롤을 쓰게 되면서 공용으로 승격했다 — 복붙하면 모션·색이
/// 두 화면에서 갈린다.
class SegmentedToggle extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// 트랙 높이 — 디자이너 지정(2026-08-06).
  static const double height = 40;

  /// 전환 시간 — design.md §6(모션 토큰 부재 임시값, `specs/OPEN.md`).
  static const _duration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    // 트랙: 높이 40, radius.pill, 배경 surface-soft(2026-08-06 지정).
    return Container(
      key: const ValueKey('segmented-track'),
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 선택 알약은 **하나뿐**이고 좌우로 미끄러진다(2026-08-06 요청). 칸마다 배경을
          // 켜고 끄면 이동이 아니라 "사라졌다 나타나기"가 된다.
          AnimatedAlign(
            duration: _duration,
            curve: Curves.easeOut,
            alignment: _thumbAlignment,
            child: FractionallySizedBox(
              widthFactor: 1 / segments.length,
              heightFactor: 1,
              child: Container(
                key: const ValueKey('segmented-thumb'),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < segments.length; i++)
                Expanded(child: _segment(i)),
            ],
          ),
        ],
      ),
    );
  }

  /// 칸 i의 중심에 알약을 놓는 정렬값 — 칸이 하나뿐이면 가운데.
  Alignment get _thumbAlignment {
    if (segments.length < 2) return Alignment.center;
    return Alignment(-1 + 2 * selectedIndex / (segments.length - 1), 0);
  }

  Widget _segment(int index) {
    final selected = index == selectedIndex;
    // 칸 자체는 배경이 없다(투명) — 배경은 위의 알약 하나가 맡는다.
    // 글씨색은 AnimatedDefaultTextStyle이 보간해 fade처럼 바뀐다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(index),
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: _duration,
          curve: Curves.easeOut,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.onPrimary : AppColors.muted,
          ),
          child: Text(segments[index]),
        ),
      ),
    );
  }
}
