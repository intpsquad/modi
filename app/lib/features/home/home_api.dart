import 'dart:convert';

import '../../config/env.dart';
import '../auth/authenticated_http_client.dart';
import '../todos/todos_api.dart' show TodoNotAssigneeException;

/// 홈 대시보드(S-04) 조회 + 오늘투두 체크박스 토글 API 클라이언트 (specs/0005-홈-대시보드.md).
/// 인증 헤더와 401 갱신 재시도는 [AuthenticatedHttpClient]가 담당한다.
class HomeApi {
  HomeApi({this.baseUrl = Env.apiBaseUrl, AuthenticatedHttpClient? client})
    : _client = client ?? appAuthenticatedHttpClient;

  final String baseUrl;
  final AuthenticatedHttpClient _client;

  Future<DashboardData> fetchDashboard(
    String idToken,
    int roomId, {
    required DateTime weekStart,
    required DateTime weekEnd,
  }) async {
    final uri = Uri.parse('$baseUrl/rooms/$roomId/dashboard').replace(
      queryParameters: {
        'weekStart': _formatDate(weekStart),
        'weekEnd': _formatDate(weekEnd),
      },
    );
    final response = await _client.get(uri, idToken: idToken);
    if (response.statusCode == 403) {
      throw NotRoomMemberException();
    }
    if (response.statusCode != 200) {
      throw StateError('홈 대시보드 조회 실패: ${response.statusCode} ${response.body}');
    }
    return DashboardData.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> setTodoCompleted(
    String idToken,
    int roomId,
    int todoId,
    bool completed,
  ) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId/todos/$todoId'),
      idToken: idToken,
      body: jsonEncode({'completed': completed}),
    );
    // FR-39: 담당자 아닌 투두 완료 시도(403)는 담당자 전용 안내 문구로 구분한다.
    if (response.statusCode == 403) {
      throw TodoNotAssigneeException.fromResponse(response);
    }
    if (response.statusCode != 200) {
      throw StateError('투두 완료 처리 실패: ${response.statusCode} ${response.body}');
    }
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class DashboardData {
  DashboardData({
    required this.room,
    required this.members,
    required this.weekSchedules,
    required this.todayTodos,
    required this.recentArchives,
    List<ArchiveBrief>? previewArchives,
    this.todoDone,
    this.todoTotal,
    this.activities = const [],
    // 공개 파라미터(previewArchives)를 private 백킹 필드에 담아 같은 이름의 폴백 게터로
    // 노출한다 — 초기화 포멀로는 표현 불가한 의도된 패턴.
    // ignore: prefer_initializing_formals
  }) : _previewArchives = previewArchives;

  final RoomInfo room;
  final List<MemberProgress> members;
  final List<ScheduleBrief> weekSchedules;
  final List<TodoBrief> todayTodos;

  /// 순수 최신순 자료(등록순). 홈 외 다른 화면이 최신순을 그대로 쓸 수 있어 유지한다.
  final List<ArchiveBrief> recentArchives;

  /// 홈 미리보기 전용(백엔드 `previewArchives` — 핀 우선·최대 4). 서버 미반영 시 null이며
  /// 이때는 [recentArchives](최신순)로 폴백한다(2026-08-07, forward-compatible).
  final List<ArchiveBrief>? _previewArchives;

  /// 홈 모아보기 미리보기에 쓸 자료 — 핀 우선(있으면), 없으면 최신순 폴백.
  List<ArchiveBrief> get previewArchives => _previewArchives ?? recentArchives;

  /// 홈 활동 피드(docs/backend/home-activity-feed.md) — 최신·중요순, 최근 20건.
  /// 서버 미반영 시 빈 리스트(기존 팀 진행률·D-day 문구만 배너에 남는다).
  final List<ActivityEvent> activities;

  /// 방 전체 투두 완료/전체 개수(백엔드 정확값) — 히어로 진행률 바 & "완료 n · 전체 m"에 사용.
  /// 백엔드 미반영 시 null이며, 이때는 멤버 담당 합산 근사치로 대체한다(아래 display* 참고).
  final int? todoDone;
  final int? todoTotal;

  // 멤버 담당 합산 근사치 — 다중 담당자 투두를 중복집계할 수 있어 백엔드 정확값(todoTotal)으로 교체 대상.
  int get _memberAssignedDone =>
      members.fold(0, (sum, m) => sum + m.assignedDone);
  int get _memberAssignedTotal =>
      members.fold(0, (sum, m) => sum + m.assignedTotal);

  /// 표시용 완료 개수 — 백엔드 정확값이 있으면 그 값, 없으면 멤버 합산 근사치.
  int? get displayTodoDone => todoTotal != null
      ? todoDone
      : (_memberAssignedTotal > 0 ? _memberAssignedDone : null);

  /// 표시용 전체 개수 — 백엔드 정확값이 있으면 그 값, 없으면 멤버 합산 근사치.
  int? get displayTodoTotal =>
      todoTotal ?? (_memberAssignedTotal > 0 ? _memberAssignedTotal : null);

  /// 진행률이 근사치(멤버 합산)인지 여부 — 백엔드 정확값이 오면 false.
  bool get isTodoProgressApproximate =>
      todoTotal == null && _memberAssignedTotal > 0;

  /// 0.0~1.0. 표시할 값이 없으면 null(진행률 바 숨김).
  double? get todoProgress {
    final total = displayTodoTotal;
    final done = displayTodoDone;
    if (total == null || done == null || total == 0) return null;
    return (done / total).clamp(0, 1).toDouble();
  }

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      room: RoomInfo.fromJson(json['room'] as Map<String, dynamic>),
      members: (json['members'] as List)
          .cast<Map<String, dynamic>>()
          .map(MemberProgress.fromJson)
          .toList(),
      weekSchedules: (json['weekSchedules'] as List)
          .cast<Map<String, dynamic>>()
          .map(ScheduleBrief.fromJson)
          .toList(),
      todayTodos: (json['todayTodos'] as List)
          .cast<Map<String, dynamic>>()
          .map(TodoBrief.fromJson)
          .toList(),
      recentArchives: (json['recentArchives'] as List)
          .cast<Map<String, dynamic>>()
          .map(ArchiveBrief.fromJson)
          .toList(),
      // 백엔드가 아직 안 내려주면 null → getter가 recentArchives로 폴백.
      previewArchives: (json['previewArchives'] as List?)
          ?.cast<Map<String, dynamic>>()
          .map(ArchiveBrief.fromJson)
          .toList(),
      todoDone: json['todoDone'] as int?,
      todoTotal: json['todoTotal'] as int?,
      activities: json['activities'] == null
          ? const []
          : (json['activities'] as List)
                .cast<Map<String, dynamic>>()
                .map(ActivityEvent.fromJson)
                .toList(),
    );
  }
}

