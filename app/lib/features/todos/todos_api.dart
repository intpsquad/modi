import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/env.dart';
import '../auth/authenticated_http_client.dart';

/// 투두 탭(S-15~18) API 클라이언트 — specs/0006-투두-탭.md.
/// 인증 헤더와 401 갱신 재시도는 [AuthenticatedHttpClient]가 담당한다.
class TodosApi {
  TodosApi({
    this.baseUrl = Env.apiBaseUrl,
    AuthenticatedHttpClient? client,
    http.Client? uploadClient,
  }) : _client = client ?? appAuthenticatedHttpClient,
       _uploadClient = uploadClient ?? http.Client();

  final String baseUrl;
  final AuthenticatedHttpClient _client;
  final http.Client _uploadClient;

  /// 투두 이미지 첨부(2026-08-09, docs/backend/todo-image-archive-handoff.md) — 투두 id 없이
  /// 발급받는 presigned PUT 2단계 업로드. [SettingsApi.uploadProfilePhoto]와 동일 패턴.
  Future<String> uploadTodoImage(
    String idToken,
    int roomId, {
    required List<int> bytes,
  }) async {
    final urlResponse = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/todos/image/upload-url'),
      idToken: idToken,
    );
    _checkOk(urlResponse, '투두 이미지 업로드 준비');
    final body = jsonDecode(urlResponse.body) as Map<String, dynamic>;
    final uploadUrl = body['uploadUrl'] as String;
    final publicUrl = body['publicUrl'] as String;

