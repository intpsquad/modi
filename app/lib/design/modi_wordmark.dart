import 'package:flutter/material.dart';

/// MODI 워드마크 로고. 로그인(S-02)·인트로(S-01) 등에서 공유한다.
/// 원본은 `assets/icons/modi_logo.svg`(패턴+임베드 래스터라 flutter_svg가 못 그림)에서
/// 뽑아 다운스케일한 PNG(`modi_logo.png`, 600×184, 비율 ≈ 3.26:1)를 쓴다.
class ModiWordmark extends StatelessWidget {
  const ModiWordmark({super.key, this.height = 28});

  /// 워드마크 높이(px). 폭은 비율(≈3.26:1)로 자동.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icons/modi_logo.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'MODI',
    );
  }
}
