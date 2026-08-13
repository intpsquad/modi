import 'package:app/features/notifications/notification_router.dart';
import 'package:app/features/room/room_session.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRoomSession extends RoomSession {
  int? switchedTo;

  @override
  Future<void> switchRoom(int roomId) async {
    switchedTo = roomId;
    currentRoomId = roomId;
  }
}

void main() {
  group('notificationRouteFor', () {
    test('type을 해당 탭 경로로 매핑한다', () {
      expect(notificationRouteFor({'type': 'POKE'}), '/todos');
      expect(notificationRouteFor({'type': 'ASSIGNED_TODO_ADDED'}), '/todos');
      expect(
        notificationRouteFor({'type': 'SCHEDULE_DAY_BEFORE'}),
        '/schedule',
      );
      expect(notificationRouteFor({'type': 'SCHEDULE_DDAY'}), '/schedule');
      expect(
        notificationRouteFor({'type': 'ROOM_MEMBER_JOINED'}),
        '/mypage/members',
      );
      expect(
        notificationRouteFor({'type': 'ROOM_MEMBER_LEFT'}),
        '/mypage/members',
      );
      expect(
        notificationRouteFor({'type': 'ARCHIVE_ANALYSIS_DONE'}),
        '/archive',
      );
    });

    test('소문자 type도 매핑되고, 모르는/빈 type은 null', () {
      expect(notificationRouteFor({'type': 'poke'}), '/todos');
      expect(notificationRouteFor({'type': 'UNKNOWN'}), isNull);
      expect(notificationRouteFor(<String, dynamic>{}), isNull);
    });
  });

  group('notificationRoomId', () {
    test('문자열/정수 roomId를 파싱하고 없으면 null', () {
      expect(notificationRoomId({'roomId': '42'}), 42);
      expect(notificationRoomId({'roomId': 7}), 7);
      expect(notificationRoomId(<String, dynamic>{}), isNull);
      expect(notificationRoomId({'roomId': 'x'}), isNull);
    });
  });

  group('handleNotificationData', () {
    test('다른 방이면 전환 후 매핑 경로로 이동한다', () async {
      final session = _FakeRoomSession()..currentRoomId = 1;
      String? navigatedTo;

      await handleNotificationData(
        {'type': 'POKE', 'roomId': '42'},
        navigate: (location) => navigatedTo = location,
        roomSession: session,
      );

      expect(session.switchedTo, 42);
      expect(navigatedTo, '/todos');
    });

    test('같은 방이면 전환하지 않고 이동만 한다', () async {
      final session = _FakeRoomSession()..currentRoomId = 42;
      String? navigatedTo;

      await handleNotificationData(
        {'type': 'SCHEDULE_DDAY', 'roomId': '42'},
        navigate: (location) => navigatedTo = location,
        roomSession: session,
      );

      expect(session.switchedTo, isNull);
      expect(navigatedTo, '/schedule');
    });

    test('모르는 type이면 전환도 이동도 하지 않는다', () async {
      final session = _FakeRoomSession()..currentRoomId = 1;
      var navigated = false;

      await handleNotificationData(
        {'type': 'NOPE', 'roomId': '42'},
        navigate: (_) => navigated = true,
        roomSession: session,
      );

      expect(session.switchedTo, isNull);
      expect(navigated, isFalse);
    });
  });
}