    final uploadResponse = await _uploadClient.put(
      Uri.parse(uploadUrl),
      body: bytes,
    );
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw StateError('투두 이미지 업로드 실패 (${uploadResponse.statusCode})');
    }
    return publicUrl;
  }

  Future<List<Category>> fetchCategories(String idToken, int roomId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/categories'),
      idToken: idToken,
    );
    _checkOk(response, '카테고리 목록 조회 실패');
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(Category.fromJson)
        .toList();
  }

  Future<Category> createCategory(
    String idToken,
    int roomId,
    String name,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/categories'),
      idToken: idToken,
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode != 201) {
      throw StateError('카테고리 생성 실패: ${response.statusCode} ${response.body}');
    }
    return Category.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Category> renameCategory(
    String idToken,
    int roomId,
    int categoryId,
    String name,
  ) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId/categories/$categoryId'),
      idToken: idToken,
      body: jsonEncode({'name': name}),
    );
    _checkOk(response, '카테고리 이름 수정 실패');
    return Category.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteCategory(
    String idToken,
    int roomId,
    int categoryId,
  ) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/rooms/$roomId/categories/$categoryId'),
      idToken: idToken,
    );
    if (response.statusCode != 204) {
      throw StateError('카테고리 삭제 실패: ${response.statusCode} ${response.body}');
    }
  }

  Future<List<TodoItem>> fetchTodos(String idToken, int roomId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/todos'),
      idToken: idToken,
    );
    _checkOk(response, '투두 목록 조회 실패');
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(TodoItem.fromJson)
        .toList();
  }

  /// S-18 전체화면 상세(2026-08-06) — 목록의 낡은 값이 아니라 서버 최신값을 받는다.
  Future<TodoItem> fetchTodo(String idToken, int roomId, int todoId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/todos/$todoId'),
      idToken: idToken,
    );
    _checkOk(response, '투두 상세 조회 실패');
    return TodoItem.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<MemberBrief>> fetchMembers(String idToken, int roomId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/members'),
      idToken: idToken,
    );
    _checkOk(response, '멤버 목록 조회 실패');
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(MemberBrief.fromJson)
        .toList();
  }

  Future<TodoItem> createTodo(
    String idToken,
    int roomId, {
    required String title,
    String? detail,
    int? categoryId,
    List<String>? assigneeUserIds,
    DateTime? dueDate,
    String? imageUrl,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/todos'),
      idToken: idToken,
      body: jsonEncode({
        'title': title,
        'detail': detail,
        'categoryId': categoryId,
        'assigneeUserIds': assigneeUserIds,
        'dueDate': _formatDate(dueDate),
        'imageUrl': imageUrl,
      }),
    );
    if (response.statusCode != 201) {
      throw StateError('투두 생성 실패: ${response.statusCode} ${response.body}');
    }
    return TodoItem.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// 투두 수정 — **PUT 전체 교체**라 안 실은 값은 서버가 지운다.
  ///
  /// 🔴 **값 인자가 전부 `required` 인 이유**(2026-08-25 #65). 예전엔 선택 인자였는데,
  /// 생략해도 키가 빠지는 게 아니라 `null` 이 실려 나가서 **생략 = 삭제**였다. 호출부가
  /// 값을 손으로 나열하는 구조라 나중에 추가된 `imageUrl` 이 세 곳에서 빠졌고(인라인
  /// 제목·메모 저장 / 담당자 지정 / 카테고리 이동), 첨부 사진이 조용히 지워졌다.
  /// 주석으로 "다시 실어 보내라"고 적어두는 방식은 이미 두 번 실패했다 — 마감일 때는
  /// 챙겼고 사진 때는 놓쳤다. 그래서 **빠뜨리면 컴파일이 깨지게** 바꿨다.
  ///
  /// 필드를 새로 추가할 때도 `required` 로 넣으면 모든 호출부가 즉시 에러로 드러난다.
  /// 값을 바꾸지 않는 호출부는 `imageUrl: todo.imageUrl` 처럼 기존 값을 그대로 넘긴다.
  /// (`createTodo` 는 그대로 선택 인자다 — 새로 만드는 경로라 덮어쓸 기존 값이 없다.)
  Future<TodoItem> updateTodo(
    String idToken,
    int roomId,
    int todoId, {
    required String title,
    required String? detail,
    required int? categoryId,
    required List<String>? assigneeUserIds,
    required DateTime? dueDate,
    required String? imageUrl,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/rooms/$roomId/todos/$todoId'),
      idToken: idToken,
      body: jsonEncode({
        'title': title,
        'detail': detail,
        'categoryId': categoryId,
        'assigneeUserIds': assigneeUserIds,
        // 전체 교체다 — 마감일·이미지를 안 넣으면 서버에서 지워진다("없음" 선택과 같은 요청).
        'dueDate': _formatDate(dueDate),
        'imageUrl': imageUrl,
      }),
    );
    _checkOk(response, '투두 수정 실패');
    return TodoItem.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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
    // FR-39: 담당자가 있는 투두는 그 담당자만 완료/재오픈 가능(아니면 403).
    // 방 멤버가 방 안에서 누른 것이라 여기서의 403은 사실상 담당자 아님 케이스다.
    if (response.statusCode == 403) {
      throw TodoNotAssigneeException.fromResponse(response);
    }
    _checkOk(response, '투두 완료 처리 실패');
  }

  /// 드래그 순서변경(2026-08-04) — 나에게 배정된 투두만 옮길 수 있다(서버가 강제). FR-39와 달리
  /// 미지정(담당자 없음) 투두는 대상이 아니다 — "내 투두만" 화면이 미지정을 안 보여주기 때문.
  /// [categoryId]가 null이면 "기타"(미분류) 그룹을 뜻한다. [todoIds]는 그 그룹 안에서 내가
  /// 재배치할 투두 id 전체를 새 순서대로 담는다 — 다른 사람 담당 투두는 넣지 않는다.
  Future<List<TodoItem>> reorderTodos(
    String idToken,
    int roomId, {
    required int? categoryId,
    required List<int> todoIds,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId/todos/order'),
      idToken: idToken,
      body: jsonEncode({'categoryId': categoryId, 'todoIds': todoIds}),
    );
    _checkOk(response, '투두 순서 변경 실패');
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(TodoItem.fromJson)
        .toList();
  }

  /// S-16-B AI 투두 추천 — 후보만 받는다. 채택은 [createTodo]로 앱이 직접 하며
  /// 담당자는 미지정([])으로 생성한다(specs/full_spec.md S-16-B).
  /// 실측 7~9초(ai/docs/EXPERIMENTS.md #10) — 호출부는 로딩 상태를 보여줘야 한다.
  Future<List<TodoSuggestionCandidate>> fetchAiSuggestions(
    String idToken,
    int roomId,
  ) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/todos/ai-suggest'),
      idToken: idToken,
    );
    _checkOk(response, 'AI 투두 추천 실패');
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['candidates'] as List)
        .cast<Map<String, dynamic>>()
        .map(TodoSuggestionCandidate.fromJson)
        .toList();
  }

  Future<void> deleteTodo(String idToken, int roomId, int todoId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/rooms/$roomId/todos/$todoId'),
      idToken: idToken,
    );
    if (response.statusCode != 204) {
      throw StateError('투두 삭제 실패: ${response.statusCode} ${response.body}');
    }
  }

  void _checkOk(http.Response response, String message) {
    if (response.statusCode != 200) {
      throw StateError('$message: ${response.statusCode} ${response.body}');
    }
  }

  String? _formatDate(DateTime? date) {
    if (date == null) return null;
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

/// 담당자가 있는 투두를 담당자 아닌 멤버가 완료/재오픈하려 할 때(FR-39, 서버 403).
/// specs/0006-투두-탭.md — 일반 실패("완료 처리에 실패했어요")와 구분해 담당자 전용
/// 안내 문구를 노출하기 위한 타입. 홈(S-04)·투두 탭(S-15) 두 화면이 공유한다.
class TodoNotAssigneeException implements Exception {
  TodoNotAssigneeException([String? message])
    : message = (message == null || message.isEmpty) ? defaultMessage : message;

  final String message;

  /// 서버 body 파싱에 실패했을 때의 폴백 문구(서버 원문과 동일하게 맞춤).
  static const String defaultMessage = '본인이 담당한 투두만 체크할 수 있어요';

  /// 403 응답 body의 `message`(서버 안내 문구)를 그대로 노출한다. 파싱 실패 시 폴백.
  static TodoNotAssigneeException fromResponse(http.Response response) {
    return TodoNotAssigneeException(_extractMessage(response.body));
  }

  static String? _extractMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // JSON이 아니거나 형식이 다르면 폴백 문구로.
    }
    return null;
  }

  @override
  String toString() => 'TodoNotAssigneeException: $message';
}