/// 홈 활동 피드 항목 하나(docs/backend/home-activity-feed.md). 문구는 [homeActivityMessages]가
/// 조립한다 — 이 클래스는 서버 응답을 그대로 옮긴 구조화된 값만 갖는다.
class ActivityEvent {
  ActivityEvent({
    required this.type,
    this.actorNickname,
    this.actorUserId,
    this.count,
    this.targetName,
    this.secondaryCount,
    required this.createdAt,
  });

  final String type;
  final String? actorNickname;
  final String? actorUserId;
  final int? count;

  /// 타입에 따라 뜻이 다르다 — 대상이 사람이면(POKE) 닉네임, 자료면(ARCHIVE_ADDED) 폴더/자료 이름.
  final String? targetName;

  /// WEEKLY_SUMMARY 전용(지난주 대비 증감) — 그 외 타입은 항상 null.
  final int? secondaryCount;
  final DateTime createdAt;

  factory ActivityEvent.fromJson(Map<String, dynamic> json) {
    return ActivityEvent(
      type: json['type'] as String,
      actorNickname: json['actorNickname'] as String?,
      actorUserId: json['actorUserId'] as String?,
      count: json['count'] as int?,
      targetName: json['targetName'] as String?,
      secondaryCount: json['secondaryCount'] as int?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class RoomInfo {
  RoomInfo({
    required this.id,
    required this.name,
    required this.goal,
    this.goalDetail,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.coverImageUrl,
  });

  final int id;
  final String name;
  final String goal;
  final String? goalDetail;
  final DateTime startDate;
  final DateTime endDate;
  final String status;

  /// 히어로 배경 커버 이미지(백엔드 `rooms.cover_image`, 0002). null이면 그라데이션 폴백(specs/0005).
  final String? coverImageUrl;

  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    return RoomInfo(
      id: json['id'] as int,
      name: json['name'] as String,
      goal: json['goal'] as String,
      goalDetail: json['goalDetail'] as String?,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      status: json['status'] as String,
      coverImageUrl: json['coverImage'] as String?,
    );
  }

  /// D-day = 오늘부터 종료일까지 남은 일수(specs/0005-홈-대시보드.md, 클라이언트 로컬 타임존 기준).
  int get daysRemaining {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return endDate.difference(todayDate).inDays;
  }
}

class MemberProgress {
  MemberProgress({
    required this.userId,
    required this.nickname,
    this.profileImage,
    required this.assignedTotal,
    required this.assignedDone,
  });

  final String userId;
  final String nickname;
  final String? profileImage;
  final int assignedTotal;
  final int assignedDone;

  /// 0.0~1.0. 담당 투두가 없으면 0(design.md §5 "0%면 트랙만 보이고").
  double get progressRatio =>
      assignedTotal == 0 ? 0 : assignedDone / assignedTotal;

  factory MemberProgress.fromJson(Map<String, dynamic> json) {
    return MemberProgress(
      userId: json['userId'] as String,
      nickname: json['nickname'] as String,
      profileImage: json['profileImage'] as String?,
      assignedTotal: json['assignedTotal'] as int,
      assignedDone: json['assignedDone'] as int,
    );
  }
}

class ScheduleBrief {
  ScheduleBrief({
    required this.id,
    required this.title,
    required this.date,
    this.time,
    this.endDate,
    this.endTime,
  });

  final int id;
  final String title;
  final DateTime date;
  final String? time;

  /// 다중일 일정의 종료 날짜(선택) — specs/0009 §데이터.
  final DateTime? endDate;

  /// 종료 시간(선택, "HH:mm:ss" 원문).
  final String? endTime;

  /// [day]가 이 일정의 날짜 구간(`date` ~ `endDate ?? date`)에 포함되는지.
  bool coversDate(DateTime day) {
    final start = _dateOnly(date);
    final end = _dateOnly(endDate ?? date);
    final target = _dateOnly(day);
    return !target.isBefore(start) && !target.isAfter(end);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  factory ScheduleBrief.fromJson(Map<String, dynamic> json) {
    final endDate = json['endDate'] as String?;
    return ScheduleBrief(
      id: json['id'] as int,
      title: json['title'] as String,
      date: DateTime.parse(json['date'] as String),
      time: json['time'] as String?,
      endDate: endDate == null ? null : DateTime.parse(endDate),
      endTime: json['endTime'] as String?,
    );
  }
}

class TodoBrief {
  TodoBrief({required this.id, required this.title, required this.completed});

  final int id;
  final String title;
  final bool completed;

  TodoBrief copyWith({bool? completed}) =>
      TodoBrief(id: id, title: title, completed: completed ?? this.completed);

  factory TodoBrief.fromJson(Map<String, dynamic> json) {
    return TodoBrief(
      id: json['id'] as int,
      title: json['title'] as String,
      completed: json['completed'] as bool,
    );
  }
}

class ArchiveBrief {
  ArchiveBrief({
    required this.id,
    required this.title,
    this.thumbnail,
    this.url,
    required this.pinned,
    required this.likeCount,
  });

  final int id;
  final String title;
  final String? thumbnail;
  final String? url;
  final bool pinned;
  final int likeCount;

  factory ArchiveBrief.fromJson(Map<String, dynamic> json) {
    return ArchiveBrief(
      id: json['id'] as int,
      title: json['title'] as String,
      thumbnail: json['thumbnail'] as String?,
      url: json['url'] as String?,
      pinned: json['pinned'] as bool,
      likeCount: json['likeCount'] as int,
    );
  }
}

/// 방 멤버가 아닌 사용자가 대시보드를 조회한 경우(403).
class NotRoomMemberException implements Exception {}
