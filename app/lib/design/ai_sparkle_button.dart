import 'package:flutter/material.dart';

import 'tokens.dart';

/// AI 액션용 원형 아이콘 버튼 — 60px 흰 원 + 중앙 아이콘 + 약한 그림자, **텍스트 없음**.
///
/// 투두 탭의 'AI로 생성하기'(S-16-B) 진입 버튼이 첫 사용처다. 라벨을 빼고 아이콘 하나만
/// 두는 대신, 접근성 이름은 [semanticLabel]로 준다(스크린리더가 읽을 문구).
/// 아이콘 에셋은 [iconAsset]으로 바꿔 다른 AI 액션에도 쓸 수 있다.
class AiSparkleButton extends StatelessWidget {
  const AiSparkleButton({
    super.key,
    required this.onTap,
    this.iconAsset = 'assets/icons/icon_ai_sparkle.png',
    this.semanticLabel = 'AI로 생성하기',
    this.size = 60,
    this.iconSize = 28,
  });

  final VoidCallback onTap;

  /// 중앙 아이콘(디자이너 제공 PNG — 자체 채색이라 tint를 입히지 않는다).
  final String iconAsset;

  /// 텍스트가 없으므로 스크린리더용 이름을 따로 준다.
  final String semanticLabel;

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      // 크기는 **자기가 정한다** — 부모가 넓은 제약을 주더라도(리스트·Row 안 등) 원이
      // 늘어나면 안 되므로 가장 바깥에서 고정한다.
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          // 떠 있는 요소라 단일 그림자 티어를 쓴다(design.md §5 float).
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: AppElevation.float,
          ),
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Image.asset(
                  iconAsset,
                  width: iconSize,
                  height: iconSize,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
