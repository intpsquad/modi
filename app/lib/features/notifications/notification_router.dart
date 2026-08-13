import '../../routing/app_router.dart';
import '../room/room_session.dart';

/// 푸시 `data` 페이로드 → 앱 내 이동 처리.
///
/// 서버가 푸시에 실어주는 계약(`docs/backend/notification-deeplink-handoff.md`):
/// ```
/// data: { "type": "<PUSH_TYPE>", "roomId": "<방 id, 선택>", ... }
/// ```
/// FCM `data`는 값이 전부 문자열이다. `type`이 없거나 모르는 값이면 이동하지 않는다
/// (앱만 열림 — 회귀 없음). 서버가 아직 `data`를 안 실어주면 자연히 no-op이다.

/// [data.type] → 이동할 탭/화면 경로. 모르는 type은 null.
String? notificationRouteFor(Map<String, dynamic> data) {
  final type = (data['type'] as String?)?.toUpperCase();
  switch (type) {
    case 'POKE':
    case 'ASSIGNED_TODO_ADDED':
      return '/todos';
    case 'SCHEDULE_DAY_BEFORE':
    case 'SCHEDULE_DDAY':
      return '/schedule';
    case 'ROOM_MEMBER_JOINED':
    case 'ROOM_MEMBER_LEFT':
      return '/mypage/members';
    case 'ARCHIVE_ANALYSIS_DONE':
      return '/archive';
    default:
      return null;
  }
}

/// [data.roomId]를 int로 파싱(FCM data는 문자열). 없으면 null.
int? notificationRoomId(Map<String, dynamic> data) {
  final raw = data['roomId'];
  if (raw is int) return raw;
  if (raw is String) return int.tryParse(raw);
  return null;
}

typedef NotificationNavigate = void Function(String location);

/// 알림 탭 시 호출 — 해당 방으로 전환(다른 방이면)한 뒤 매핑된 화면으로 이동한다.
/// [navigate]/[roomSession]은 테스트 주입용(기본 [appRouter]/[appRoomSession]).
Future<void> handleNotificationData(
  Map<String, dynamic> data, {
  NotificationNavigate? navigate,
  RoomSession? roomSession,
}) async {
  final route = notificationRouteFor(data);
  if (route == null) return;

  final session = roomSession ?? appRoomSession;
  final roomId = notificationRoomId(data);
  if (roomId != null && roomId != session.currentRoomId) {
    await session.switchRoom(roomId);
  }

  (navigate ?? appRouter.go)(route);
}