class Category {
  Category({required this.id, required this.name});

  final int id;
  final String name;

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(id: json['id'] as int, name: json['name'] as String);
  }
}

class MemberBrief {
  MemberBrief({
    required this.userId,
    required this.nickname,
    this.profileImage,
  });

  final String userId;
  final String nickname;
  final String? profileImage;

  factory MemberBrief.fromJson(Map<String, dynamic> json) {
    return MemberBrief(
      userId: json['userId'] as String,
      nickname: json['nickname'] as String,
      profileImage: json['profileImage'] as String?,
    );
  }
}

/// S-16-B AI 추천 후보 — 서버 `TodoSuggestionCandidate` record(camelCase 직렬화).
/// [category]는 기존 카테고리명이거나 AI가 새로 제안한 이름 — 이름→id 해석과
/// "없으면 생성"은 채택 시점에 앱이 한다(서버 javadoc이 지정한 계약).
/// [sourceItemId]는 근거가 된 아카이브 자료 id로, 방에 자료가 없으면 null.
class TodoSuggestionCandidate {
  TodoSuggestionCandidate({
    required this.title,
    this.category,
    this.sourceItemId,
  });

  final String title;
  final String? category;
  final int? sourceItemId;

  factory TodoSuggestionCandidate.fromJson(Map<String, dynamic> json) {
    return TodoSuggestionCandidate(
      title: json['title'] as String,
      category: json['category'] as String?,
      sourceItemId: (json['sourceItemId'] as num?)?.toInt(),
    );
  }
}

