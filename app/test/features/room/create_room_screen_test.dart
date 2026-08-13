import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/room/create_room_screen.dart';
import 'package:app/features/room/room_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRoomApi extends RoomApi {
  bool createCalled = false;
  DateTime? sentStartDate;
  DateTime? sentEndDate;
  String? sentName;
  String? sentGoal;

  @override
  Future<CreatedRoom> createRoom(
    String idToken, {
    required String name,
    required String goal,
    String? goalDetail,
    required DateTime startDate,
    required DateTime endDate,
    String? coverImage,
  }) async {
    createCalled = true;
    sentName = name;
    sentGoal = goal;
    sentStartDate = startDate;
    sentEndDate = endDate;
    return CreatedRoom(id: 1, name: name, inviteCode: 'ABCDEF');
  }
}

class _FakeAuthService extends AuthService {
  @override
  Future<String> getIdToken() async => 'fake-token';
}

Finder _createButton() => find.widgetWithText(ElevatedButton, '만들기');

void main() {
  testWidgets('이름·목표를 비우면 만들기 버튼이 비활성이고 API가 호출되지 않는다', (tester) async {
    final fakeApi = _FakeRoomApi();
    await tester.pumpWidget(
      MaterialApp(
        home: CreateRoomScreen(api: fakeApi, authService: _FakeAuthService()),
      ),
    );

    expect(tester.widget<ElevatedButton>(_createButton()).onPressed, isNull);
    expect(fakeApi.createCalled, isFalse);
  });

  testWidgets('이름만 채우면 아직 비활성, 목표까지 채우면 활성화된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateRoomScreen(
          api: _FakeRoomApi(),
          authService: _FakeAuthService(),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), '알고리즘 스터디');
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(_createButton()).onPressed,
      isNull,
      reason: '목표가 비어 있으면 아직 비활성',
    );

    await tester.enterText(find.byType(TextField).at(1), '매주 문제 풀기');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(_createButton()).onPressed, isNotNull);
  });

  testWidgets('만들기 시 시작일은 오늘로 자동 전달된다 (시작일 입력 없음)', (tester) async {
    final fakeApi = _FakeRoomApi();
    await tester.pumpWidget(
      MaterialApp(
        home: CreateRoomScreen(api: fakeApi, authService: _FakeAuthService()),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), '알고리즘 스터디');
    await tester.enterText(find.byType(TextField).at(1), '매주 문제 풀기');
    await tester.pump();
    await tester.tap(_createButton());
    await tester.pump();

    expect(fakeApi.createCalled, isTrue);
    expect(fakeApi.sentName, '알고리즘 스터디');
    expect(fakeApi.sentGoal, '매주 문제 풀기');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    expect(fakeApi.sentStartDate, today, reason: '시작일 = 오늘 자동');
    // 종료일 기본값은 오늘+4주 이상(사용자가 안 바꿨으면 오늘보다 뒤).
    expect(fakeApi.sentEndDate!.isAfter(today), isTrue);
  });

  testWidgets('종료 날짜 카드와 안내 문구가 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateRoomScreen(
          api: _FakeRoomApi(),
          authService: _FakeAuthService(),
        ),
      ),
    );

    expect(find.text('종료 날짜'), findsOneWidget);
    expect(find.text('기한이 지나면 방이 자동으로 종료 상태로 전환돼요'), findsOneWidget);
    // 시작일 입력 UI는 없다.
    expect(find.text('시작일'), findsNothing);
  });
}
