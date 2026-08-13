import 'dart:math';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// 아바타 + 진행률 링 — specs/design.md §6(컴포넌트 규격). 트랙=border, **채움=primary 단색**.
/// (2026-08-05: 앵귤러 그라데이션으로 바꿨다가 같은 날 사용자 요청으로 단색으로 되돌렸다.)
/// 기본 36px/두께 3px(홈 아바타줄), 컴팩트 28px(리스트 등)로 재사용.
/// [strokeWidth]로 대형 링(멤버 프로필 히어로 S-30-M)에 두꺼운 게이지를 준다.
class AvatarProgressRing extends StatelessWidget {
  const AvatarProgressRing({
    super.key,
    required this.progress,
    required this.label,
    this.imageUrl,
    this.size = 36,
    this.strokeWidth = 3,
  });

  /// 0.0~1.0. 0이면 트랙만, 1이면 링 한 바퀴가 그라데이션으로 찬다.
  final double progress;

  /// 프로필 이미지가 없을 때 표시할 이니셜(닉네임 첫 글자).
  final String label;
  final String? imageUrl;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ProgressRingPainter(
          progress: progress.clamp(0, 1),
          strokeWidth: strokeWidth,
        ),
        child: Padding(
          padding: EdgeInsets.all(strokeWidth + 2),
          child: ClipOval(
            child: imageUrl != null
                ? Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    // URL 실패 시 빈 원 대신 이니셜로 폴백.
                    errorBuilder: (context, error, stackTrace) => _initial(),
                  )
                : _initial(),
          ),
        ),
      ),
    );
  }

  Widget _initial() => Container(
    color: AppColors.surfaceSoft,
    alignment: Alignment.center,
    child: Text(
      label,
      style: AppTypography.caption.copyWith(color: AppColors.foreground),
    ),
  );
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({required this.progress, required this.strokeWidth});

  final double progress;
  final double strokeWidth;

  /// 12시에서 시작해 시계방향으로 채운다.
  static const double _startAngle = -pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      // 채움은 primary 단색(2026-08-05 사용자 확정 — 앵귤러 그라데이션을 되돌렸다).
      final fillPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = AppColors.primary;
      canvas.drawArc(rect, _startAngle, 2 * pi * progress, false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.strokeWidth != strokeWidth;
}
