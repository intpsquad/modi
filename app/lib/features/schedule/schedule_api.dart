import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/env.dart';
import '../auth/authenticated_http_client.dart';

/// 일정 탭(S-20~20-B) API 클라이언트 — specs/0009-일정-탭.md.
/// 인증 헤더와 401 갱신 재시도는 [AuthenticatedHttpClient]가 담당한다.
class ScheduleApi {
  ScheduleApi({this.baseUrl = Env.apiBaseUrl, AuthenticatedHttpClient? client})
    : _client = client ?? appAuthenticatedHttpClient;

  final String baseUrl;
  final AuthenticatedHttpClient _client;

  Future<List<ScheduleItem>> fetchSchedules(
    String idToken,
    int roomId, {
    required DateTime start,
    required DateTime end,
  }) async {
    final response = await _client.get(
      Uri.parse(
        '$baseUrl/rooms/$roomId/schedules'
        '?start=${_formatDate(start)}&end=${_formatDate(end)}',
      ),
      idToken: idToken,
    );
    _checkOk(response, '일정 목록 조회 실패');
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(ScheduleItem.fromJson)
        .toList();
  }

  Future<ScheduleItem> createSchedule(
    String idToken,
    int roomId, {
    required String title,
    required DateTime date,
    String? time,
    DateTime? endDate,
    String? endTime,
    String? detail,
    String? place,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/schedules'),
      idToken: idToken,
      body: jsonEncode({
        'title': title,
        'date': _formatDate(date),
        'time': time,
        'endDate': endDate == null ? null : _formatDate(endDate),
        'endTime': endTime,
        'detail': detail,
        'place': place,
      }),
    );
    if (response.statusCode != 201) {
      throw StateError('일정 생성 실패: ${response.statusCode} ${response.body}');
    }
    return ScheduleItem.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ScheduleItem> updateSchedule(
    String idToken,
    int roomId,
    int scheduleId, {
    required String title,
    required DateTime date,
    String? time,
    DateTime? endDate,
    String? endTime,
    String? detail,
    String? place,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/rooms/$roomId/schedules/$scheduleId'),
      idToken: idToken,
      body: jsonEncode({
        'title': title,
        'date': _formatDate(date),
        'time': time,
        'endDate': endDate == null ? null : _formatDate(endDate),
        'endTime': endTime,
        'detail': detail,
        'place': place,
      }),
    );
    _checkOk(response, '일정 수정 실패');
    return ScheduleItem.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteSchedule(
    String idToken,
    int roomId,
    int scheduleId,
  ) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/rooms/$roomId/schedules/$scheduleId'),
      idToken: idToken,
    );
    if (response.statusCode != 204) {
      throw StateError('일정 삭제 실패: ${response.statusCode} ${response.body}');
    }
  }

  void _checkOk(http.Response response, String message) {
    if (response.statusCode != 200) {
      throw StateError('$message: ${response.statusCode} ${response.body}');
    }
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class ScheduleItem {
  ScheduleItem({
    required this.id,
    required this.title,
    required this.date,
    this.time,
    this.endDate,
    this.endTime,
    this.detail,
    this.place,
  });

  final int id;
  final String title;
  final DateTime date;

  /// 서버 원문 그대로("HH:mm:ss") 보관 — 화면 표시 시점에만 가공한다.
  final String? time;

  /// 다중일 일정의 종료 날짜(선택). `date`와 같으면 서버가 저장 시 null로
  /// 정규화하므로, 이 필드가 null이면 단일일 일정으로 취급한다.
  final DateTime? endDate;

  /// 종료 시간(선택, "HH:mm:ss" 원문). `time`이 있어야 설정 가능(서버 검증).
  final String? endTime;
  final String? detail;

  /// 장소(자유 텍스트). 서버 place 컬럼 — 미반영 시 null 폴백.
  final String? place;

  /// [day]가 이 일정의 날짜 구간(`date` ~ `endDate ?? date`)에 포함되는지.
  /// 월간 그리드 점 표시·선택일 필터가 공유하는 구간 판정.
  bool coversDate(DateTime day) {
    final start = _dateOnly(date);
    final end = _dateOnly(endDate ?? date);
    final target = _dateOnly(day);
    return !target.isBefore(start) && !target.isAfter(end);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    final endDate = json['endDate'] as String?;
    return ScheduleItem(
      id: json['id'] as int,
      title: json['title'] as String,
      date: DateTime.parse(json['date'] as String),
      time: json['time'] as String?,
      endDate: endDate == null ? null : DateTime.parse(endDate),
      endTime: json['endTime'] as String?,
      detail: json['detail'] as String?,
      place: json['place'] as String?,
    );
  }
}
