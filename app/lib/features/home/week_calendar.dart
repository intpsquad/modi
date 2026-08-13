import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../schedule/holiday_card.dart';
import '../schedule/korean_holidays.dart';
import '../schedule/schedule_time_format.dart';
import 'home_api.dart';

/// 홈 주간 달력(읽기전용) — specs/0005-홈-대시보드.md.
/// #F7F7F7 배경 + 16px 라운드 컨테이너. 오늘이 기본 Selected이고, 날짜 칸을 탭하면
/// Active(하이라이트)만 바뀐다(전이·시트 없음 = 읽기전용). 날짜 하단 상태 점은
/// 조건부(Boolean) 렌더 — 현재는 해당 날짜의 일정 유무.
class WeekCalendar extends StatefulWidget {
  const WeekCalendar({
    super.key,
    required this.schedules,
    required this.weekStart,
  });

  final List<ScheduleBrief> schedules;
  final DateTime weekStart;

  @override
  State<WeekCalendar> createState() => _WeekCalendarState();
}

class _WeekCalendarState extends State<WeekCalendar> {
  static const _labels = ['월', '화', '수', '목', '금', '토', '일'];

  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = _dateOnly(DateTime.now());
  }

  @override
  void didUpdateWidget(WeekCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 방 전환 등으로 주가 바뀌면 선택을 오늘로 되돌린다(기본 상태 복귀).
    if (oldWidget.weekStart != widget.weekStart) {
      _selected = _dateOnly(DateTime.now());
    }
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());

    // 선택된 날짜의 일정 — 상태 점과 같은 데이터/색(현재 카테고리 없어 primary 단일).
    // 다중일 일정은 구간에 속한 모든 날짜에서 노출된다(schedule_screen.dart와
    // 동일한 구간 포함 판정 — 2026-08-04).
    final selectedSchedules = widget.schedules
        .where((s) => s.coversDate(_selected))
        .toList();

    // 배경 컨테이너는 부모 섹션 박스가 제공한다(헤더를 박스 안에 두기 위해).
    final dayRow = Row(
      children: List.generate(7, (i) {
        final date = _dateOnly(widget.weekStart.add(Duration(days: i)));
        final isSelected = date == _selected;
        final isToday = date == today;
        final hasSchedule = widget.schedules.any((s) => s.coversDate(date));
        final isWeekend = i >= 5; // 토(5)·일(6)은 살짝 muted 처리

        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _selected = date),
            child: Column(
              children: [
                // 요일 라벨·날짜 숫자 모두 title(16/600) — 섹션 제목과 동일. 주말은 살짝 muted.
                Text(
                  _labels[i],
                  style: AppTypography.title.copyWith(
                    color: isWeekend ? AppColors.muted : AppColors.foreground,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColors.primary : Colors.transparent,
                  ),
                  child: Text(
                    '${date.day}',
                    style: AppTypography.title.copyWith(
                      color: isSelected
                          ? AppColors.onPrimary
                          : (isToday
                                ? AppColors.primary
                                : (isWeekend
                                      ? AppColors.muted
                                      : AppColors.foreground)),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // 상태 점 — 조건부 렌더(일정 유무).
                SizedBox(
                  width: 5,
                  height: 5,
                  child: hasSchedule
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // 일정 유무 점 — 비선택은 연하게(borderStrong), 선택일은 primary.
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.borderStrong,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
      }),
    );

    // 공휴일이면 이름을 일정처럼 미리보기 맨 위에 보여준다.
    final holidayName = KoreanHolidays.nameOf(_selected);
    final hasPreview = holidayName != null || selectedSchedules.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        dayRow,
        // 선택일 공휴일·일정 리스트 카드(읽기전용). 둘 다 없으면 렌더 안 함.
        if (hasPreview) ...[
          const SizedBox(height: AppSpacing.md),
          if (holidayName != null) ...[
            // 홈은 회색 _SectionBox 안이라 무테(bordered:false).
            HolidayCard(name: holidayName, bordered: false),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final s in selectedSchedules) ...[
            _ScheduleCard(schedule: s),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ],
    );
  }
}

/// 선택일 일정 카드 — 흰 배경 + 8px 라운드 + 좌측 세로 액센트 바(카테고리/상태 색 자리).
/// 카테고리 데이터가 없어 현재 액센트는 primary 단일(상태 점과 동일) — specs/OPEN.md.
class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.schedule});

  final ScheduleBrief schedule;

  /// 종료 시간이 있으면 "오전 10:00 - 오후 12:00" 범위, 없으면 시작 시간만
  /// 단일 표기. 서버가 "HH:mm:ss"를 내려주지만 초는 표시하지 않는다.
  String? get _displayTime {
    final start = formatServerTimeKorean(schedule.time);
    if (start == null) return null;
    final end = formatServerTimeKorean(schedule.endTime);
    return end == null ? start : '$start - $end';
  }

  @override
  Widget build(BuildContext context) {
    // 흰 카드(radius 10) 안: 좌 12px → 2×18 세로 바(#FF385C) → 12px → 일정(2026-08-07 요청).
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(width: 2, height: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              schedule.title,
              style: AppTypography.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_displayTime != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(_displayTime!, style: AppTypography.caption),
          ],
        ],
      ),
    );
  }
}
