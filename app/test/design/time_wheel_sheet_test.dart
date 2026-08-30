import 'package:app/design/theme.dart';
import 'package:app/design/time_wheel_sheet.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 시간 선택 휠 시트 — specs/design.md §7, #80.
/// 기존 Material `showTimePicker`(시계 다이얼)를 대체한다.

/// 시트를 띄우고, 사용자가 고른 값(또는 취소 시 null)을 돌려준다.
Future<TimeOfDay?> _openSheet(
  WidgetTester tester, {
  required TimeOfDay initialTime,
}) async {
  TimeOfDay? result;
  var opened = false;

  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              opened = true;
              result = await showTimeWheelSheet(
                context: context,
                initialTime: initialTime,
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  expect(opened, isTrue);
  return result;
}

/// 진짜 더블탭 — `tester.tap` 두 번은 간격이 kDoubleTapTimeout 을 넘어 별개 탭이 된다.
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('휠 3개와 완료 버튼이 보인다', (tester) async {
    await _openSheet(tester, initialTime: const TimeOfDay(hour: 9, minute: 0));

    expect(find.text('시간 선택'), findsOneWidget);
    expect(find.byKey(const ValueKey('time-wheel-hour')), findsOneWidget);
    expect(find.byKey(const ValueKey('time-wheel-minute')), findsOneWidget);
    expect(find.byKey(const ValueKey('time-wheel-period')), findsOneWidget);
    expect(find.byKey(const ValueKey('time-wheel-confirm')), findsOneWidget);
  });

  testWidgets('오전·오후는 AM/PM이 아니라 우리말로 적는다', (tester) async {
    // 고르는 순간과 고른 뒤 보이는 값(formatTimeOfDayKorean)의 말이 같아야 한다.
    await _openSheet(tester, initialTime: const TimeOfDay(hour: 9, minute: 0));

    expect(find.text('오전'), findsOneWidget);
    expect(find.text('오후'), findsOneWidget);
    expect(find.text('AM'), findsNothing);
    expect(find.text('PM'), findsNothing);
  });

  testWidgets('완료를 누르면 초기값을 그대로 돌려준다', (tester) async {
    // 아무것도 안 돌렸으면 열 때 준 값이 그대로 나와야 한다 — 초기 스크롤 위치가
    // 어긋나면 사용자가 건드리지도 않은 값이 바뀐다.
    TimeOfDay? picked;
    await tester.runAsync(() async {});

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showTimeWheelSheet(
                  context: context,
                  initialTime: const TimeOfDay(hour: 14, minute: 30),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('time-wheel-confirm')));
    await tester.pumpAndSettle();

    expect(picked, const TimeOfDay(hour: 14, minute: 30));
  });

  testWidgets('선택 칸 배경이 고른 값을 가리지 않는다', (tester) async {
    // #80 실기 확인에서 잡은 회귀 — 선택 칸 배경을 `selectionOverlay` 로 넘겼더니
    // 자식 **위에** 그려져서 불투명 색이 고른 값(시·분·오전오후)을 통째로 가렸다.
    // find.text 는 페인트 순서를 안 보므로 이 검사가 유일한 방어선이다.
    await _openSheet(tester, initialTime: const TimeOfDay(hour: 9, minute: 0));

    for (final key in const [
      ValueKey('time-wheel-hour'),
      ValueKey('time-wheel-minute'),
      ValueKey('time-wheel-period'),
    ]) {
      final picker = tester.widget<CupertinoPicker>(find.byKey(key));
      expect(
        picker.selectionOverlay,
        isA<SizedBox>(),
        reason: '$key 의 선택 칸 배경은 피커 뒤(Stack)에 깔아야 한다',
      );
    }
  });

  testWidgets('선택 칸을 더블탭하면 숫자 입력창이 열린다', (tester) async {
    // 휠로 60칸을 굴리는 것보다 직접 치는 게 빠른 경우가 있다. Material 피커의
    // 키보드 토글이 사라진 자리를 이걸로 메운다(#80).
    await _openSheet(tester, initialTime: const TimeOfDay(hour: 9, minute: 0));

    expect(find.byType(TextField), findsNothing);

    await _doubleTap(tester, find.byKey(const ValueKey('time-wheel-hour')));

    expect(find.byKey(const ValueKey('time-wheel-hour-field')), findsOneWidget);
  });

  testWidgets('오전·오후 휠은 숫자가 아니라 더블탭해도 입력창이 안 열린다', (tester) async {
    await _openSheet(tester, initialTime: const TimeOfDay(hour: 9, minute: 0));

    await _doubleTap(tester, find.byKey(const ValueKey('time-wheel-period')));

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('직접 친 숫자가 완료 결과에 반영된다', (tester) async {
    TimeOfDay? picked;
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showTimeWheelSheet(
                  context: context,
                  initialTime: const TimeOfDay(hour: 9, minute: 0),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await _doubleTap(tester, find.byKey(const ValueKey('time-wheel-minute')));
    await tester.enterText(
      find.byKey(const ValueKey('time-wheel-minute-field')),
      '45',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('time-wheel-confirm')));
    await tester.pumpAndSettle();

    expect(picked, const TimeOfDay(hour: 9, minute: 45));
  });

  testWidgets('범위를 넘는 숫자는 거부가 아니라 잘라 맞춘다', (tester) async {
    // 99분은 입력 자체를 막기보다 59로 붙여 주는 쪽이 덜 답답하다.
    await _openSheet(tester, initialTime: const TimeOfDay(hour: 9, minute: 0));

    await _doubleTap(tester, find.byKey(const ValueKey('time-wheel-minute')));
    await tester.enterText(
      find.byKey(const ValueKey('time-wheel-minute-field')),
      '99',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('59'), findsWidgets);
  });

  testWidgets('입력창은 회색 칸 위에서 글자만 바뀐다 — 흰 상자를 덧대지 않는다', (tester) async {
    // 전역 inputDecorationTheme 이 filled:true(흰색) + 회색 테두리라, `border` 만
    // 끄면 선택 칸 위에 흰 둥근 사각형이 얹힌다(실기 확인에서 지적됨).
    await _openSheet(tester, initialTime: const TimeOfDay(hour: 9, minute: 0));
    await _doubleTap(tester, find.byKey(const ValueKey('time-wheel-hour')));

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('time-wheel-hour-field')),
    );
    final decoration = field.decoration!;
    expect(decoration.filled, isFalse, reason: '흰 배경을 깔면 안 된다');
    expect(decoration.border, InputBorder.none);
    expect(decoration.enabledBorder, InputBorder.none);
    expect(decoration.focusedBorder, InputBorder.none);
  });

  testWidgets('다른 곳을 터치하면 입력창이 닫힌다', (tester) async {
    await _openSheet(tester, initialTime: const TimeOfDay(hour: 9, minute: 0));

    await _doubleTap(tester, find.byKey(const ValueKey('time-wheel-hour')));
    expect(find.byKey(const ValueKey('time-wheel-hour-field')), findsOneWidget);

    // 시트 제목처럼 휠 밖의 아무 곳이나 누르면 편집이 끝난다.
    await tester.tap(find.text('시간 선택'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('time-wheel-hour-field')), findsNothing);
  });

  testWidgets('시트를 닫으면 null 이라 호출부가 기존 값을 지킨다', (tester) async {
    TimeOfDay? picked = const TimeOfDay(hour: 1, minute: 1);

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showTimeWheelSheet(
                  context: context,
                  initialTime: const TimeOfDay(hour: 9, minute: 0),
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    // scrim 을 눌러 시트를 닫는다(취소 버튼은 없다 — 참조 디자인과 동일).
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();

    expect(picked, isNull);
  });
}
