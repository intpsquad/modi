import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/env.dart';
import '../auth/authenticated_http_client.dart';

/// 알림 내역 한 건(specs/0017-알림-내역.md, S-41).
class NotificationHistoryItem {
  const NotificationHistoryItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.roomId,
    required this.read,
    required this.createdAt,
  });

  factory NotificationHistoryItem.fromJson(Map<String, dynamic> json) {
    return NotificationHistoryItem(
      id: json['id'] as int,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      roomId: json['roomId'] as int?,
      read: json['read'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  final int id;
  final String type;
  final String title;
  final String body;
  final int? roomId;
  final bool read;
  final DateTime createdAt;
}

/// `GET/POST/DELETE /me/notifications*` — specs/0017-알림-내역.md.
class NotificationsApi {
  NotificationsApi({
    this.baseUrl = Env.apiBaseUrl,
    AuthenticatedHttpClient? client,
  }) : _client = client ?? appAuthenticatedHttpClient;

  final String baseUrl;
  final AuthenticatedHttpClient _client;

  Future<List<NotificationHistoryItem>> fetchHistory(String idToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/me/notifications'),
      idToken: idToken,
    );
    _checkOk(response, '알림 내역 조회');
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(NotificationHistoryItem.fromJson)
        .toList();
  }

  Future<int> fetchUnreadCount(String idToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/me/notifications/unread-count'),
      idToken: idToken,
    );
    _checkOk(response, '안읽은 알림 개수 조회');
    return (jsonDecode(response.body) as Map<String, dynamic>)['count'] as int;
  }

  Future<void> markAllRead(String idToken) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/me/notifications/read-all'),
      idToken: idToken,
    );
    if (response.statusCode != 204) {
      throw StateError('알림 읽음 처리 실패 (${response.statusCode})');
    }
  }

  /// 알림 한 건 삭제(#111). 404 는 성공으로 본다 — 다른 기기에서 지웠거나 90일 보존 배치가
  /// 먼저 지운 알림이라, 화면에서 없애려던 목적은 이미 이뤄졌다.
  Future<void> deleteNotification(String idToken, int id) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/me/notifications/$id'),
      idToken: idToken,
    );
    if (response.statusCode != 204 && response.statusCode != 404) {
      throw StateError('알림 삭제 실패 (${response.statusCode})');
    }
  }

  /// 내 알림 전체 삭제(#111).
  Future<void> deleteAll(String idToken) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/me/notifications'),
      idToken: idToken,
    );
    if (response.statusCode != 204) {
      throw StateError('알림 전체 삭제 실패 (${response.statusCode})');
    }
  }

  void _checkOk(http.Response response, String operation) {
    if (response.statusCode != 200) {
      throw StateError('$operation 실패 (${response.statusCode})');
    }
  }
}
