import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// S-25-D: 아카이브 항목의 `crawlStatus`가 'DONE'이 아닐 때 목록/상세 화면에 공통으로 쓰는 배지.
/// `crawlStatus == 'DONE'`이면 호출하지 않는다(정상 상태는 배지 없음).
class CrawlStatusBadge extends StatelessWidget {
  const CrawlStatusBadge({super.key, required this.status});

  final String status;

  static const double _horizontalPadding = 10;

  /// 태그 칩과 **같은 줄에** 오므로 높이를 맞춘다(2026-08-05 요청으로 자료 목록의 칩 줄로
  /// 옮겼다). 세로 패딩 대신 높이를 고정하고 안쪽을 가운데 정렬한다.
  static const double height = 20;

  /// 텍스트 외 고정 폭 — `SingleLineChips`가 폭을 미리 재는 데 쓴다.
  static const double extraWidth = _horizontalPadding * 2;

  /// 상태별 문구 — 폭 계산과 렌더가 같은 문자열을 쓰도록 한곳에 둔다.
  static String labelFor(String status) =>
      status == 'FAILED' ? '분석 실패' : '분석 중';

  @override
  Widget build(BuildContext context) {
    final isFailed = status == 'FAILED';
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      decoration: BoxDecoration(
        color: isFailed
            ? AppColors.accentDanger.withValues(alpha: 0.1)
            : AppColors.accentWarningBackground,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      // ⚠️ Container에 `alignment`를 주면 **가로로 최대 폭까지 늘어난다**(실측: 800px).
      // 세로 가운데 정렬만 필요하므로 widthFactor 1인 Align으로 폭은 내용에 맞춘다.
      child: Align(
        alignment: Alignment.center,
        widthFactor: 1,
        child: Text(
          labelFor(status),
          style: AppTypography.badge.copyWith(
            color: isFailed
                ? AppColors.accentDanger
                : AppColors.accentWarningText,
          ),
        ),
      ),
    );
  }
}
