import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'room_api.dart';

const _lastRoomIdPrefsKey = 'last_viewed_room_id';

/// `GET /rooms` 응답 한 건 — specs/0008-방-전환.md 데이터 소스.
class RoomSummary {
  RoomSummary({
    required this.id,
    required this.name,
    required this.goal,
    required this.status,
    required this.startDate,
    required this.endDate,
    this.coverImage,
    this.goalDetail,
  });

  final int id;
  final String name;
  final String goal;
  final String status; // 'ACTIVE' | 'ENDED'
  final DateTime startDate;
  final DateTime endDate;

  /// 방 대표 이미지 URL(백엔드 `rooms.cover_image`). 없으면 null. 설정 화면 초기값에 사용.
  final String? coverImage;

  /// 설정 화면에서 기존 목표 상세 설명을 프리필한다.
  final String? goalDetail;

  bool get isActive => status == 'ACTIVE';

  factory RoomSummary.fromMap(Map<String, dynamic> json) => RoomSummary(
    id: json['id'] as int,
    name: json['name'] as String,
    goal: json['goal'] as String,
    status: json['status'] as String,
    startDate: DateTime.parse(json['startDate'] as String),
    endDate: DateTime.parse(json['endDate'] as String),
    coverImage: json['coverImage'] as String?,
    goalDetail: json['goalDetail'] as String?,
  );
}

/// [RoomSession.resolveCurrentRoom]의 결과.
/// [switchedFromEnded]가 true면 이전에 보던 방이 종료돼 다른 방으로 대체됐다는 뜻이라
/// 홈 화면에서 안내 토스트를 띄운다(specs/0003-navigation.md 재진입 리다이렉트).
class RoomResolution {
  const RoomResolution({
    required this.roomId,
    required this.switchedFromEnded,
    this.previousRoomName,
  });

  final int? roomId;
  final bool switchedFromEnded;
  final String? previousRoomName;
}

/// "현재 방" 상태 — specs/0008-방-전환.md. 방 목록 캐시 + 마지막으로 본 방 영속화.
/// AppSession(인증/온보딩 게이팅 전용)과는 책임이 분리된 별도 세션이며,
/// Home/Todos 탭이 동일 인스턴스([appRoomSession])를 공유해 방 전환을 서로 반영한다.
class RoomSession extends ChangeNotifier {
  RoomSession({RoomApi? roomApi}) : _roomApi = roomApi ?? RoomApi();

  final RoomApi _roomApi;

  List<RoomSummary> rooms = [];
  int? currentRoomId;

  Future<void> loadRooms(String idToken) async {
    final raw = await _roomApi.listMyRooms(idToken);
    rooms = raw.map(RoomSummary.fromMap).toList();
  }

  /// 로그아웃·회원 탈퇴처럼 계정 경계가 바뀌는 경우, 다른 사용자에게 이전 방 캐시가
  /// 보이지 않도록 메모리와 마지막 방 선택값을 함께 초기화한다.
  Future<void> clear() async {
    rooms = [];
    currentRoomId = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastRoomIdPrefsKey);
  }

  /// specs/0003-navigation.md 재진입 우선순위 + specs/0008-방-전환.md "마지막 본 방" 영속화.
  /// [loadRooms]로 목록을 채운 뒤에 호출해야 한다.
  Future<RoomResolution> resolveCurrentRoom() async {
    if (rooms.isEmpty) {
      currentRoomId = null;
      return const RoomResolution(roomId: null, switchedFromEnded: false);
    }

    final prefs = await SharedPreferences.getInstance();
    final lastId = currentRoomId ?? prefs.getInt(_lastRoomIdPrefsKey);

    RoomSummary? last;
    if (lastId != null) {
      for (final room in rooms) {
        if (room.id == lastId) {
          last = room;
          break;
        }
      }
    }

    if (last != null && last.isActive) {
      currentRoomId = last.id;
      return RoomResolution(roomId: last.id, switchedFromEnded: false);
    }

    RoomSummary? fallback;
    for (final room in rooms) {
      if (room.isActive) {
        fallback = room;
        break;
      }
    }
    if (fallback == null) {
      currentRoomId = null;
      return const RoomResolution(roomId: null, switchedFromEnded: false);
    }

    currentRoomId = fallback.id;
    await prefs.setInt(_lastRoomIdPrefsKey, fallback.id);
    // last != null이면 이전 방을 찾긴 했으나 ACTIVE가 아니었다는 뜻(=종료됨) → 안내 대상.
    // last == null(이전 기록이 없거나 더 이상 접근 불가)이면 조용히 대체한다.
    return RoomResolution(
      roomId: fallback.id,
      switchedFromEnded: last != null,
      previousRoomName: last?.name,
    );
  }

  /// S-07에서 사용자가 직접 고른 방으로 전환 — 즉시 영속화 + 다른 화면에 알림.
  Future<void> switchRoom(int roomId) async {
    currentRoomId = roomId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastRoomIdPrefsKey, roomId);
    notifyListeners();
  }

  /// 현재 방 화면의 서버 데이터가 바뀐 뒤 홈·탭들이 같은 방을 다시 읽도록 알린다.
  /// 방 전환은 아니므로 마지막 방 영속값은 건드리지 않는다.
  void notifyCurrentRoomDataChanged() => notifyListeners();

  /// 이 계정이 방을 한 번이라도 가진 적 있는가 — "마지막 본 방"(생성·참여 시 기록되고
  /// `clear()`(로그아웃·탈퇴)에서만 지워진다. 방을 다 나가도 남는다) 유무로 판단한다.
  /// 방 없음 허브(S-03)에서 "첫 가입" vs "방을 다 나감"을 구분하는 데 쓴다.
  Future<bool> hasEverEnteredRoom() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastRoomIdPrefsKey) != null;
  }
}

final RoomSession appRoomSession = RoomSession();
