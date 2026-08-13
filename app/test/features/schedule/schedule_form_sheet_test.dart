import 'package:app/design/theme.dart';
import 'package:app/features/schedule/schedule_form_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 일정 추가/수정 시트의 기간·시간·장소 행 — specs/0009.
/// 2026-08-05 요청: 라벨은 왼쪽, "값 + 꺽쇠" 세트는 오른쪽(space-between).

Future<void> pumpSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ScheduleFormSheet(
          date: DateTime(2026, 8, 10),
          onSubmit:
              ({
                required title,
                required date,
                time,
                endDate,
                endTime,
                detail,
                place,
              }) async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('기간·시간·장소 행은 라벨 왼쪽 / 값+꺽쇠 오른쪽으로 벌어진다', (tester) async {
    await pumpSheet(tester);

    // 그룹 박스가 좌우 여백(16)을 뺀 폭을 다 써야 Spacer가 작동한다.
    // 예전에는 바깥 Column이 crossAxisAlignment.start라 박스가 내용 폭으로 줄어들어
    // 라벨과 값이 붙어 있었다.
    final chevrons = find.byIcon(Icons.chevron_right);
    expect(chevrons, findsAtLeastNWidgets(3), reason: '기간·시간·장소 행');

    for (final label in ['기간', '시간', '장소']) {
      final labelRect = tester.getRect(find.text(label));
      expect(labelRect.left, closeTo(32, 1), reason: '$label 라벨은 왼쪽(16+16)');
    }

    // 꺽쇠는 오른쪽 끝(화면폭 400 - 좌우 여백 16 - 박스 내부 여백 16)에 붙는다.
    for (var i = 0; i < 3; i++) {
      final chevron = tester.getRect(chevrons.at(i));
      expect(
        chevron.right,
        closeTo(367, 2),
        reason: "꺽쇠는 오른쪽 끝(박스 안쪽 여백 16 안)",
      );
    }
  });

  testWidgets('값 텍스트는 꺽쇠 바로 왼쪽에 붙는다', (tester) async {
    await pumpSheet(tester);

    // 값은 Expanded로 가운데를 다 차지하고 **오른쪽 정렬**이라, 글자가 꺽쇠 옆에 붙는다.
    // getRect은 글자가 아니라 박스를 주므로 박스의 오른쪽 끝과 정렬 속성을 함께 본다.
    final valueBox = tester.getRect(find.text('종일'));
    final chevron = tester.getRect(find.byIcon(Icons.chevron_right).at(1));

    expect(
      chevron.left - valueBox.right,
      closeTo(4, 1),
      reason: '값 박스 바로 뒤에 꺽쇠',
    );
    expect(
      tester.widget<Text>(find.text('종일')).textAlign,
      TextAlign.right,
      reason: '글자는 오른쪽 정렬 — 그래야 꺽쇠에 붙어 보인다',
    );
  });

  // 2026-08-08: 안드로이드 하단 네비바 겹침 수정 — 방 전환 시트처럼 SafeArea로
  // 하단 시스템 인셋을 흡수해, 시트 콘텐츠가 네비바 위에서 시작하게 한다.
  testWidgets('하단 시스템 인셋(네비바)만큼 콘텐츠가 위로 밀려 하단바와 겹치지 않는다', (tester) async {
    const navBarInset = 48.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(400, 800),
            devicePixelRatio: 1,
            padding: EdgeInsets.only(bottom: navBarInset),
          ),
          child: Scaffold(
            // 실제 바텀시트처럼 콘텐츠를 하단에 앵커해 하단 여백을 검증한다.
            body: Align(
              alignment: Alignment.bottomCenter,
              child: _SubmitProbe(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final buttonRect = tester.getRect(
      find.widgetWithText(ElevatedButton, '추가하기'),
    );
    expect(
      buttonRect.bottom,
      lessThanOrEqualTo(800 - navBarInset + 0.5),
      reason: 'SafeArea가 하단 네비바 인셋(48)을 흡수해 버튼이 그 위에 위치해야 한다',
    );
  });
}

/// 하단 인셋 검증용 — 최소 구성의 생성 모드 시트.
class _SubmitProbe extends StatelessWidget {
  const _SubmitProbe();

  @override
  Widget build(BuildContext context) {
    return ScheduleFormSheet(
      date: DateTime(2026, 8, 10),
      onSubmit:
          ({
            required title,
            required date,
            time,
            endDate,
            endTime,
            detail,
            place,
          }) async {},
    );
  }
}