/// `TodoItem.copyWith` 의 "이 인자는 안 넘겼다" 표시. `null` 은 "값을 비워라"라는
/// 뜻으로 이미 쓰이고 있어서 구분자가 따로 필요하다.
///
/// 전용 private 클래스인 이유: `const Object()` 로 두면 Dart 가 같은 const 인스턴스를
/// 하나로 합쳐서, 바깥에서 우연히 `const Object()` 를 넘겨도 "생략"으로 처리된다.
class _Unchanged {
  const _Unchanged();
}

const _Unchanged _unchanged = _Unchanged();

class TodoItem {
  TodoItem({
    required this.id,
    required this.title,
    this.detail,
    required this.completed,
    this.categoryId,
    required this.assignees,
    this.createdAt,
    this.dueDate,
    this.imageUrl,
  });

  final int id;
  final String title;
  final String? detail;
  final bool completed;
  final int? categoryId;
  final List<MemberBrief> assignees;

  /// 생성일 — 생성일순 정렬에 쓴다.
  final DateTime? createdAt;

  /// 마감일. 2026-08-07 롤백 후 남은 유일한 미리 알림형 메타데이터로, 협업 캐릭터(S-16)의
  /// 마감 준수율 계산에 쓰인다(specs/0006-투두-탭.md).
  final DateTime? dueDate;

  /// 첨부된 사진(2026-08-09, docs/backend/todo-image-archive-handoff.md) — 없으면 null.
  final String? imageUrl;

  /// 일부만 바꾼 사본 — **지정하지 않은 값은 전부 그대로 따라온다.**
  ///
  /// 🔴 화면이 낙관적으로(서버 응답 전에) 목록을 갈아끼울 때 쓴다. 예전엔 화면마다
  /// `TodoItem(...)` 을 손으로 새로 지었는데, 거기서 `imageUrl` 이 빠져 **저장하자마자
  /// 썸네일이 사라졌다**(2026-08-25 #65). 여기 한 곳으로 모아 두면 필드가 늘어도
  /// 사본이 알아서 들고 간다.
  ///
  /// `detail`·`categoryId` 만 센티널을 쓴다 — 평범한 nullable 인자로는 **"안 건드림"과
  /// "null 로 비우기"를 구분할 수 없는데**, 메모 비우기와 "기타"(카테고리 없음)로
  /// 옮기기가 실제로 필요한 동작이기 때문이다. 나머지는 `null` = "안 건드림"이다
  /// (센티널은 타입 검사를 느슨하게 만들어서, 필요한 곳에만 쓴다 — 2026-08-25 리뷰).
  TodoItem copyWith({
    String? title,
    bool? completed,
    List<MemberBrief>? assignees,
    DateTime? dueDate,
    String? imageUrl,
    Object? detail = _unchanged,
    Object? categoryId = _unchanged,
  }) => TodoItem(
    id: id,
    title: title ?? this.title,
    detail: detail is _Unchanged ? this.detail : detail as String?,
    completed: completed ?? this.completed,
    categoryId: categoryId is _Unchanged ? this.categoryId : categoryId as int?,
    assignees: assignees ?? this.assignees,
    createdAt: createdAt,
    dueDate: dueDate ?? this.dueDate,
    imageUrl: imageUrl ?? this.imageUrl,
  );

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as int,
      title: json['title'] as String,
      detail: json['detail'] as String?,
      completed: json['completed'] as bool,
      categoryId: json['categoryId'] as int?,
      assignees: (json['assignees'] as List)
          .cast<Map<String, dynamic>>()
          .map(MemberBrief.fromJson)
          .toList(),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'] as String),
      dueDate: json['dueDate'] == null
          ? null
          : DateTime.tryParse(json['dueDate'] as String),
      imageUrl: json['imageUrl'] as String?,
    );
  }
}
