import 'package:app/features/room/room_api.dart';
import 'package:app/features/room/room_session.dart';
import 'package:app/features/room/room_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRoomApi extends RoomApi {
  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async => [];
}

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RoomSetupScreen(
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('선물상자 그래픽·서브 문구·CTA 2종이 렌더된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pump(tester);

    expect(find.byIcon(Icons.card_giftcard), findsOneWidget);
    expect(find.text('팀과 함께할 방을 만들거나, 초대코드로 참여하세요'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '방 만들기'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '초대코드로 참여하기'), findsOneWidget);
  });

  testWidgets('방을 가진 적 없으면(신규) "첫 번째 방을 만들어볼까요?"가 뜬다', (tester) async {
    SharedPreferences.setMockInitialValues({}); // last_viewed_room_id 없음
    await pump(tester);

    expect(find.text('첫 번째 방을 만들어볼까요?'), findsOneWidget);
    expect(find.text('현재 진행 중인 방이 없어요!'), findsNothing);
    // 신규(첫 가입)는 온보딩 게이트 유지 — 시스템 back 차단.
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
  });

  testWidgets('방을 가진 적 있으면(방 다 나감) "현재 진행 중인 방이 없어요!"가 뜬다', (tester) async {
    SharedPreferences.setMockInitialValues({'last_viewed_room_id': 42});
    await pump(tester);

    expect(find.text('현재 진행 중인 방이 없어요!'), findsOneWidget);
    expect(find.text('첫 번째 방을 만들어볼까요?'), findsNothing);
    // returning(방 가졌던 사용자)은 시스템 back 허용(안드로이드 앱 최소화).
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
  });
}
