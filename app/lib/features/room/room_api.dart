import 'dart:convert';

import '../../config/env.dart';
import '../auth/authenticated_http_client.dart';

/// 방 생성/초대코드 미리보기/참여/내 방 목록 API 클라이언트 (specs/0004-방-생성-참여.md).
/// 인증 헤더와 일반 요청의 401 갱신 재시도는 [AuthenticatedHttpClient]가 담당한다.
/// baseUrl 기본값/오버라이드는 config/env.dart 참고.
class RoomApi {
  RoomApi({this.baseUrl = Env.apiBaseUrl, AuthenticatedHttpClient? client})
    : _client = client ?? appAuthenticatedHttpClient;

  final String baseUrl;
  final AuthenticatedHttpClient _client;

  Future<CreatedRoom> createRoom(
    String idToken, {
    required String name,
    required String goal,
    String? goalDetail,
    required DateTime startDate,
    required DateTime endDate,
    String? coverImage,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms'),
      idToken: idToken,
      body: jsonEncode({
        'name': name,
        'goal': goal,
        'goalDetail': goalDetail,
        'startDate': _formatDate(startDate),
        'endDate': _formatDate(endDate),
        'coverImage': coverImage,
      }),
    );
    if (response.statusCode != 201) {
      throw StateError('방 만들기 실패: ${response.statusCode} ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return CreatedRoom(
      id: body['id'] as int,
      name: body['name'] as String,
      inviteCode: body['inviteCode'] as String,
    );
  }

  /// 대표 이미지 업로드(2단계 계약 1단계) — 파일을 올리고 접근 URL 문자열을 받는다.
  /// 방에 묶이지 않은 범용 엔드포인트(방 생성 전에도 사용). 받은 URL을 방 생성/설정의
  /// `coverImage` 필드로 저장한다. 백엔드 계약: `docs/api/room-cover-image.md`.
  Future<String> uploadCoverImage(
    String idToken, {
    required List<int> bytes,
    required String filename,
  }) async {
    final response = await _client.sendMultipart(
      Uri.parse('$baseUrl/rooms/cover-image'),
      idToken: idToken,
      fileField: 'image',
      bytes: bytes,
      filename: filename,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw StateError(
        '대표 이미지 업로드 실패: ${response.statusCode} ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['coverImage'] as String;
  }

  Future<InvitePreview> previewInvite(String idToken, String code) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/invite-codes/$code'),
      idToken: idToken,
    );
    if (response.statusCode == 404) {
      throw InviteNotFoundException();
    }
    if (response.statusCode != 200) {
      throw StateError('초대코드 확인 실패: ${response.statusCode} ${response.body}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return InvitePreview(
      roomId: body['roomId'] as int,
      name: body['name'] as String,
      goal: body['goal'] as String,
      status: body['status'] as String,
      // 아래 3개는 백엔드가 아직 안 줄 수 있어 방어적으로 파싱(없으면 null).
      memberCount: body['memberCount'] as int?,
      startDate: _tryParseDate(body['startDate']),
      endDate: _tryParseDate(body['endDate']),
    );
  }

  static DateTime? _tryParseDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  Future<void> joinRoom(String idToken, String code) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/invite-codes/$code/join'),
      idToken: idToken,
    );
    if (response.statusCode == 404) {
      throw InviteNotFoundException();
    }
    if (response.statusCode == 409) {
      throw RoomEndedException();
    }
    if (response.statusCode != 200) {
      throw StateError('방 참여 실패: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms'),
      idToken: idToken,
      // AppSession이 기존 부팅 계약대로 401 갱신·로그아웃을 직접 처리한다.
      retryOnUnauthorized: false,
    );
    if (response.statusCode != 200) {
      throw RoomApiException(
        statusCode: response.statusCode,
        operation: '내 방 목록 조회',
      );
    }
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// 방 API 호출 실패를 인증 부팅 흐름이 상태별로 처리할 수 있게 하는 예외.
class RoomApiException implements Exception {
  const RoomApiException({required this.statusCode, required this.operation});

  final int statusCode;
  final String operation;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => '$operation 실패 (HTTP $statusCode)';
}

class CreatedRoom {
  CreatedRoom({required this.id, required this.name, required this.inviteCode});

  final int id;
  final String name;
  final String inviteCode;
}

class InvitePreview {
  InvitePreview({
    required this.roomId,
    required this.name,
    required this.goal,
    required this.status,
    this.memberCount,
    this.startDate,
    this.endDate,
  });

  final int roomId;
  final String name;
  final String goal;
  final String status;

  /// 참여 확인 모달 메타("멤버 N명 · 기간")용 — preview API가 아직 안 주면 null.
  /// 백엔드가 `GET /invite-codes/{code}`에 memberCount·startDate·endDate를
  /// 추가하면 채워진다. 그 전까지 모달은 goal로 폴백한다.
  final int? memberCount;
  final DateTime? startDate;
  final DateTime? endDate;
}

/// 코드가 없거나 만료된 경우(404).
class InviteNotFoundException implements Exception {}

/// 종료된(ENDED) 방에 참여를 시도한 경우(409).
class RoomEndedException implements Exception {}
