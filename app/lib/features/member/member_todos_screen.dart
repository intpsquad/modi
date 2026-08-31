import 'dart:convert';

import 'package:flutter/material.dart';

import '../../config/env.dart';
import '../../design/empty_state.dart';
import '../../design/tokens.dart';
import '../auth/authenticated_http_client.dart';
import '../auth/auth_service.dart';
import '../room/room_session.dart';
import '../settings/my_activity_card.dart';
import '../todos/todo_photo.dart';
import '../todos/todos_api.dart';

typedef MemberTokenLoader = Future<String> Function();

/// 로그인한 사용자의 uid를 **지연** 조회한다(#68). 생성자 기본값에서 곧바로
/// `AuthService().currentUserId`를 읽으면 `FirebaseAuth.instance`를 건드려
/// 위젯 테스트가 깨지므로, 호출 시점을 build까지 미룬다.
typedef MemberCurrentUserIdLoader = String? Function();

class MemberTodosApi {
  MemberTodosApi({
    this.baseUrl = Env.apiBaseUrl,
    AuthenticatedHttpClient? client,
  }) : _client = client ?? appAuthenticatedHttpClient;

  final String baseUrl;
  final AuthenticatedHttpClient _client;

  Future<MemberTodosData> fetchMemberTodos(
    String idToken,
    int roomId,
    String userId,
  ) async {
    final responses = await Future.wait([
      _client.get(
        Uri.parse('$baseUrl/rooms/$roomId/members/$userId/todos'),
        idToken: idToken,
      ),
      _client.get(
        Uri.parse('$baseUrl/rooms/$roomId/members/progress'),
        idToken: idToken,
      ),
      _client.get(
        Uri.parse('$baseUrl/rooms/$roomId/categories'),
        idToken: idToken,
      ),
    ]);
    for (final response in responses) {
      if (response.statusCode != 200) {
        throw StateError('멤버 투두 조회 실패 (${response.statusCode})');
      }
    }

    final todos = (jsonDecode(responses[0].body) as List)
        .cast<Map<String, dynamic>>()
        .map(TodoItem.fromJson)
        .toList();
    final progress = (jsonDecode(responses[1].body) as List)
        .cast<Map<String, dynamic>>();
    final member = progress.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['userId'] == userId,
      orElse: () => null,
    );
    if (member == null) throw StateError('방 멤버를 찾을 수 없어요');
    final categories = <int, String>{
      for (final item
          in (jsonDecode(responses[2].body) as List)
              .cast<Map<String, dynamic>>())
        item['id'] as int: item['name'] as String,
    };

    return MemberTodosData(
      memberName: member['nickname'] as String,
      profileImage: member['profileImage'] as String?,
      assignedTotal: member['assignedTotal'] as int,
      assignedDone: member['assignedDone'] as int,
      todos: todos,
      categories: categories,
    );
  }

  Future<void> poke(String idToken, int roomId, String userId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/members/$userId/pokes'),
      idToken: idToken,
    );
    if (response.statusCode != 201) {
      throw StateError('재촉 전송 실패 (${response.statusCode})');
    }
  }

  /// 멤버 협업 캐릭터(전역, specs/0016). 방 멤버십은 접근 권한 확인용.
  Future<MyActivitySummary> fetchCharacter(
    String idToken,
    int roomId,
    String userId,
  ) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/members/$userId/character'),
      idToken: idToken,
    );
    if (response.statusCode != 200) {
      throw StateError('멤버 캐릭터 조회 실패 (${response.statusCode})');
    }
    return MyActivitySummary.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

class MemberTodosData {
  const MemberTodosData({
    required this.memberName,
    this.profileImage,
    required this.assignedTotal,
    required this.assignedDone,
    required this.todos,
    this.categories = const {},
  });

  final String memberName;
  final String? profileImage;
  final int assignedTotal;
  final int assignedDone;
  final List<TodoItem> todos;
  final Map<int, String> categories;
}

/// S-30-M 멤버 투두 — 체크/상세 진입이 없는 읽기 전용 목록.
class MemberTodosScreen extends StatefulWidget {
  MemberTodosScreen({
    super.key,
    required this.userId,
    int? roomId,
    MemberTodosApi? api,
    MemberTokenLoader? tokenLoader,
    MemberCurrentUserIdLoader? currentUserId,
  }) : roomId = roomId ?? appRoomSession.currentRoomId,
       api = api ?? MemberTodosApi(),
       tokenLoader = tokenLoader ?? AuthService().getIdToken,
       currentUserId = currentUserId ?? (() => AuthService().currentUserId);

