import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// 공휴일을 일정처럼 목록 상단에 보여주는 읽기전용 카드(2026-08-08).
/// 이름 데이터는 [KoreanHolidays.nameOf](추석·설날·어린이날 등). 색은 캘린더 휴일 색
/// (`accent-danger`)으로 통일해, 일반 일정 카드(primary 바)와 구분한다.
///
/// 각 화면의 일정 카드 룩에 맞춘다(두 카드가 서로 달라 공휴일 카드도 맥락별로 맞춰야
/// 나란히 놓였을 때 이질감이 없다):
///  - [bordered]=true — **일정 탭**(흰 캔버스). `schedule_screen.dart`의 일정 카드와 동일:
///    `radius.card`(16) · 좌측 바 3×34(반경 2) · 패딩 12/10(테두리 1px 보정) · 제목 `title` · 테두리.
///  - [bordered]=false — **홈 주간 미리보기**(회색 패널). `week_calendar.dart` 일정 카드와 동일:
///    radius 10 · 좌측 바 2×18 · 패딩 12/8 · 제목 `body` · 무테.
///
/// ⚠️ 3·34·10 등은 `design.md`의 4px 스케일 밖 값(형제 일정 카드와 동일한 Figma 확정값을
/// 그대로 따른다 — `specs/OPEN.md` 추적). 임의로 반올림하지 않는다.
class HolidayCard extends StatelessWidget {
  const HolidayCard({super.key, required this.name, this.bordered = true});

  final String name;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    const borderWidth = 1.0;
    final radius = bordered ? AppRadius.card : 10.0;
    final barWidth = bordered ? 3.0 : 2.0;
    final barHeight = bordered ? 34.0 : 18.0;
    final barGap = bordered ? 10.0 : AppSpacing.md; // 일정 탭 10 / 홈 12
    final nameStyle = bordered ? AppTypography.title : AppTypography.body;
    final padding = bordered
        ? const EdgeInsets.symmetric(
            horizontal: AppSpacing.md - borderWidth,
            vertical: 10 - borderWidth,
          )
        : const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: bordered
            ? Border.all(color: AppColors.border, width: borderWidth)
            : null,
      ),
      padding: padding,
      child: Row(
        children: [
          Container(
            width: barWidth,
            height: barHeight,
            decoration: BoxDecoration(
              color: AppColors.accentDanger,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: barGap),
          Expanded(
            child: Text(
              name,
              style: nameStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '공휴일',
            style: AppTypography.caption.copyWith(
              color: AppColors.accentDanger,
            ),
          ),
        ],
      ),
    );
  }
}
