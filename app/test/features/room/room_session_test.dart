import 'package:app/features/room/room_api.dart';
import 'package:app/features/room/room_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRoomApi extends RoomApi {
  _FakeRoomApi(this.rooms);

  final List<Map<String, dynamic>> rooms;

  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async => rooms;
}

Map<String, dynamic> _room({
  required int id,
  required String name,
  required String status,
}) => {
  'id': id,
  'name': name,
  'goal': '목표-$id',
  'status': status,
  'startDate': '2026-01-01',
  'endDate': '2026-12-31',
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('영속화된 마지막 방이 없으면 첫 번째 ACTIVE 방을 고른다', () async {
    final session = RoomSession(
      roomApi: _FakeRoomApi([
        _room(id: 1, name: '방1', status: 'ACTIVE'),
        _room(id: 2, name: '방2', status: 'ACTIVE'),
      ]),
    );
    await session.loadRooms('token');

    final resolution = await session.resolveCurrentRoom();

    expect(resolution.roomId, 1);
    expect(resolution.switchedFromEnded, false);
    expect(session.currentRoomId, 1);
  });

  test('마지막으로 본 방이 ACTIVE면 그대로 유지한다', () async {
    SharedPreferences.setMockInitialValues({'last_viewed_room_id': 2});
    final session = RoomSession(
      roomApi: _FakeRoomApi([
        _room(id: 1, name: '방1', status: 'ACTIVE'),
        _room(id: 2, name: '방2', status: 'ACTIVE'),
      ]),
    );
    await session.loadRooms('token');

    final resolution = await session.resolveCurrentRoom();

    expect(resolution.roomId, 2);
    expect(resolution.switchedFromEnded, false);
  });

  test('현재 방을 나가 목록에서 사라지면 다른 ACTIVE 방으로 전환한다 (방 나가기)', () async {
    // 방1을 보다가 나갔다 — currentRoomId는 1로 남아 있지만 목록엔 방2만 있다.
    final session = RoomSession(
      roomApi: _FakeRoomApi([_room(id: 2, name: '방2', status: 'ACTIVE')]),
    );
    session.currentRoomId = 1;
    await session.loadRooms('token');

    final resolution = await session.resolveCurrentRoom();

    expect(resolution.roomId, 2);
    expect(session.currentRoomId, 2);
  });

  test('마지막 방을 나가 방이 0개가 되면 roomId는 null이다 (방 나가기)', () async {
    final session = RoomSession(roomApi: _FakeRoomApi([]));
    session.currentRoomId = 1;
    await session.loadRooms('token');

    final resolution = await session.resolveCurrentRoom();

    expect(resolution.roomId, isNull);
    expect(session.currentRoomId, isNull);
  });

  test('마지막으로 본 방이 종료됐으면 다른 ACTIVE 방으로 전환하고 안내 플래그를 켠다', () async {
    SharedPreferences.setMockInitialValues({'last_viewed_room_id': 1});
    final session = RoomSession(
      roomApi: _FakeRoomApi([
        _room(id: 1, name: '끝난방', status: 'ENDED'),
        _room(id: 2, name: '방2', status: 'ACTIVE'),
      ]),
    );
    await session.loadRooms('token');

    final resolution = await session.resolveCurrentRoom();

    expect(resolution.roomId, 2);
    expect(resolution.switchedFromEnded, true);
    expect(resolution.previousRoomName, '끝난방');
  });

  test('ACTIVE 방이 하나도 없으면 roomId는 null이다', () async {
    SharedPreferences.setMockInitialValues({'last_viewed_room_id': 1});
    final session = RoomSession(
      roomApi: _FakeRoomApi([_room(id: 1, name: '끝난방', status: 'ENDED')]),
    );
    await session.loadRooms('token');

    final resolution = await session.resolveCurrentRoom();

    expect(resolution.roomId, null);
    expect(resolution.switchedFromEnded, false);
  });

  test('방이 하나도 없으면 roomId는 null이고 예외를 던지지 않는다', () async {
    final session = RoomSession(roomApi: _FakeRoomApi([]));
    await session.loadRooms('token');

    final resolution = await session.resolveCurrentRoom();

    expect(resolution.roomId, null);
  });

  test('switchRoom은 즉시 반영되고 영속화되며 리스너에게 알린다', () async {
    final session = RoomSession(
      roomApi: _FakeRoomApi([
        _room(id: 1, name: '방1', status: 'ACTIVE'),
        _room(id: 2, name: '방2', status: 'ACTIVE'),
      ]),
    );
    await session.loadRooms('token');
    var notified = false;
    session.addListener(() => notified = true);

    await session.switchRoom(2);

    expect(session.currentRoomId, 2);
    expect(notified, true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('last_viewed_room_id'), 2);
  });

  test('switchRoom으로 저장한 값은 새 세션 인스턴스에서도 유지된다(재진입 시뮬레이션)', () async {
    final firstSession = RoomSession(
      roomApi: _FakeRoomApi([
        _room(id: 1, name: '방1', status: 'ACTIVE'),
        _room(id: 2, name: '방2', status: 'ACTIVE'),
      ]),
    );
    await firstSession.loadRooms('token');
    await firstSession.switchRoom(2);

    final reopenedSession = RoomSession(
      roomApi: _FakeRoomApi([
        _room(id: 1, name: '방1', status: 'ACTIVE'),
        _room(id: 2, name: '방2', status: 'ACTIVE'),
      ]),
    );
    await reopenedSession.loadRooms('token');
    final resolution = await reopenedSession.resolveCurrentRoom();

    expect(resolution.roomId, 2);
  });

  test('계정 탈퇴 후 clear는 방 캐시와 마지막 방 영속값을 모두 제거한다', () async {
    final session = RoomSession(
      roomApi: _FakeRoomApi([_room(id: 1, name: '방1', status: 'ACTIVE')]),
    );
    await session.loadRooms('token');
    await session.switchRoom(1);

    await session.clear();

    expect(session.rooms, isEmpty);
    expect(session.currentRoomId, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('last_viewed_room_id'), isNull);
  });
}