  final String userId;
  final int? roomId;
  final MemberTodosApi api;
  final MemberTokenLoader tokenLoader;

  /// 본인 페이지 여부 판정용 — 홈에서 내 아바타를 탭해도 이 화면으로 들어오므로(#68)
  /// 자기 자신을 찌르는 버튼을 숨기는 데 쓴다.
  final MemberCurrentUserIdLoader currentUserId;

  @override
  State<MemberTodosScreen> createState() => _MemberTodosScreenState();
}

class _MemberTodosScreenState extends State<MemberTodosScreen> {
  MemberTodosData? _data;
  MyActivitySummary? _character;
  String? _error;
  bool _poking = false;

  /// 카테고리 접힘/펼침 상태 — key는 categoryId(미분류는 null). 기본 펼침.
  final Map<int?, bool> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadCharacter();
  }

  Future<void> _loadCharacter() async {
    final roomId = widget.roomId;
    if (roomId == null) return;
    try {
      final token = await widget.tokenLoader();
      final character = await widget.api.fetchCharacter(
        token,
        roomId,
        widget.userId,
      );
      if (mounted) setState(() => _character = character);
    } catch (_) {
      // 캐릭터는 보조 정보 — 실패해도 카드가 placeholder로 남는다.
    }
  }

  Future<void> _load() async {
    final roomId = widget.roomId;
    if (roomId == null) {
      setState(() => _error = '현재 선택된 방이 없어요');
      return;
    }
    setState(() => _error = null);
    try {
      final token = await widget.tokenLoader();
      final data = await widget.api.fetchMemberTodos(
        token,
        roomId,
        widget.userId,
      );
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) setState(() => _error = '멤버 투두를 불러오지 못했어요');
    }
  }

  Future<void> _poke() async {
    final roomId = widget.roomId;
    if (roomId == null || _poking) return;
    setState(() => _poking = true);
    try {
      final token = await widget.tokenLoader();
      await widget.api.poke(token, roomId, widget.userId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('콕 찔렀어요')));
      }
    } catch (_) {
      // 성공(콕 찔렀어요)과 대칭으로 실패도 상단 CTA 근처에서 보이도록 SnackBar로.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('콕 찌르지 못했어요')));
      }
    } finally {
      if (mounted) setState(() => _poking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.foreground,
        titleTextStyle: AppTypography.section,
        title: Text(data?.memberName ?? '멤버'),
      ),
      body: data == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _MemberErrorState(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                _buildProfileRow(data),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.content,
                    0,
                    AppSpacing.content,
                    AppSpacing.base,
                  ),
                  child: MyActivityCard(
                    nickname: data.memberName,
                    summary: _character,
                  ),
                ),
                if (data.todos.isEmpty)
                  const EmptyState(icon: Icons.task_alt, message: '담당한 투두가 없어요')
                else
                  ..._buildGroups(data),
              ],
            ),
    );
  }

  /// 프로필 행(마이페이지식) — 아바타 + [이름 + 진행률 문구] + 우측 "찌르기" 버튼.
  /// 본인 페이지면 찌르기 버튼을 아예 그리지 않는다(#68) — 자기 자신은 찌를 수 없다.
  Widget _buildProfileRow(MemberTodosData data) {
    final isSelf = widget.currentUserId() == widget.userId;
    final percent = data.assignedTotal == 0
        ? 0
        : (data.assignedDone / data.assignedTotal * 100).round();
    final caption = data.assignedTotal == 0
        ? '아직 담당한 투두가 없어요'
        : '투두를 $percent% 완료했어요';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.content,
        AppSpacing.base,
        AppSpacing.content,
        AppSpacing.base,
      ),
      child: Row(
        children: [
          _MemberAvatar(name: data.memberName, imageUrl: data.profileImage),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.memberName,
                  style: AppTypography.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  caption,
                  style: AppTypography.caption.copyWith(color: AppColors.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!isSelf) ...[
            const SizedBox(width: AppSpacing.sm),
            _PokeButton(loading: _poking, onTap: _poke),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildGroups(MemberTodosData data) {
    // 카테고리 등장 순서를 보존한다(미분류는 null → "기타", specs/0002-data-model.md).
    final grouped = <int?, List<TodoItem>>{};
    for (final todo in data.todos) {
      grouped.putIfAbsent(todo.categoryId, () => []).add(todo);
    }
    return [
      const SizedBox(height: AppSpacing.sm),
      for (final entry in grouped.entries)
        _buildCategorySection(
          categoryId: entry.key,
          title: entry.key == null
              ? '기타'
              : data.categories[entry.key] ?? '카테고리',
          todos: entry.value,
        ),
    ];
  }

  Widget _buildCategorySection({
    required int? categoryId,
    required String title,
    required List<TodoItem> todos,
  }) {
    final expanded = _expanded[categoryId] ?? true;
    final keySuffix = categoryId?.toString() ?? 'independent';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.section)),
              IconButton(
                key: ValueKey('member-category-toggle-$keySuffix'),
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.muted,
                ),
                onPressed: () =>
                    setState(() => _expanded[categoryId] = !expanded),
              ),
            ],
          ),
          if (expanded)
            for (final todo in todos) _MemberTodoRow(todo: todo),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// 읽기전용 투두 행 — **투두 탭 행(`_TodoListRow` 읽기 모드)과 동일한 모양**을 쓰되 체크
