import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../auth/auth_service.dart';
import '../room/room_session.dart';
import 'todo_form_sheet.dart';
import 'todo_sync.dart';
import 'todos_api.dart';

/// S-18 전체화면 투두 상세/수정(specs/0006-투두-탭.md) — 목록 항목을 탭하면 여기로 이동한다.
/// 서버에서 최신값을 다시 받아 채우고, 저장은 기존 `PUT /rooms/{roomId}/todos/{todoId}`(전체
/// 교체)를 그대로 쓴다.
///
/// 2026-08-07 롤백으로 본문 위젯이 인라인 작성기에서 [TodoFormSheet]로 바뀌었다 — 전체화면이라는
/// 형태는 그대로다.
class TodoDetailScreen extends StatefulWidget {
  TodoDetailScreen({
    super.key,
    required this.todoId,
    TodosApi? api,
    AuthService? authService,
    RoomSession? roomSession,
    TodoSync? todoSync,
  }) : api = api ?? TodosApi(),
       authService = authService ?? AuthService(),
       roomSession = roomSession ?? appRoomSession,
       todoSync = todoSync ?? appTodoSync;

  final int todoId;
  final TodosApi api;
  final AuthService authService;
  final RoomSession roomSession;
  final TodoSync todoSync;

  @override
  State<TodoDetailScreen> createState() => _TodoDetailScreenState();
}

class _TodoDetailScreenState extends State<TodoDetailScreen> {
  bool _loading = true;
  String? _errorText;
  int? _roomId;
  TodoItem? _todo;
  List<Category> _categories = const [];
  List<MemberBrief> _members = const [];

  // 방 전환 등으로 조회가 겹쳐 호출될 때 먼저 시작한 요청이 나중 요청 결과를 덮어쓰지 않도록 막는 가드.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.roomSession.addListener(_onRoomSessionChanged);
    _load();
  }

  @override
  void dispose() {
    widget.roomSession.removeListener(_onRoomSessionChanged);
    super.dispose();
  }

  void _onRoomSessionChanged() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final idToken = await widget.authService.getIdToken();
      await widget.roomSession.loadRooms(idToken);
      final resolution = await widget.roomSession.resolveCurrentRoom();
      final roomId = resolution.roomId;
      if (roomId == null) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _roomId = null;
          _loading = false;
        });
        return;
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _roomId = roomId);
      await _fetchDetail();
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorText = '투두를 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  Future<void> _fetchDetail() async {
    final roomId = _roomId;
    if (roomId == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final idToken = await widget.authService.getIdToken();
      final results = await Future.wait([
        widget.api.fetchTodo(idToken, roomId, widget.todoId),
        widget.api.fetchCategories(idToken, roomId),
        widget.api.fetchMembers(idToken, roomId),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _todo = results[0] as TodoItem;
        _categories = results[1] as List<Category>;
        _members = results[2] as List<MemberBrief>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorText = '투두를 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  Future<void> _handleSubmit({
    required String title,
    String? detail,
    int? categoryId,
    required List<String> assigneeUserIds,
    DateTime? dueDate,
    String? imageUrl,
  }) async {
    final roomId = _roomId;
    if (roomId == null) return;
    final idToken = await widget.authService.getIdToken();
    await widget.api.updateTodo(
      idToken,
      roomId,
      widget.todoId,
      title: title,
      detail: detail,
      categoryId: categoryId,
      assigneeUserIds: assigneeUserIds,
      dueDate: dueDate,
      imageUrl: imageUrl,
    );
    // 홈(S-04)·투두 탭은 살아있는 상태로 남아 있어 스스로 다시 조회하지 않는다. S-18이 유일한
    // 수정 경로라 여기서 신호를 안 보내면 다른 화면이 옛 제목을 계속 보여준다.
    widget.todoSync.markChanged();
  }

  Future<String> _uploadImage(List<int> bytes) async {
    final roomId = _roomId;
    if (roomId == null) throw StateError('방 정보를 찾지 못했어요');
    final idToken = await widget.authService.getIdToken();
    return widget.api.uploadTodoImage(idToken, roomId, bytes: bytes);
  }

  @override
  Widget build(BuildContext context) {
    final todo = _todo;
    if (_loading || _errorText != null || _roomId == null || todo == null) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(title: const Text('투두 상세')),
        body: SafeArea(child: _buildStateBody()),
      );
    }
    // 뒤로가기(`<`)는 AppBar 기본 버튼 = 테마의 actionIconTheme이 그려 준다(0003 하위 페이지 규칙).
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('투두 상세')),
      body: SafeArea(
        top: false,
        child: TodoFormSheet(
          categories: _categories,
          members: _members,
          initial: todo,
          onSubmit: _handleSubmit,
          uploadImage: _uploadImage,
          // 제목은 AppBar가 담당한다. 삭제 버튼은 폼에 아예 없다(목록 스와이프가 유일 경로).
          showTitle: false,
        ),
      ),
    );
  }

  Widget _buildStateBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: AppSpacing.cardGap),
            Text('투두를 불러오고 있어요', style: AppTypography.bodySmall),
          ],
        ),
      );
    }

    if (_errorText != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.content),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorText!,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.accentDanger,
                ),
              ),
              const SizedBox(height: AppSpacing.cardGap),
              OutlinedButton(
                onPressed: _fetchDetail,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    if (_roomId == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.content),
          child: Text('진행 중인 방이 없어요', style: AppTypography.title),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
