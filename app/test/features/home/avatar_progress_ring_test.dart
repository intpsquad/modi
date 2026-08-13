import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app/design/tokens.dart';
import 'package:app/features/home/avatar_progress_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 링을 실제로 그려 픽셀을 읽는다 — 앵귤러 그라데이션은 위젯 트리 단언으로 확인할 수 없다.
Future<RingPixels> renderRing(
  WidgetTester tester, {
  required double progress,
  double size = 64,
  double strokeWidth = 4,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: const ValueKey('ring'),
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Center(
            child: AvatarProgressRing(
              progress: progress,
              label: '주',
              size: size,
              strokeWidth: strokeWidth,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  late ByteData bytes;
  late ui.Image image;
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject(find.byKey(const ValueKey('ring')))
            as RenderRepaintBoundary;
    image = await boundary.toImage();
    bytes = (await image.toByteData())!;
  });
  final ringRect = tester.getRect(find.byType(AvatarProgressRing));
  return RingPixels(
    bytes: bytes,
    width: image.width,
    center: ringRect.center,
    radius: (size - strokeWidth) / 2,
  );
}

class RingPixels {
  RingPixels({
    required this.bytes,
    required this.width,
    required this.center,
    required this.radius,
  });

  final ByteData bytes;
  final int width;
  final Offset center;
  final double radius;

  /// 12시에서 시계방향으로 [turns](0~1) 지점의 링 색.
  Color at(double turns) {
    final angle = -math.pi / 2 + 2 * math.pi * turns;
    final x = (center.dx + radius * math.cos(angle)).round();
    final y = (center.dy + radius * math.sin(angle)).round();
    final offset = (y * width + x) * 4;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }
}

/// 두 색이 사람 눈에 "같은 계열"인지 — 안티에일리어싱·블렌딩 오차를 허용한다.
Matcher closeToColor(Color expected, {int tolerance = 40}) => predicate<Color>(
  (actual) =>
      ((actual.r - expected.r) * 255).abs() <= tolerance &&
      ((actual.g - expected.g) * 255).abs() <= tolerance &&
      ((actual.b - expected.b) * 255).abs() <= tolerance,
  '≈ $expected (±$tolerance)',
);

void main() {
  testWidgets('채움은 진행 구간 전체가 primary 단색이다', (tester) async {
    // 2026-08-05: 앵귤러 그라데이션에서 단색으로 되돌렸다 — 구간 어디를 찍어도 같은 색이어야 한다.
    final ring = await renderRing(tester, progress: 1);

    for (final turns in [0.0, 0.02, 0.25, 0.5, 0.75, 0.98]) {
      expect(
        ring.at(turns),
        closeToColor(AppColors.primary),
        reason: 'turns=$turns',
      );
    }
    expect(ring.at(0.5), isNot(closeToColor(AppColors.aiGradientEnd)));
  });

  testWidgets('진행률만큼만 채우고 나머지는 트랙이다', (tester) async {
    final ring = await renderRing(tester, progress: 0.4);

    expect(ring.at(0.02), closeToColor(AppColors.primary));
    expect(ring.at(0.38), closeToColor(AppColors.primary));
    expect(ring.at(0.7), closeToColor(AppColors.border), reason: '빈 구간은 트랙');
  });

  testWidgets('진행률 0이면 트랙만 그린다', (tester) async {
    final ring = await renderRing(tester, progress: 0);

    for (final turns in [0.0, 0.25, 0.5, 0.75]) {
      expect(
        ring.at(turns),
        closeToColor(AppColors.border),
        reason: 'turns=$turns',
      );
    }
  });
}