/// 동그라미·스와이프·편집 없이 읽기 전용으로만 보여준다(2026-08-09 데모 — "투두탭
/// 컴포넌트와 같게, 체크만 없애고 읽기전용"). 제목 15/ink(line-height 130%)+완료 시 취소선,
/// 메모 13/muted, 제목>메모 간격 4. 담당자 아바타는 이 화면 전체가 한 멤버라 중복이라 뺀다.
class _MemberTodoRow extends StatelessWidget {
  const _MemberTodoRow({required this.todo});

  final TodoItem todo;

  // 투두 탭 읽기 행과 동일: 본문 잉크 #111111.
  static const Color _ink = Color(0xFF111111);

  @override
  Widget build(BuildContext context) {
    final detail = todo.detail;
    final titleStyle = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.3,
      color: todo.completed ? AppColors.completedTodo : _ink,
      decoration: todo.completed ? TextDecoration.lineThrough : null,
      decorationColor: AppColors.borderSoft,
      decorationThickness: 1,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(todo.title, style: titleStyle),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              style: AppTypography.caption.copyWith(color: AppColors.muted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // 첨부 사진 썸네일(2026-08-24 #65) — 투두 탭 읽기 행과 동일 모양 유지(0006:77③).
          if ((todo.imageUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            TodoRowThumbnail(
              key: ValueKey('todo-thumb-${todo.id}'),
              url: todo.imageUrl!,
            ),
          ],
        ],
      ),
    );
  }
}

/// 원형 프로필 아바타 — 이미지 있으면 표시, 없거나 실패하면 이니셜.
class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.name, this.imageUrl});

  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    // design.md §아바타 승인 크기(64) — 새 크기 도입 금지.
    const size = 64.0;
    final initial = name.isEmpty ? '?' : name.characters.first;
    final fallback = Center(
      child: Text(
        initial,
        style: AppTypography.title.copyWith(color: AppColors.muted),
      ),
    );
    final url = imageUrl;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: ColoredBox(
          color: AppColors.surfaceSoft,
          child: url == null || url.isEmpty
              ? fallback
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

/// "찌르기" 버튼 — primary pill(패딩 10/16), 흰 16px + 번개 아이콘(gap 6). S-30-M 즉시 실행.
class _PokeButton extends StatelessWidget {
  const _PokeButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '찌르기',
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                else
                  Image.asset(
                    'assets/icons/icon_light.png',
                    width: 16,
                    height: 16,
                    color: AppColors.onPrimary,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.bolt,
                      size: 16,
                      color: AppColors.onPrimary,
                    ),
                  ),
                const SizedBox(width: 6),
                Text(
                  '찌르기',
                  style: AppTypography.body.copyWith(
                    color: AppColors.onPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberErrorState extends StatelessWidget {
  const _MemberErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
