import 'package:app/features/home/ended_room_summary_screen.dart';
import 'package:app/features/settings/settings_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('S-05는 종료 성과를 읽기 전용으로 요약한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EndedRoomSummaryScreen(
          roomId: 9,
          api: _FakePastRoomApi(),
          tokenLoader: () async => 'token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('봄학기 CS 스터디'), findsOneWidget);
    expect(find.text('읽기전용'), findsWidgets);
    expect(find.text('최종 목표 달성 현황'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    expect(find.text('재시작'), findsOneWidget);
  });
}

class _FakePastRoomApi extends SettingsApi {
  @override
  Future<List<PastRoom>> fetchPastRooms(String idToken) async {
    return [
      PastRoom(
        id: 9,
        name: '봄학기 CS 스터디',
        startDate: DateTime(2026, 5, 20),
        endDate: DateTime(2026, 6, 25),
        completionRate: 0.87,
      ),
    ];
  }
}
