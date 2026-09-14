import 'package:flutter/material.dart';

/// MODI 워드마크 로고. 로그인(S-02)·인트로(S-01) 등에서 공유한다.
/// 원본은 `assets/icons/modi_logo.svg`(패턴+임베드 래스터라 flutter_svg가 못 그림)에서
/// 뽑은 PNG(`modi_logo.png`, 789×250, 비율 ≈ 3.16:1)를 쓴다.
///
/// ⚠️ **에셋에 투명 여백이 있으면 안 된다** — 이 위젯은 높이로만 크기를 정하므로,
/// 정사각 캔버스에 워드마크를 담아 내보내면 글자가 지정 높이의 일부만 차지해
/// 화면에서 훨씬 작게 보인다(2026-09-13 실제 사고: 1024×1024 캔버스에 789×250
/// 워드마크가 들어와 로고가 지정 높이의 24%로 렌더됐다). 로고를 교체할 때는
/// **내용 경계에 딱 맞게 잘라서** 넣는다.
class ModiWordmark extends StatelessWidget {
  const ModiWordmark({super.key, this.height = 28});

  /// 워드마크 높이(px). 폭은 비율(≈3.16:1)로 자동.
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
