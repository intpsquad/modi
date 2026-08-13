import 'package:app/features/notifications/notification_history_screen.dart';
import 'package:app/features/notifications/notifications_api.dart';
import 'package:app/features/room/room_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: child);

  testWidgets('목록을 불러오면 제목·본문이 보이고 진입 시 전체 읽음 처리를 호출한다', (tester) async {
    final api = _FakeNotificationsApi(
      items: [
        NotificationHistoryItem(
          id: 1,
          type: 'POKE',
          title: '민지님의 콕찌르기',
          body: '여름 스터디 방에서 투두를 확인해보세요',
          roomId: 7,
          read: false,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      ],
    );

    await tester.pumpWidget(
      host(
        NotificationHistoryScreen(
          api: api,
          tokenLoader: () async => 'token',
          roomSession: RoomSession(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('민지님의 콕찌르기'), findsOneWidget);
    expect(find.text('여름 스터디 방에서 투두를 확인해보세요'), findsOneWidget);
    expect(api.markAllReadCallCount, 1);
  });

  testWidgets('알림이 없으면 빈 상태 문구를 보인다', (tester) async {
    await tester.pumpWidget(
      host(
        NotificationHistoryScreen(
          api: _FakeNotificationsApi(items: []),
          tokenLoader: () async => 'token',
          roomSession: RoomSession(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아직 받은 알림이 없어요'), findsOneWidget);
  });

  testWidgets('로드 실패 시 에러 안내와 재시도 버튼이 보이고, 재시도하면 다시 호출한다', (tester) async {
    final api = _FakeNotificationsApi(items: [], shouldFailFirst: true);

    await tester.pumpWidget(
      host(
        NotificationHistoryScreen(
          api: api,
          tokenLoader: () async => 'token',
          roomSession: RoomSession(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('알림 내역을 불러오지 못했어요'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('아직 받은 알림이 없어요'), findsOneWidget);
  });

  testWidgets('연결된 방이 이미 없어졌으면 탭해도 이동하지 않고 안내만 뜬다', (tester) async {
    final api = _FakeNotificationsApi(
      items: [
        NotificationHistoryItem(
          id: 1,
          type: 'ASSIGNED_TODO_ADDED',
          title: '새 투두가 도착했어요',
          body: '없어진 방 · 청소하기',
          roomId: 999,
          read: false,
          createdAt: DateTime.now(),
        ),
      ],
    );

    await tester.pumpWidget(
      host(
        NotificationHistoryScreen(
          api: api,
          tokenLoader: () async => 'token',
          roomSession: RoomSession(), // rooms가 비어 있어 999는 없는 방.
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('새 투두가 도착했어요'));
    await tester.pumpAndSettle();

    expect(find.text('이미 없어진 방이에요'), findsOneWidget);
  });
}

class _FakeNotificationsApi extends NotificationsApi {
  _FakeNotificationsApi({required this.items, this.shouldFailFirst = false});

  final List<NotificationHistoryItem> items;
  final bool shouldFailFirst;
  int _fetchCallCount = 0;
  int markAllReadCallCount = 0;

  @override
  Future<List<NotificationHistoryItem>> fetchHistory(String idToken) async {
    _fetchCallCount++;
    if (shouldFailFirst && _fetchCallCount == 1) {
      throw StateError('알림 내역 조회 실패');
    }
    return items;
  }

  @override
  Future<void> markAllRead(String idToken) async {
    markAllReadCallCount++;
  }
}
