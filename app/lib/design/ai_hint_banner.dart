import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// AI 관련 한 줄 안내 배너 — 흰 배경 + **AI 그라데이션 1px 테두리**(45°) + 좌측 아이콘 + 문구.
///
/// 첫 사용처는 투두 탭 상단의 "담당자 미지정" 안내지만, **문구·아이콘을 갈아끼워 다른 곳에서도
/// 쓰도록** 만들었다(AI 표식이 필요한 안내 전용 — design.md §2: 두 그라데이션 색은 AI 생성물
/// 표식에만 쓴다).
///
/// 규격(2026-08-05 지정): 높이 40 · `radius.control`(16) · 패딩 10×16 · 아이콘 20 ·
/// 아이콘↔문구 간격 8 · 문구 13px. 문구는 남는 폭을 다 쓰고, 길면 말줄임으로 자른다.
class AiHintBanner extends StatelessWidget {
  const AiHintBanner({
    super.key,
    required this.text,
    this.iconAsset = 'assets/icons/icon_ai_sparkle.png',
    this.onTap,
    this.maxLines = 1,
  });

  /// 배너 문구. 사용처마다 바꿔 쓴다.
  final String text;

  /// 좌측 아이콘(디자이너 제공 PNG — 자체 채색이라 tint 없이 그대로 그린다).
  final String iconAsset;

  /// 누를 수 있는 배너면 준다. null이면 표시 전용.
  final VoidCallback? onTap;

  final int maxLines;

  static const double _height = 40;
  static const double _borderWidth = 2;
  static const double _iconSize = 20;

  /// 은은한 민트 글로우 — 오프셋 0(사방으로 고르게 퍼진다). 그라데이션 두 색 중 **민트**만
  /// 쓴다(핑크는 쓰지 않는다, 2026-08-05 지정). design.md §5의 float 티어와 별개인
  /// **AI 표식 전용 글로우**라 여기서만 쓴다.
  static const List<BoxShadow> _glow = [
    BoxShadow(
      color: Color(0x5961FFE5), // ai-gradient-start @ 35%
      blurRadius: 10,
      offset: Offset.zero,
    ),
  ];

  /// 가로 패딩만 지정값(16)을 그대로 쓴다. **세로는 높이 40이 이긴다** — 지정대로 10+10을
  /// 주면 테두리 2px까지 더해 42가 되어 20px 아이콘이 40 안에 안 들어간다(실측 18px로 눌림).
  /// 그래서 세로는 패딩 대신 가운데 정렬로 두고, 남는 여백이 자연히 9px씩 잡히게 한다.
  static const EdgeInsets _padding = EdgeInsets.symmetric(horizontal: 16);

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: _padding,
      child: Row(
        children: [
          Image.asset(
            iconAsset,
            width: _iconSize,
            height: _iconSize,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: AppColors.foreground,
              ),
            ),
          ),
        ],
      ),
    );

    // 그라데이션 테두리는 Border 로 그릴 수 없다 — 그라데이션 배경 위에 _borderWidth 만큼 안쪽으로
    // 흰 면(Material)을 얹어 테두리처럼 보이게 한다. 흰 면을 Material 로 두면
    // Scaffold 밖에서도 잉크 효과가 동작하고(조상 Material 을 요구하지 않는다),
    // 리플이 흰 면 위에 정확히 그려진다.
    return Container(
      height: _height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        gradient: const LinearGradient(
          colors: [AppColors.aiGradientStart, AppColors.aiGradientEnd],
          // 박스 비율과 무관하게 정확히 45°(왼쪽 아래 → 오른쪽 위).
          transform: GradientRotation(-math.pi / 4),
        ),
        boxShadow: _glow,
      ),
      padding: const EdgeInsets.all(_borderWidth),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.control - _borderWidth),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? row : InkWell(onTap: onTap, child: row),
      ),
    );
  }
}
