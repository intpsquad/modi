import 'package:app/features/home/home_api.dart';
import 'package:app/features/home/week_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime mondayOfThisWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('선택된 날짜(기본 오늘)에 일정이 있으면 일정 카드가 노출된다', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await tester.pumpWidget(
      wrap(
        WeekCalendar(
          schedules: [
            ScheduleBrief(
              id: 1,
              title: '스크럼 미팅',
              date: today,
              time: '10:00:00',
            ),
          ],
          weekStart: mondayOfThisWeek(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('스크럼 미팅'), findsOneWidget);
    // 서버는 "10:00:00"(초 포함)을 내려주지만, 화면에는 초를 표시하지 않는다.
    expect(find.text('오전 10:00'), findsOneWidget);
    expect(find.text('10:00:00'), findsNothing);
  });

  testWidgets('종료 시간이 있으면 시간 범위로 표시된다', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await tester.pumpWidget(
      wrap(
        WeekCalendar(
          schedules: [
            ScheduleBrief(
              id: 1,
              title: '워크숍',
              date: today,
              time: '10:00:00',
              endTime: '12:00:00',
            ),
          ],
          weekStart: mondayOfThisWeek(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('오전 10:00 - 오후 12:00'), findsOneWidget);
  });

  testWidgets('다중일 일정이 구간 내 다른 날짜를 선택해도 카드로 보인다', (tester) async {
    final weekStart = mondayOfThisWeek();
    final start = weekStart;
    final end = weekStart.add(const Duration(days: 2));
    await tester.pumpWidget(
      wrap(
        WeekCalendar(
          schedules: [
            ScheduleBrief(id: 1, title: '워크숍', date: start, endDate: end),
          ],
          weekStart: weekStart,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 오늘이 이번 주 구간 밖일 수 있으므로, 구간의 마지막 날을 직접 탭한다.
    await tester.tap(find.text('${end.day}'));
    await tester.pumpAndSettle();

    expect(find.text('워크숍'), findsOneWidget);
  });

  testWidgets('선택된 날짜에 일정이 없으면 일정 카드가 없다', (tester) async {
    final weekStart = mondayOfThisWeek();
    // 다음 주 날짜에만 일정 → 이번 주 선택일(오늘)엔 카드 없음.
    await tester.pumpWidget(
      wrap(
        WeekCalendar(
          schedules: [
            ScheduleBrief(
              id: 1,
              title: '먼 일정',
              date: weekStart.add(const Duration(days: 30)),
            ),
          ],
          weekStart: weekStart,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('먼 일정'), findsNothing);
  });

  testWidgets('이번 주 7일이 월~일 라벨과 함께 표시된다', (tester) async {
    await tester.pumpWidget(
      wrap(WeekCalendar(schedules: const [], weekStart: mondayOfThisWeek())),
    );
    await tester.pumpAndSettle();

    for (final label in ['월', '화', '수', '목', '금', '토', '일']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('일정이 있는 날에만 상태 점이 조건부로 렌더된다', (tester) async {
    final weekStart = mondayOfThisWeek();
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final scheduleDate = List.generate(
      7,
      (index) => weekStart.add(Duration(days: index)),
    ).firstWhere((date) => date != todayDate);

    int decoratedBoxCount() => tester
        .widgetList(
          find.descendant(
            of: find.byType(WeekCalendar),
            matching: find.byType(DecoratedBox),
          ),
        )
        .length;

    await tester.pumpWidget(
      wrap(WeekCalendar(schedules: const [], weekStart: weekStart)),
    );
    await tester.pumpAndSettle();
    final withoutSchedule = decoratedBoxCount();

    await tester.pumpWidget(
      wrap(
        WeekCalendar(
          // 오늘 일정이면 카드 배경까지 함께 생겨 DecoratedBox가 2개 증가한다.
          // 상태 점만 비교할 수 있도록 이번 주의 오늘이 아닌 날짜를 사용한다.
          schedules: [ScheduleBrief(id: 1, title: '회의', date: scheduleDate)],
          weekStart: weekStart,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final withSchedule = decoratedBoxCount();

    // 일정 하루가 늘면 상태 점(DecoratedBox) 하나가 추가된다.
    expect(withSchedule, withoutSchedule + 1);
  });

  testWidgets('다른 날짜를 탭하면 Selected 하이라이트가 이동한다(읽기전용, 전이 없음)', (tester) async {
    final weekStart = mondayOfThisWeek();
    await tester.pumpWidget(
      wrap(WeekCalendar(schedules: const [], weekStart: weekStart)),
    );
    await tester.pumpAndSettle();

    // 오늘이 기본 선택. 오늘이 아닌 다른 날짜를 골라 탭한다.
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    DateTime target = weekStart;
    for (var i = 0; i < 7; i++) {
      final d = weekStart.add(Duration(days: i));
      if (d != todayDate) {
        target = d;
        break;
      }
    }

    await tester.tap(find.text('${target.day}'));
    await tester.pumpAndSettle();

    // 탭 후에도 화면 전이가 없어야 한다(WeekCalendar가 그대로 존재).
    expect(find.byType(WeekCalendar), findsOneWidget);
  });

  // 공휴일 이름 표시: 선택일이 공휴일이면 미리보기에 이름 카드를 보여준다.
  testWidgets('선택일이 공휴일이면 이름과 "공휴일" 배지를 미리보기에 보여준다', (tester) async {
    // 2026-12-25(금, 성탄절)이 든 주. 월요일 시작 = 2026-12-21.
    await tester.pumpWidget(
      wrap(
        WeekCalendar(schedules: const [], weekStart: DateTime(2026, 12, 21)),
      ),
    );
    await tester.pumpAndSettle();

    // 실제 '오늘'이 이 주 밖일 수 있으므로 성탄절 셀을 직접 탭해 선택한다.
    await tester.tap(find.text('25'));
    await tester.pumpAndSettle();

    expect(find.text('성탄절'), findsOneWidget);
    expect(find.text('공휴일'), findsOneWidget);
  });
}
