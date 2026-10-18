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

  // --- 삭제(#111) ---

  NotificationHistoryItem item(int id, String title) => NotificationHistoryItem(
    id: id,
    type: 'POKE',
    title: title,
    body: '본문 $id',
    roomId: null,
    read: true,
    createdAt: DateTime.now(),
  );

  Future<_FakeNotificationsApi> pumpWith(
    WidgetTester tester,
    List<NotificationHistoryItem> items, {
    bool failDelete = false,
  }) async {
    final api = _FakeNotificationsApi(items: items, failDelete: failDelete);
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
    return api;
  }

  /// 행을 왼쪽으로 [dx]만큼 민다. 투두 테스트의 `swipeLeft` 와 같은 이유로 드래그 도중 pump 가
  /// 필요하다 — 그래야 끝까지 당겼을 때 DismissiblePane 이 붙어 "끝까지 당겨 삭제"가 된다.
  Future<void> swipeLeft(WidgetTester tester, Finder finder, double dx) async {
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await gesture.moveBy(Offset(-dx / 2, 0));
    await tester.pump();
    await gesture.moveBy(Offset(-dx / 2, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('전체 삭제는 확인 모달을 거쳐 내 알림을 모두 지운다', (tester) async {
    final api = await pumpWith(tester, [item(1, '첫 알림'), item(2, '둘째 알림')]);

    await tester.tap(find.byKey(const Key('notification-delete-all')));
    await tester.pumpAndSettle();
    expect(find.text('알림을 모두 삭제할까요?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notification-delete-all-confirm')));
    await tester.pumpAndSettle();

    expect(api.deleteAllCallCount, 1);
    expect(find.text('첫 알림'), findsNothing);
    expect(find.text('아직 받은 알림이 없어요'), findsOneWidget);
    // 지울 것이 없으면 버튼도 없다.
    expect(find.byKey(const Key('notification-delete-all')), findsNothing);
  });

  testWidgets('전체 삭제 확인 모달에서 취소하면 아무것도 지우지 않는다', (tester) async {
    final api = await pumpWith(tester, [item(1, '첫 알림')]);

    await tester.tap(find.byKey(const Key('notification-delete-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-delete-all-cancel')));
    await tester.pumpAndSettle();

    expect(api.deleteAllCallCount, 0);
    expect(find.text('첫 알림'), findsOneWidget);
  });

  testWidgets('알림이 없으면 전체 삭제 버튼을 보이지 않는다', (tester) async {
    await pumpWith(tester, []);

    expect(find.byKey(const Key('notification-delete-all')), findsNothing);
  });

  testWidgets('전체 삭제가 실패하면 목록을 되살리고 안내한다', (tester) async {
    await pumpWith(tester, [item(1, '첫 알림')], failDelete: true);

    await tester.tap(find.byKey(const Key('notification-delete-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-delete-all-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('첫 알림'), findsOneWidget);
    expect(find.text('삭제에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
  });

  testWidgets('행을 왼쪽으로 밀면 휴지통 버튼이 나오고, 누르면 그 알림만 바로 지운다', (tester) async {
    final api = await pumpWith(tester, [item(1, '첫 알림'), item(2, '둘째 알림')]);

    await swipeLeft(tester, find.text('첫 알림'), 80);
    final trash = find.byKey(const ValueKey('notification-delete-1'));
    expect(trash, findsOneWidget);
    expect(
      find.descendant(of: trash, matching: find.byIcon(Icons.delete_outline)),
      findsOneWidget,
    );

    await tester.tap(trash);
    await tester.pumpAndSettle();

    expect(api.deletedIds, [1]);
    expect(find.text('첫 알림'), findsNothing);
    expect(find.text('둘째 알림'), findsOneWidget);
  });

  testWidgets('끝까지 밀면 버튼을 누르지 않아도 바로 지운다', (tester) async {
    final api = await pumpWith(tester, [item(1, '첫 알림'), item(2, '둘째 알림')]);

    await swipeLeft(tester, find.text('둘째 알림'), 500);

    expect(api.deletedIds, [2]);
    expect(find.text('둘째 알림'), findsNothing);
    expect(find.text('첫 알림'), findsOneWidget);
  });

  testWidgets('한 건 삭제가 실패하면 그 알림을 제자리에 되살리고 안내한다', (tester) async {
    await pumpWith(tester, [
      item(1, '첫 알림'),
      item(2, '둘째 알림'),
      item(3, '셋째 알림'),
    ], failDelete: true);

    await swipeLeft(tester, find.text('둘째 알림'), 500);

    expect(find.text('둘째 알림'), findsOneWidget);
    expect(find.text('삭제에 실패했어요. 다시 시도해 주세요'), findsOneWidget);
    // 제자리 — 첫 알림과 셋째 알림 사이.
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('첫 알림') < y('둘째 알림') && y('둘째 알림') < y('셋째 알림'), isTrue);
  });
}

class _FakeNotificationsApi extends NotificationsApi {
  _FakeNotificationsApi({
    required this.items,
    this.shouldFailFirst = false,
    this.failDelete = false,
  });

  final List<NotificationHistoryItem> items;
  final bool shouldFailFirst;
  final bool failDelete;
  int _fetchCallCount = 0;
  int markAllReadCallCount = 0;
  int deleteAllCallCount = 0;
  final List<int> deletedIds = [];

  @override
  Future<void> deleteNotification(String idToken, int id) async {
    if (failDelete) throw StateError('알림 삭제 실패');
    deletedIds.add(id);
  }

  @override
  Future<void> deleteAll(String idToken) async {
    if (failDelete) throw StateError('알림 전체 삭제 실패');
    deleteAllCallCount++;
  }

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
