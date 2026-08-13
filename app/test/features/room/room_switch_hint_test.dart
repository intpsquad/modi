import 'package:app/features/room/room_switch_hint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// specs/0008-방-전환.md — 코치마크 오버레이 위젯. 두 쓰임(단일 리마인더 / 2스텝 투어)을
/// 파라미터로 가른다. 무한 펄스라 pumpAndSettle 대신 고정 프레임만 진행시킨다.
Widget _host(Widget overlay) => MaterialApp(home: Stack(children: [overlay]));

void main() {
  testWidgets('기본(리마인더): 방전환 문구 + 진행 버튼 없음 + 바깥 탭으로 onDismiss', (tester) async {
    var dismissed = false;

    await tester.pumpWidget(
      _host(
        RoomSwitchHintOverlay(
          targetCenter: const Offset(50, 550),
          onDismiss: () => dismissed = true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('홈을 꾹 누르면 방을 바꿀 수 있어요'), findsOneWidget);
    expect(find.text('다음'), findsNothing);
    expect(find.text('완료'), findsNothing);

    // 구멍/버튼과 겹치지 않는 바깥 지점 탭 → 닫힘.
    await tester.tapAt(const Offset(400, 200));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets('투어 아바타 스텝: 아래 말풍선 + 완료 버튼 + 바깥 탭 무시, 완료로만 종료', (tester) async {
    var dismissed = false;
    var primary = false;

    await tester.pumpWidget(
      _host(
        RoomSwitchHintOverlay(
          targetCenter: const Offset(60, 150),
          onDismiss: () => dismissed = true,
          dismissOnOutsideTap: false,
          bubbleBelow: true,
          title: '팀원을 눌러 콕 찔러보세요',
          body: '진행 상황을 보고 콕 찔러 독려할 수 있어요',
          primaryLabel: '완료',
          onPrimary: () => primary = true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('팀원을 눌러 콕 찔러보세요'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);

    // 바깥 탭 → 닫히지 않는다.
    await tester.tapAt(const Offset(400, 400));
    await tester.pump();
    expect(dismissed, isFalse);

    // 완료 버튼 → onPrimary.
    await tester.tap(find.text('완료'));
    await tester.pump();
    expect(primary, isTrue);
  });
}
