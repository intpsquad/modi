import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../design/notice_banner.dart';
import '../../design/ai_sparkle_button.dart';
import '../../design/todo_checkbox.dart';
import '../../design/tokens.dart';
import '../../design/tab_header.dart';
import '../auth/auth_service.dart';
import '../room/room_session.dart';
import '../shell/app_shell.dart';
import '../shell/tab_activation.dart';
import 'ai_suggest_sheet.dart';
import 'assignee_avatar.dart';
import 'pending_completion.dart';
import 'todo_form_sheet.dart';
import 'todo_order_store.dart';
import 'todo_photo.dart';
import 'todo_sync.dart';
import 'todos_api.dart';
import 'unassigned_sheet.dart';

// ── 투두 화면 정밀 레이아웃 스펙(사용자 지정 px/색) ──────────────────────────
// design.md 토큰과 별개인 iOS 계열 값들. 필요 시 추후 토큰으로 승격한다.
const double _kHMargin = 20; // 전역 좌우 공백(헤더·세그먼트·배너 + 행 박스 바깥 여백)
const double _kListHMargin = 32; // 구분선 좌우(= 전역 20 + 행 내부 12, 콘텐츠와 정렬)
const double _kRowInset = 12; // 행 박스 "내부" 좌우 패딩. 박스 자체는 _kHMargin만큼 들어가 있다.
const double _kHeaderH = 48; // 카테고리/기타 헤더 높이 — 투두 행보다 크다(요청).
// 상단 바 높이 — 일반 헤더와 선택 모드 바가 **같은 높이**여야 목록이 위아래로 튀지 않는다
// (2026-08-05 요청). 값의 근거는 일반 헤더의 스펙 수치다: 위 패딩 16 + 제목 줄높이 32
// (24px × 32/24) + 아래 패딩 12. **제목 타이포를 바꾸면 이 상수도 함께 고쳐야 한다.**
// 두 모드의 자연 높이를 맞추는 방법은 없다 — 제목은 폰트 줄높이로, 선택 바는 아이콘 크기로
// 높이가 정해져 서로 다른 이유로 변한다(고정값이 유일하게 일치를 보장한다).
const double _kTopBarH = TabHeader.height; // 56 — 4개 탭 공용 헤더 높이
const double _kRowH = 44; // 투두·추가 행 높이
const double _kRowGap = 8; // 행 사이 수직 간격
// 좌측 스와이프로 드러나는 액션 버튼(수정/삭제) — 시각 크기 50×28, 버튼 사이 간격 4px(요청).
// 오른쪽 끝은 전역 좌우 여백(_kHMargin)에 정렬되고, 행과의 간격도 _kActionGap이다.
const double _kActionBtnW = 50;
const double _kActionBtnH = 28;
const double _kActionGap = 4;
const Color _kInk = Color(0xFF111111); // 제목·본문 진한 텍스트
const Color _kMutedInk = Color(0xFF636366); // 기타/셰브론/뱃지 텍스트
const Color _kCircleBorder = Color(0xFFC7C7CC); // 체크/점선 원 테두리
const Color _kDividerColor = Color(0xFFE5E5EA); // 그룹 구분선

// 세그먼트 탭 높이 — 트랙과 선택 알약이 같은 높이다(2026-08-06 지정, design.md §6).
// (폐지: 트랙 48 + 패딩 4 + 흰 알약 그림자 `_kActiveTabShadow`·트랙색 `_kSegBg`·
//  비활성 글씨 `_kInactiveInk`. 이제 토큰 surface-soft/primary/on-primary/muted를 쓴다.)
const double _kSegHeight = 40;

/// 투두 정렬 기준 — specs/0006-투두-탭.md. 마감일순은 데이터상 불가(투두 마감 없음, 0002).
/// manual은 서버 `position`에 저장되는 실제 드래그 순서다(2026-08-04, "내 투두만" 토글일 때만
/// 드래그 가능 — 남의 투두는 자리도 안 바뀐다). created는 서버가 createdAt을 안 주면 id로 폴백한다.
enum _TodoSort {
  manual('수동'),
  created('생성일'),
  title('제목');

  const _TodoSort(this.label);
  final String label;
}

/// 수동 정렬 flat 목록의 한 행. 헤더/추가행은 드래그 불가, 투두행만 드래그 가능.
enum _FlatKind { header, todo, add }

class _FlatItem {
  _FlatItem.header(this.categoryId)
    : kind = _FlatKind.header,
      todo = null,
      hidden = false;
  _FlatItem.todo(this.todo, this.categoryId, {this.hidden = false})
    : kind = _FlatKind.todo;
  _FlatItem.add(this.categoryId, {this.hidden = false})
    : kind = _FlatKind.add,
      todo = null;

  final _FlatKind kind;
  final int? categoryId; // null = 기타
  final TodoItem? todo;

  /// 접힌 카테고리에 속해 화면에서 감춘 행. **목록에서 빼지 않고 남겨 둔다** — 빼 버리면
  /// 접힘이 애니메이션 없이 툭 사라지고, 저장되는 수동 순서에서도 그 투두들이 빠진다.
  final bool hidden;
}

/// 수동 정렬 flat 목록에서 oldIndex의 투두를 newIndex로 옮겼을 때의 결과를 계산하는 순수 함수.
/// - targetCategoryId: 드롭 위치 위쪽으로 가장 가까운 헤더의 카테고리(없으면 아래쪽 첫 헤더). 기타=null.
/// - visibleOrder: 이동 후 보이는 투두 id들의 순서.
/// 헤더/추가행은 드래그 불가라 oldIndex는 투두여야 한다. UI에서 분리해 결정적으로 테스트한다.
@visibleForTesting
({int? targetCategoryId, List<int> visibleOrder}) computeFlatReorder(
  List<({String kind, int? categoryId, int? todoId})> items,
  int oldIndex,
  int newIndex,
) {
  final moved = items[oldIndex];
  final without = [...items]..removeAt(oldIndex);
  // 상·하한: 맨 위 카테고리 헤더 위로, 맨 밑 "할 일 추가" 행 아래로는 드롭 금지.
  // minInsert = 첫 헤더 바로 아래, maxInsert = 마지막 추가행 위(그 앞에 삽입).
  var minInsert = 0;
  for (var i = 0; i < without.length; i++) {
    if (without[i].kind == 'header') {
      minInsert = i + 1;
      break;
    }
  }
  var maxInsert = without.length;
  for (var i = without.length - 1; i >= 0; i--) {
    if (without[i].kind == 'add') {
      maxInsert = i;
      break;
    }
  }
  final rawInsert = newIndex.clamp(0, without.length);
  final insertAt = minInsert <= maxInsert
      ? rawInsert.clamp(minInsert, maxInsert)
      : rawInsert;

  int? targetCat;
  var found = false;
  for (var i = insertAt - 1; i >= 0; i--) {
    if (without[i].kind == 'header') {
      targetCat = without[i].categoryId;
      found = true;
      break;
    }
  }
  if (!found) {
    for (var i = insertAt; i < without.length; i++) {
      if (without[i].kind == 'header') {
        targetCat = without[i].categoryId;
        break;
      }
    }
  }

  without.insert(insertAt, (
    kind: 'todo',
    categoryId: targetCat,
    todoId: moved.todoId,
  ));
  final visibleOrder = [
    for (final it in without)
      if (it.kind == 'todo') it.todoId!,
  ];
  return (targetCategoryId: targetCat, visibleOrder: visibleOrder);
}

/// S-15 투두 탭 — specs/0006-투두-탭.md. 세그먼티드 컨트롤(내투두/전체보기),
/// 완료 인라인 표시(더보기>완료된 항목 보기 토글), 카테고리 아코디언 + 기타 섹션,
/// 미지정 배너, 상단 ⋯ 더보기 메뉴(항목선택/카테고리관리/완료보기/정렬), 일괄선택 모드.
class TodosScreen extends StatefulWidget {
  TodosScreen({
    super.key,
    TodosApi? api,
    AuthService? authService,
    RoomSession? roomSession,
    TodoSync? todoSync,
    TabActivation? tabActivation,
    this.completionDelay = const Duration(seconds: 2),
  }) : api = api ?? TodosApi(),
       authService = authService ?? AuthService(),
       roomSession = roomSession ?? appRoomSession,
       todoSync = todoSync ?? appTodoSync,
       tabActivation = tabActivation ?? appTabActivation;

  final TodosApi api;
  final AuthService authService;
  final RoomSession roomSession;
  final TodoSync todoSync;
  final TabActivation tabActivation;

  /// 완료 체크를 서버에 보내기까지 기다리는 시간(요청 3). 테스트에서 줄여 쓴다.
  final Duration completionDelay;

  @override
  State<TodosScreen> createState() => TodosScreenState();
}

/// State가 public인 것은 테스트가 카테고리 이동(드래그 드롭 결과)을 직접 호출하기 위해서다 —
/// 중첩 스크롤 뷰 안의 `ReorderableListView` 드래그는 위젯 테스트로 구동하기 어렵다.
class TodosScreenState extends State<TodosScreen> {
  bool _loading = true;

  /// 한 번이라도 목록을 그린 뒤인가 — 그 뒤로는 재조회에 전체 스피너를 쓰지 않는다(요청 6).
  bool _loadedOnce = false;
  String? _errorText;
  String? _todoErrorText;
  int? _roomId;
  List<Category> _categories = [];
  List<TodoItem> _todos = [];
  List<MemberBrief> _members = [];
  String? _myUserId;
  bool _showAllMembers = false;
  bool _showCompleted = true; // 더보기>완료된 항목 보기 토글. 기본 표시(인라인 취소선).
  /// 사용자가 고른 정렬. **전체보기에서는 수동 정렬을 제공하지 않는다**(2026-08-05 요청) —
  /// 그 상태에서는 [_effectiveSort]가 생성일로 대신하고, 여기 값은 그대로 남겨
  /// "내 투두만"으로 돌아오면 수동 순서가 되살아난다.
  _TodoSort _sortMode = _TodoSort.manual;
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  final Map<int, bool> _expandedCategories = {};
  // "기타"(카테고리 미지정) 그룹 펼침 상태 — categoryId가 null이라 위 맵에 못 넣어 별도 보관.
  bool _etcExpanded = true;

  // 수동 정렬 순서(기기 로컬 영속). 백엔드에 순서 필드가 없어 서버 저장 불가 → shared_preferences.
  final TodoOrderStore _orderStore = TodoOrderStore();
  List<int> _manualOrder = [];

  // 수동 정렬 flat 목록(빌드 시 채우고 onReorderItem에서 참조 — 인덱스→카테고리 판정용).
  List<_FlatItem> _flatItems = [];

  // 좌측 스와이프 액션 패널은 화면에 하나만 열려 있는다(요청). 행/헤더가 자기 컨트롤러를
  // 여기 등록하고, 다른 상호작용이 시작되면 _closeSwipeActions()로 전부 되돌린다.
  final _SlidableGroup _slidableGroup = _SlidableGroup();

  /// 완료 체크를 2초 붙잡아 두는 대기열 — 그 사이 다시 누르면 취소된다(요청 3).
  late final PendingCompletions _pendingCompletions = PendingCompletions(
    delay: widget.completionDelay,
  );

  // 방 전환 등으로 _load()가 겹쳐 호출될 때 먼저 시작한 요청이 나중 요청 결과를 덮어쓰지 않도록 막는 가드.
  int _loadGeneration = 0;

  // 내가 유발한 투두 변경이면 내 리스너 리로드를 건너뛴다(낙관적 업데이트로 이미 반영).
  bool _selfTodoMutation = false;

  /// 열려 있던 스와이프 액션(수정/삭제)을 되돌린다. 다른 상호작용이 시작될 때 먼저 호출 —
  /// 사용자 확정: 열린 게 있으면 "닫고 그 동작도 바로 실행"(탭을 먹지 않는다).
  void _closeSwipeActions() => _slidableGroup.closeAll();

  /// 지금 세그먼트에서 고를 수 있는 정렬 — 전체보기에는 **수동이 없다**(2026-08-05 요청).
  /// 남의 투두가 섞인 목록에서 드래그 순서는 의미가 없고 서버에 저장할 수도 없다.
  List<_TodoSort> get _availableSorts => _showAllMembers
      ? const [_TodoSort.created, _TodoSort.title]
      : _TodoSort.values;

  /// 실제로 적용되는 정렬. 전체보기에서 수동이 걸려 있으면 생성일로 대신한다.
  _TodoSort get _effectiveSort =>
      _availableSorts.contains(_sortMode) ? _sortMode : _TodoSort.created;

  /// 담당자(내투두/전체) + 완료 표시 여부로 거른 뒤 정렬 기준으로 정렬한 목록.
  /// 카테고리 그룹핑은 이 순서를 그대로 이어받는다(build에서 categoryId로 분류).
  List<TodoItem> get _filteredTodos {
    final myId = _myUserId;
    Iterable<TodoItem> list = _todos;
    if (!_showAllMembers && myId != null) {
      list = list.where((t) => t.assignees.any((a) => a.userId == myId));
    }
    if (!_showCompleted) {
      // 방금 체크해 **아직 서버로 안 간** 항목은 남긴다 — 홈과 같이 2초 안에는 되돌릴 수
      // 있어야 하는데, 바로 걸러버리면 행이 사라져 다시 누를 대상이 없어진다(요청 3).
      list = list.where(
        (t) => !t.completed || _pendingCompletions.isPending(t.id),
      );
    }
    final result = list.toList();
    switch (_effectiveSort) {
      case _TodoSort.manual:
        // 저장된 수동 순서로 정렬. 순서에 없는(새로 생긴) 투두는 뒤로, id로 안정 정렬.
        // 순서 미저장(빈 목록)이면 서버 반환 순서(등록순)를 그대로 유지한다.
        if (_manualOrder.isNotEmpty) {
          int rank(TodoItem t) {
            final i = _manualOrder.indexOf(t.id);
            return i == -1 ? 1 << 30 : i;
          }

          result.sort((a, b) {
            final r = rank(a).compareTo(rank(b));
            return r != 0 ? r : a.id.compareTo(b.id);
          });
        }
        break;
      case _TodoSort.created:
        result.sort((a, b) {
          final ac = a.createdAt, bc = b.createdAt;
          if (ac != null && bc != null) return ac.compareTo(bc);
          return a.id.compareTo(b.id); // createdAt 미노출 시 id 프록시
        });
        break;
      case _TodoSort.title:
        result.sort((a, b) => a.title.compareTo(b.title));
        break;
    }
    return result;
  }

  /// 바깥 ListView 스크롤 — 투두 탭을 (재)탭하면 맨 위로 되돌리는 데 쓴다(2026-08-10).
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.roomSession.addListener(_onRoomSessionChanged);
    widget.todoSync.addListener(_onExternalTodoChange);
    widget.tabActivation.addListener(_onTabChanged);
    widget.tabActivation.reselect.addListener(_onTabReselected);
    _load();
  }

  @override
  void dispose() {
    widget.roomSession.removeListener(_onRoomSessionChanged);
    widget.todoSync.removeListener(_onExternalTodoChange);
    widget.tabActivation.removeListener(_onTabChanged);
    widget.tabActivation.reselect.removeListener(_onTabReselected);
    // 화면을 떠나면 대기 중인 완료 체크는 즉시 보낸다(사용자 확정) — 버리면 체크가 사라진다.
    _pendingCompletions.flushAll();
    _scrollController.dispose();
    super.dispose();
  }

  /// 투두 탭을 누를 때마다(전환·재탭) 맨 위로 부드럽게 스크롤한다(2026-08-10 요청).
  void _onTabReselected() {
    if (!mounted) return;
    if (widget.tabActivation.reselect.index != AppShell.todosIndex) return;
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// 투두 탭이 다시 켜지면 조용히(스피너 없이) 최신 목록으로 맞춘다(요청 1) —
  /// 탭 상태가 살아 있어 initState 가 다시 돌지 않기 때문에 이 신호가 필요하다.
  /// 탭을 떠날 때는 대기 중인 완료 체크를 즉시 반영한다(요청 3).
  void _onTabChanged() {
    if (!mounted) return;
    if (widget.tabActivation.index == AppShell.todosIndex) {
      _load(silent: true);
    } else {
      _pendingCompletions.flushAll();
    }
  }

  void _onRoomSessionChanged() {
    if (!mounted) return;
    // 방이 바뀌면 이전 방 기준 일괄선택은 무효 — 해제하고 다시 불러온다.
    if (_selectionMode) _exitSelection();
    _load();
  }

  /// 다른 화면(홈 등)에서 투두 완료가 바뀌면 목록을 다시 불러온다.
  /// 내가 유발한 변경(_selfTodoMutation)이면 낙관적 업데이트로 이미 반영돼 스킵.
  void _onExternalTodoChange() {
    // 외부 변경은 조용히 갱신 — 전체 스피너로 초기화하지 않고 기존 목록을 유지한다.
    if (mounted && !_selfTodoMutation) _load(silent: true);
  }

  /// 다른 화면에 투두 변경을 알린다(자기 리스너는 스킵). notifyListeners는 동기라
  /// 플래그를 세팅한 사이에 리스너들이 실행된다.
  void _notifyTodoChanged() {
    _selfTodoMutation = true;
    widget.todoSync.markChanged();
    _selfTodoMutation = false;
  }

  /// [silent]이면 실패해도 에러 화면으로 뒤엎지 않는다(외부 동기화 리로드용).
  ///
  /// 전체 스피너는 **첫 로드에만** 쓴다 — 한 번 목록을 보여준 뒤로는 재조회 중에도
  /// 화면을 유지하고 결과가 오면 목록만 갈아끼운다(요청 6: 추가하면 잠시 뒤 항목이 나타나는 식).
  Future<void> _load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    setState(() {
      if (!silent && !_loadedOnce) _loading = true;
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
          _loadedOnce = true;
        });
        return;
      }

      final results = await Future.wait<dynamic>([
        widget.api.fetchCategories(idToken, roomId),
        widget.api.fetchTodos(idToken, roomId),
        widget.api.fetchMembers(idToken, roomId),
        _orderStore.load(roomId),
      ]);
      // 이 요청이 진행되는 동안 더 최신 _load()가 시작됐다면 이 결과는 버린다(오래된 응답이
      // 나중에 도착해 최신 상태를 덮어쓰는 경쟁 상태 방지).
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _roomId = roomId;
        _categories = results[0] as List<Category>;
        _todos = results[1] as List<TodoItem>;
        _members = results[2] as List<MemberBrief>;
        _manualOrder = results[3] as List<int>;
        _myUserId = widget.authService.currentUserId;
        for (final category in _categories) {
          _expandedCategories.putIfAbsent(category.id, () => true);
        }
        _loading = false;
        _loadedOnce = true;
      });
      // 홈 "투두 추가하기"로 넘어온 경우, 목록(방)이 준비된 지금 추가 시트를 바로 띄운다
      // (2026-08-09). 플래그는 홈 버튼이 넘기기 직전에만 세우므로 다른 _load 경로엔 영향 없다.
      if (widget.tabActivation.consumeOpenTodoComposer()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openCreateTodoSheet();
        });
      }
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (!silent) _errorText = '투두를 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  /// 체크는 화면에 바로, 서버 반영은 2초 뒤(요청 3) — 그 사이 다시 누르면 없던 일이 된다.
  /// 화면을 떠나거나 탭을 옮기면 대기 중인 것은 즉시 보낸다([PendingCompletions.flushAll]).
  void _toggleTodo(TodoItem todo) {
    if (_roomId == null) return;

    // 대기 중인 항목을 다시 누른 것 = 취소. 서버로 아무것도 보내지 않고 화면만 되돌린다.
    if (_pendingCompletions.cancel(todo.id)) {
      setState(() {
        _todoErrorText = null;
        _todos = [
          for (final t in _todos)
            if (t.id == todo.id) t.copyWith(completed: !todo.completed) else t,
        ];
      });
      return;
    }

    final newCompleted = !todo.completed;
    final previousTodos = _todos;
    setState(() {
      _todoErrorText = null;
      _todos = [
        for (final t in _todos)
          if (t.id == todo.id) t.copyWith(completed: newCompleted) else t,
      ];
    });
    _pendingCompletions.schedule(
      todo.id,
      () => _commitCompletion(todo, newCompleted, previousTodos),
    );
  }

  /// 실제 서버 반영. 실패하면 목록을 되돌리고 인라인 에러를 띄운다(기존 동작 유지).
  Future<void> _commitCompletion(
    TodoItem todo,
    bool newCompleted,
    List<TodoItem> previousTodos,
  ) async {
    final roomId = _roomId;
    if (roomId == null) return;
    try {
      final idToken = await widget.authService.getIdToken();
      await widget.api.setTodoCompleted(idToken, roomId, todo.id, newCompleted);
      _notifyTodoChanged(); // 홈 등 다른 화면에 반영
      // 대기가 끝났으니 목록을 다시 그린다 — '완료된 항목 보기'가 꺼져 있으면 이 시점에
      // 행이 사라진다(그전까지는 되돌릴 수 있게 남겨둔다).
      if (mounted) setState(() {});
    } on TodoNotAssigneeException catch (e) {
      if (!mounted) return;
      setState(() {
        _todos = previousTodos;
        _todoErrorText = e.message; // FR-39: 담당자 아님 전용 안내
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _todos = previousTodos;
        _todoErrorText = '완료 처리에 실패했어요. 다시 시도해 주세요';
      });
    }
  }

  /// 좌측 스와이프 즉시 삭제(낙관적). 실패하면 목록을 원복하고 인라인 에러를 노출한다.
  Future<void> _deleteTodo(TodoItem todo) async {
    final roomId = _roomId;
    if (roomId == null) return;
    final previousTodos = _todos;
    setState(() {
      _todoErrorText = null;
      _todos = [
        for (final t in _todos)
          if (t.id != todo.id) t,
      ];
    });
    try {
      final idToken = await widget.authService.getIdToken();
      await widget.api.deleteTodo(idToken, roomId, todo.id);
      _notifyTodoChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _todos = previousTodos;
        _todoErrorText = '삭제에 실패했어요. 다시 시도해 주세요';
      });
    }
  }

  Future<void> _createCategoryDialog() async {
    final roomId = _roomId;
    if (roomId == null) return;
    var mutated = false;
    await showDialog<void>(
      context: context,
      builder: (context) => _CategoryNameDialog(
        title: '카테고리 추가',
        initialName: '',
        confirmLabel: '추가',
        onSubmit: (name) async {
          final idToken = await widget.authService.getIdToken();
          await widget.api.createCategory(idToken, roomId, name);
          mutated = true;
        },
      ),
    );
    if (mutated) await _load();
  }

  Future<void> _showCategoryActions(Category category) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text('이름 수정'),
            onTap: () => Navigator.of(context).pop('rename'),
          ),
          ListTile(
            title: const Text(
              '삭제',
              style: TextStyle(color: AppColors.accentDanger),
            ),
            onTap: () => Navigator.of(context).pop('delete'),
          ),
        ],
      ),
    );
    if (action == 'rename') {
      await _renameCategoryDialog(category);
    } else if (action == 'delete') {
      await _confirmDeleteCategory(category);
    }
  }

  Future<void> _renameCategoryDialog(Category category) async {
    final roomId = _roomId;
    if (roomId == null) return;
    var mutated = false;
    await showDialog<void>(
      context: context,
      builder: (context) => _CategoryNameDialog(
        title: '카테고리 이름 수정',
        initialName: category.name,
        confirmLabel: '저장',
        onSubmit: (name) async {
          final idToken = await widget.authService.getIdToken();
          await widget.api.renameCategory(idToken, roomId, category.id, name);
          mutated = true;
        },
      ),
    );
    if (mutated) await _load();
  }

  Future<void> _confirmDeleteCategory(Category category) async {
    final roomId = _roomId;
    if (roomId == null) return;
    var mutated = false;
    await showDialog<void>(
      context: context,
      builder: (context) => _ConfirmDeleteCategoryDialog(
        onConfirm: () async {
          final idToken = await widget.authService.getIdToken();
          await widget.api.deleteCategory(idToken, roomId, category.id);
          mutated = true;
        },
      ),
    );
    if (mutated) {
      _expandedCategories.remove(category.id);
      await _load();
    }
  }

  Future<void> _openAiSuggestSheet() async {
    _closeSwipeActions();
    final roomId = _roomId;
    if (roomId == null) return;
    var mutated = false;
    // showModalBottomSheet는 useSafeArea:true가 아니면 시트 내부 컨텍스트의 top padding을
    // MediaQuery.removePadding(removeTop:true)로 강제로 0을 만든다(bottom_sheet.dart) — 시트
    // 안에서 MediaQuery.viewPaddingOf(context).top을 읽으면 항상 0이라 상태바 높이를 알 수
    // 없다. 시트를 띄우기 *전* 이 컨텍스트(제거되지 않은 값)에서 미리 읽어 넘긴다.
    final topPadding = MediaQuery.viewPaddingOf(context).top;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true, // 바텀 네비(GNB) 위로 뜨게 — 시트만 보이도록.
      // 로딩(7~9초) 중에도 **바로 취소** 가능하게: 상단 드래그 핸들 + 바깥 탭/스와이프로 닫힘
      // (2026-08-09 요청). 하단 '닫기' 버튼은 그대로 둔다.
      showDragHandle: true,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => AiSuggestSheet(
        topPadding: topPadding,
        onFetch: () async {
          final idToken = await widget.authService.getIdToken();
          return widget.api.fetchAiSuggestions(idToken, roomId);
        },
        onAdopt: (candidate) async {
          final idToken = await widget.authService.getIdToken();
          // 카테고리는 **미지정(기타)** 으로 만든다. AI 가 카테고리를 정하지
          // 않으므로 해석할 이름이 없다 — 분류는 사용자가 편집에서 한다.
          //
          // 담당자도 미지정이다. 직접추가의 본인 자동 지정 경로(_openCreateTodoSheet)를 타지
          // 않는다(full_spec.md S-16-B, 0006 데이터 절: 미지정 상태는 AI추천 결과로만 발생).
          final created = await widget.api.createTodo(
            idToken,
            roomId,
            title: candidate.title,
            categoryId: null,
            assigneeUserIds: const [],
          );
          mutated = true;
          return created.id; // 시트에서 바로 취소할 때 삭제 대상.
        },
        onCancelAdopt: (todoId) async {
          // 방금 추가한 투두를 되돌린다(삭제) — 시트 안 "취소" 버튼(2026-08-09).
          final idToken = await widget.authService.getIdToken();
          await widget.api.deleteTodo(idToken, roomId, todoId);
          mutated = true;
        },
      ),
    );
    // 후보를 하나도 채택하지 않고 닫으면 리로드하지 않는다(불필요한 재조회 방지).
    if (mutated) await _load();
  }

  /// 바텀시트 연타 방지 — 추가/수정/미지정 시트를 여는 동안 true. 두 번째 탭은 무시한다
  /// (2026-08-09 사용자 요청 "두 번 연속 눌러도 하나만"). 담당자 선택 시트는 자체 전역 가드가 있다
  /// (`assignee_picker_sheet.dart`).
  bool _sheetGuard = false;

  Future<void> _openCreateTodoSheet({int? categoryId}) async {
    if (_sheetGuard) return; // 연타로 시트가 두 개 뜨지 않게(2026-08-09)
    _closeSwipeActions();
    final roomId = _roomId;
    if (roomId == null) return;
    _sheetGuard = true;
    var mutated = false;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true, // 상단 핸들(디자인 지시 2026-08-08)
        useRootNavigator: true, // 바텀 네비(GNB) 위로 뜨게 — 시트만 보이도록.
        builder: (context) => TodoFormSheet(
          categories: _categories,
          members: _members,
          initialCategoryId: categoryId,
          // 수정 시트와 동일한 **내용물 높이**(2026-08-09) — 기존 전체높이에서 맞춤.
          fullHeight: false,
          uploadImage: (bytes) async {
            final idToken = await widget.authService.getIdToken();
            return widget.api.uploadTodoImage(idToken, roomId, bytes: bytes);
          },
          onSubmit:
              ({
                required title,
                detail,
                categoryId,
                required assigneeUserIds,
                dueDate,
                imageUrl,
              }) async {
                final idToken = await widget.authService.getIdToken();
                // 담당자 미선택 시 본인 자동 지정하지 않고 **미지정으로 남긴다**(2026-08-10 사용자
                // 확정). 이전 규칙(직접추가=본인 자동 지정)을 뒤집음 — 미지정 투두는 S-17 미지정
                // 처리 배너로 흘려보낸다. specs/0006-투두-탭.md 갱신.
                await widget.api.createTodo(
                  idToken,
                  roomId,
                  title: title,
                  detail: detail,
                  categoryId: categoryId,
                  assigneeUserIds: assigneeUserIds,
                  dueDate: dueDate,
                  imageUrl: imageUrl,
                );
                _notifyTodoChanged();
                mutated = true;
              },
        ),
      );
    } finally {
      _sheetGuard = false;
    }
    // 저장하지 않고 닫으면 리로드하지 않는다(불필요한 재조회/재렌더 방지).
    if (mutated) await _load();
  }

  /// 투두 상세/수정 — 내용물 높이 바텀시트(S-18, 2026-08-08). 목록의 [todo]를 프리필해 연다.
  Future<void> _openEditTodoSheet(TodoItem todo) async {
    if (_sheetGuard) return; // 연타로 시트가 두 개 뜨지 않게(2026-08-09)
    final roomId = _roomId;
    if (roomId == null) return;
    _sheetGuard = true;
    var mutated = false;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useRootNavigator: true,
        builder: (context) => TodoFormSheet(
          categories: _categories,
          members: _members,
          initial: todo,
          fullHeight: false, // 내용물 높이(전체높이 아님)
          uploadImage: (bytes) async {
            final idToken = await widget.authService.getIdToken();
            return widget.api.uploadTodoImage(idToken, roomId, bytes: bytes);
          },
          onSubmit:
              ({
                required title,
                detail,
                categoryId,
                required assigneeUserIds,
                dueDate,
                imageUrl,
              }) async {
                final idToken = await widget.authService.getIdToken();
                await widget.api.updateTodo(
                  idToken,
                  roomId,
                  todo.id,
                  title: title,
                  detail: detail,
                  categoryId: categoryId,
                  assigneeUserIds: assigneeUserIds,
                  dueDate: dueDate,
                  imageUrl: imageUrl,
                );
                _notifyTodoChanged();
                mutated = true;
              },
        ),
      );
    } finally {
      _sheetGuard = false;
    }
    if (mutated) await _load();
  }

  Future<void> _openUnassignedSheet() async {
    if (_sheetGuard) return; // 연타로 시트가 두 개 뜨지 않게(2026-08-09)
    _closeSwipeActions();
    final roomId = _roomId;
    if (roomId == null) return;
    // 목록 재조회(비동기)부터 시트 표시까지 통째로 잠근다 — 조회 중 두 번째 탭이 들어와도
    // 두 시트가 뜨지 않게. 모든 조기 반환은 finally 에서 해제된다.
    _sheetGuard = true;
    var mutated = false;
    try {
      List<TodoItem> latestTodos;
      try {
        final idToken = await widget.authService.getIdToken();
        latestTodos = await widget.api.fetchTodos(idToken, roomId);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('미지정 목록을 불러오지 못했어요')));
        return;
      }

      if (!mounted) return;
      final unassigned = latestTodos.where((t) => t.assignees.isEmpty).toList();
      if (unassigned.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('처리할 미지정 투두가 없어요')));
        await _load();
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true, // 바텀 네비(GNB) 위로 뜨게 — 시트만 보이도록.
        // S-17 에는 닫기 버튼이 없다(2026-08-04 확정) — 손잡이가 "내려서 닫는다"를 보여준다.
        showDragHandle: true,
        builder: (context) => UnassignedSheet(
          initialTodos: unassigned,
          members: _members,
          onAssign: (todo, assigneeUserIds) async {
            final idToken = await widget.authService.getIdToken();
            await widget.api.updateTodo(
              idToken,
              roomId,
              todo.id,
              title: todo.title,
              detail: todo.detail,
              categoryId: todo.categoryId,
              assigneeUserIds: assigneeUserIds,
              // PUT은 전체 교체라 담당자만 지정할 때도 마감일을 다시 실어 보내야 지워지지 않는다.
              dueDate: todo.dueDate,
            );
            mutated = true;
          },
        ),
      );
    } finally {
      _sheetGuard = false;
    }
    if (mutated) await _load();
  }

  @override
  Widget build(BuildContext context) {
    // AI 생성 전용 플로팅 버튼 — 추가(직접) 진입과 분리(0006, PRD §2). 방이 있고 일반 모드일 때만.
    final showAiButton =
        !_loading && _errorText == null && _roomId != null && !_selectionMode;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Stack(
          children: [
            _buildBody(context),
            if (showAiButton)
              Positioned(
                right: AppSpacing.content,
                bottom: 24,
                child: AiSparkleButton(
                  key: const ValueKey('ai-generate-fab'),
                  onTap: _openAiSuggestSheet,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
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
              OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }

    final roomId = _roomId;
    if (roomId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.content),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('진행 중인 방이 없어요', style: AppTypography.title),
              const SizedBox(height: AppSpacing.cardGap),
            ],
          ),
        ),
      );
    }

    final unassignedCount = _todos.where((t) => t.assignees.isEmpty).length;
    final visibleTodos = _filteredTodos;
    final independentTodos = visibleTodos
        .where((t) => t.categoryId == null)
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      // 스크롤을 시작하면 열려 있던 스와이프 액션은 닫는다. Slidable 자체의 closeOnScroll은
      // 수동 정렬 경로에서 무력하다 — 행이 NeverScrollableScrollPhysics인 내부
      // ReorderableListView 안에 있어 "절대 스크롤되지 않는 Scrollable"을 잡는다.
      child: NotificationListener<ScrollStartNotification>(
        onNotification: (_) {
          _closeSwipeActions();
          return false; // 알림은 계속 전파(RefreshIndicator 등이 그대로 쓰도록)
        },
        child: ListView(
          controller: _scrollController,
          // 헤더가 자체 top16 패딩을 가지므로 리스트 top=0. 하단은 플로팅 버튼/네비 여백.
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _buildTopBar(context),
            _buildFilterBar(),
            // 세그먼트 ↔ 아래 콘텐츠 간격. 원래 24였는데 AI 배너가 붙으면 떠 보여서
            // 4px 줄였다(2026-08-05 요청 7). 배너가 없을 때(=카테고리 섹션이 바로 올 때)도
            // 같은 간격으로 둔다 — 배너 유무로 위치가 흔들리지 않게.
            const SizedBox(height: 20),
            if (unassignedCount > 0) ...[
              _buildUnassignedBanner(unassignedCount),
              const SizedBox(height: 16),
            ],
            if (_todoErrorText != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _kHMargin),
                child: Text(
                  _todoErrorText!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.accentDanger,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.cardGap),
            ],
            // 카테고리·투두가 없어도 항상 카테고리 섹션 + "기타" 섹션을 렌더한다(0006/PRD §1).
            // "기타"는 언제나 맨 아래. 각 섹션 하단에 "＋" 투두 추가 어포던스가 붙는다.
            // 수동 정렬(일반 모드)은 카테고리 넘나드는 드래그를 위해 전체를 flat 리스트로 렌더한다.
            if (_effectiveSort == _TodoSort.manual && !_selectionMode)
              _buildManualReorderable(visibleTodos, independentTodos)
            else ...[
              // 구분선은 그룹 "사이"에만(N-1개) — 첫 그룹 위/마지막 그룹(기타) 아래엔 없음.
              for (var i = 0; i < _categories.length; i++) ...[
                if (i > 0) _buildGroupDivider(),
                _buildCategorySection(
                  _categories[i],
                  visibleTodos
                      .where((t) => t.categoryId == _categories[i].id)
                      .toList(),
                ),
              ],
              // 기타는 항상 마지막 그룹 — 카테고리가 하나라도 있으면 그 앞에 구분선.
              if (_categories.isNotEmpty) _buildGroupDivider(),
              _buildIndependentSection(independentTodos),
            ],
          ],
        ),
      ),
    );
  }

  /// 상단 헤더 — 일반 모드와 선택 모드가 **같은 높이**여야 한다(2026-08-05 요청).
  /// 예전에는 일반 헤더만 세로 패딩(16/12)이 있고 선택 바는 없어, 항목 선택을 누르는 순간
  /// 아래 목록이 위아래로 튀었다. 두 모드를 같은 높이 박스에 담아 고정한다.
  Widget _buildTopBar(BuildContext context) {
    return SizedBox(
      key: const ValueKey('todo-top-bar'),
      height: _kTopBarH,
      child: _selectionMode ? _buildSelectionBar() : _buildTitleBar(),
    );
  }

  Widget _buildTitleBar() {
    // 4개 탭 공용 헤더로 통일(2026-08-08 QA): 제목 section(20/600) 좌측 + ⋮ 액션.
    return TabHeader(
      title: '투두',
      action: IconButton(
        key: const ValueKey('todo-overflow-menu'),
        onPressed: _showOverflowMenu,
        icon: const Icon(Icons.more_vert, color: AppColors.foreground),
        tooltip: '메뉴',
      ),
    );
  }

  Widget _buildSelectionBar() {
    final count = _selectedIds.length;
    final hasSelection = count > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHMargin),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('selection-cancel'),
            onPressed: _exitSelection,
            icon: const Icon(Icons.close, color: AppColors.foreground),
          ),
          Text('$count개 선택', style: AppTypography.title),
          const Spacer(),
          TextButton(
            onPressed: hasSelection ? _bulkComplete : null,
            child: const Text('완료처리'),
          ),
          TextButton(
            onPressed: hasSelection ? _bulkDelete : null,
            child: Text(
              '삭제',
              style: TextStyle(
                color: hasSelection ? AppColors.accentDanger : AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHMargin),
      child: _SegmentedToggle(
        segments: const ['내 투두만', '전체보기'],
        selectedIndex: _showAllMembers ? 1 : 0,
        onChanged: (i) {
          _closeSwipeActions();
          setState(() => _showAllMembers = i == 1);
        },
      ),
    );
  }

  /// 상단 ⋯ 더보기 — 딤 스크림 + 우상단 플로팅 카드(design.md §6/§7). 라우트가 아니라
  /// 화면 내 오버레이(0003 라우트 무변경, 0006 인라인 원칙 유지).
  Future<void> _showOverflowMenu() async {
    _closeSwipeActions();
    final action = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '메뉴 닫기',
      barrierColor: AppColors.scrim.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (context, _, _) => SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.content,
              child: _OverflowMenuCard(
                showCompleted: _showCompleted,
                sortLabel: _effectiveSort.label,
              ),
            ),
          ],
        ),
      ),
      transitionBuilder: (context, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'select':
        setState(() {
          _selectionMode = true;
          _selectedIds.clear();
        });
      case 'categories':
        await _showCategoryManager();
      case 'completed':
        setState(() => _showCompleted = !_showCompleted);
      case 'sort':
        await _showSortChooser();
    }
  }

  /// 카테고리 관리(인라인) — 0006 확정: 별도 화면 없이 시트로. 추가/이름수정/삭제.
  /// 순서변경은 백엔드(categories.position) 준비 후 후속(specs/OPEN.md).
  Future<void> _showCategoryManager() async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.content),
              child: Text('카테고리 관리', style: AppTypography.title),
            ),
            if (_categories.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('카테고리가 없어요', style: AppTypography.bodySmall),
              ),
            for (final category in _categories)
              ListTile(
                title: Text(category.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: AppColors.muted),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _renameCategoryDialog(category);
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.accentDanger,
                      ),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _confirmDeleteCategory(category);
                      },
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add, color: AppColors.primary),
              title: Text(
                '카테고리 추가',
                style: AppTypography.body.copyWith(color: AppColors.primary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _createCategoryDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSortChooser() async {
    final chosen = await showModalBottomSheet<_TodoSort>(
      context: context,
      useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.content),
              child: Text('정렬', style: AppTypography.title),
            ),
            for (final sort in _availableSorts)
              ListTile(
                key: ValueKey('sort-option-${sort.name}'),
                title: Text(sort.label),
                trailing: sort == _effectiveSort
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(sort),
              ),
          ],
        ),
      ),
    );
    if (mounted && chosen != null) setState(() => _sortMode = chosen);
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(int id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  /// 선택 대상 중 **현재 방에 실제로 있는** 투두만 추린다 — 방 전환 등으로 남은
  /// stale id로 엉뚱한 투두를 건드리지 않도록(id는 방별 작은 정수라 겹칠 수 있다).
  List<TodoItem> get _selectedTodosInRoom =>
      _todos.where((t) => _selectedIds.contains(t.id)).toList();

  Future<void> _bulkComplete() async {
    _pendingCompletions.flushAll(); // 대기 중 체크는 먼저 보낸다(요청 3).
    final roomId = _roomId;
    if (roomId == null) return;
    final targets = _selectedTodosInRoom.where((t) => !t.completed).toList();
    if (targets.isEmpty) {
      _exitSelection();
      return;
    }
    var failed = false;
    try {
      final idToken = await widget.authService.getIdToken();
      for (final todo in targets) {
        // 항목별로 계속 시도 — 담당자 아닌 항목은 서버 403(FR-39)이라도
        // 나머지 유효 항목은 그대로 반영된다(성공분 보존).
        try {
          await widget.api.setTodoCompleted(idToken, roomId, todo.id, true);
        } catch (_) {
          failed = true;
        }
      }
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    _exitSelection();
    if (failed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('일부 항목을 완료 처리하지 못했어요')));
    }
    _notifyTodoChanged();
    await _load();
  }

  Future<void> _bulkDelete() async {
    _pendingCompletions.flushAll(); // 대기 중 체크는 먼저 보낸다(요청 3).
    final roomId = _roomId;
    if (roomId == null) return;
    final ids = _selectedTodosInRoom.map((t) => t.id).toList();
    if (ids.isEmpty) {
      _exitSelection();
      return;
    }
    final count = ids.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$count개 항목을 삭제할까요?'),
        content: const Text('삭제한 투두는 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '삭제',
              style: TextStyle(color: AppColors.accentDanger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var failed = false;
    try {
      final idToken = await widget.authService.getIdToken();
      for (final id in ids) {
        try {
          await widget.api.deleteTodo(idToken, roomId, id);
        } catch (_) {
          failed = true;
        }
      }
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    _exitSelection();
    if (failed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('일부 항목을 삭제하지 못했어요')));
    }
    _notifyTodoChanged();
    await _load();
  }

  /// 담당자 미지정 안내 — 담당자가 없는(주인 없는) 투두 [count]개가 있음을 알린다.
  /// 공용 [NoticeBanner](흰 배경 + 연한 회색 테두리 + 회색 그림자 + 경고 아이콘)를 쓰고,
  /// 탭하면 S-17 시트를 연다.
  Widget _buildUnassignedBanner(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHMargin),
      child: NoticeBanner(
        key: const ValueKey('unassigned-banner'),
        text: '주인 없는 투두 $count개가 있어요!🥹',
        onTap: _openUnassignedSheet,
      ),
    );
  }

  Widget _buildCategorySection(Category category, List<TodoItem> todos) {
    final expanded = _expandedCategories[category.id] ?? true;
    // 좌우 패딩은 각 행(헤더/투두/추가 박스)이 12px씩 직접 갖는다 — 여기선 감싸지 않는다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCategoryHeaderRow(category),
        // 펼침/접힘 애니메이션(요청 8) — 접히면 높이 0으로 부드럽게.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTodoList(todos),
                    // 카테고리 하단 "＋"(해당 카테고리로 프리셀렉트) — PRD §1: 투두가 없어도 노출.
                    if (!_selectionMode)
                      _buildAddAffordance(categoryId: category.id),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// 카테고리 헤더 행(제목 롱프레스=이름수정/삭제, 우측 펼침/접힘 토글). 섹션과 flat 목록이 공용.
  /// 좌측 스와이프 = **삭제 하나만**(사용자 확정) — 카테고리 삭제는 확인 모달을 거친다.
  Widget _buildCategoryHeaderRow(Category category) {
    final expanded = _expandedCategories[category.id] ?? true;
    // 헤더 박스 전체가 토글 영역(요청 7). 롱프레스는 이름수정/삭제 유지, 쉐브론은 표시용.
    final header = _PressableBox(
      key: ValueKey('category-toggle-${category.id}'),
      onTap: () {
        _closeSwipeActions();
        setState(() => _expandedCategories[category.id] = !expanded);
      },
      onLongPress: () {
        _closeSwipeActions();
        _showCategoryActions(category);
      },
      // 카테고리 헤더: 높이 _kHeaderH(투두 행보다 큼), 내부 좌우 12(박스는 바깥 20 여백).
      child: SizedBox(
        height: _kHeaderH,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kRowInset),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  category.name,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 24 / 18,
                    color: _kInk,
                  ),
                ),
              ),
              _buildToggleChevron(expanded),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHMargin),
      child: _SwipeActionRow(
        key: ValueKey('category-slidable-${category.id}'),
        group: _slidableGroup,
        // onDismissed 없음 — 끝까지 당겨도 즉시 삭제되지 않는다(확인 모달 필수).
        actions: [
          _RowActionButton(
            key: ValueKey('category-delete-${category.id}'),
            label: '삭제',
            background: AppColors.accentDanger,
            foreground: AppColors.onPrimary,
            onPressed: () => _confirmDeleteCategory(category),
          ),
        ],
        child: header,
      ),
    );
  }

  /// 펼침/접힘 셰브론 — 접힘=＞(chevron_right), 펼침=⌵(90° 회전). 회전 애니메이션(요청).
  Widget _buildToggleChevron(bool expanded) {
    return AnimatedRotation(
      turns: expanded ? 0.25 : 0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      // 20×20, #636366(스펙 3-A).
      child: const Icon(Icons.chevron_right, size: 20, color: _kMutedInk),
    );
  }

  /// "기타" 헤더 — 회색 라벨 + 접이식 토글(스펙: 기타도 펼침 카테고리). 롱프레스 액션 없음.
  /// 실제 카테고리가 아니므로 스와이프 삭제도 없다.
  Widget _buildEtcHeaderRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHMargin),
      child: _PressableBox(
        key: const ValueKey('category-toggle-etc'),
        onTap: () {
          _closeSwipeActions();
          setState(() => _etcExpanded = !_etcExpanded);
        },
        // 기타 헤더: 카테고리와 동일 규격, 텍스트만 연한 #636366(스펙 3-A).
        child: SizedBox(
          height: _kHeaderH,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kRowInset),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '기타',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 24 / 18,
                      color: _kMutedInk,
                    ),
                  ),
                ),
                _buildToggleChevron(_etcExpanded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 그룹(카테고리 카드) 사이 구분선 — 연한 회색 실선. 첫 그룹 위/마지막 그룹 아래엔 없음.
  Widget _buildGroupDivider() {
    // 1px #E5E5EA, 상하 16 여백, 좌우 20(행과 정렬) — 스펙 3-D.
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: _kListHMargin, vertical: 16),
      child: Divider(height: 1, thickness: 1, color: _kDividerColor),
    );
  }

  /// 수동 정렬 + 일반 모드: 전체(카테고리 헤더 + 투두 + 추가행 + 기타)를 하나의 flat
  /// ReorderableListView로 렌더한다. 헤더/추가행은 드래그 불가(핸들 없음), 투두행만 드래그 가능.
  /// 다른 카테고리 헤더 아래로 드롭하면 카테고리가 바뀐다(_onFlatReorder).
  Widget _buildManualReorderable(
    List<TodoItem> visibleTodos,
    List<TodoItem> independentTodos,
  ) {
    // 접힌 그룹의 행도 **목록에 남기고 hidden 으로만 표시한다** — 목록에서 빼면 접힘이
    // 애니메이션 없이 툭 사라진다(2026-08-05 요청). 감춘 행은 높이 0으로 줄어들 뿐이라
    // 드롭 대상이 되지 못하고, 저장되는 수동 순서에는 그대로 남는다.
    final items = <_FlatItem>[];
    for (final category in _categories) {
      items.add(_FlatItem.header(category.id));
      final collapsed = !(_expandedCategories[category.id] ?? true);
      for (final t in visibleTodos.where((t) => t.categoryId == category.id)) {
        items.add(_FlatItem.todo(t, category.id, hidden: collapsed));
      }
      // 접히면 하위 목록과 함께 추가행(1번박스)도 숨긴다(스펙: 내부 목록 숨김).
      items.add(_FlatItem.add(category.id, hidden: collapsed));
    }
    items.add(_FlatItem.header(null)); // 기타는 항상 맨 아래
    for (final t in independentTodos) {
      items.add(_FlatItem.todo(t, null, hidden: !_etcExpanded));
    }
    items.add(_FlatItem.add(null, hidden: !_etcExpanded));
    _flatItems = items; // onReorderItem에서 인덱스→카테고리 판정에 사용

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      // 좌우 패딩은 각 행 박스가 12px씩 갖는다 — 리스트 자체는 감싸지 않는다.
      padding: EdgeInsets.zero,
      itemCount: items.length,
      // onReorder(deprecated)가 아니라 onReorderItem — newIndex를 "oldIndex를 뺀 뒤" 기준으로
      // 준다. computeFlatReorder가 원래 그 규약(먼저 제거하고 삽입)으로 계산하므로 이쪽이 맞다
      // (deprecated 쪽은 아래로 끌 때 한 칸 더 내려가는 off-by-one이 있었다).
      onReorderItem: _onFlatReorder,
      itemBuilder: (context, index) {
        final item = items[index];
        switch (item.kind) {
          case _FlatKind.header:
            final header = item.categoryId == null
                ? _buildEtcHeaderRow()
                : _buildCategoryHeaderRow(
                    _categories.firstWhere((c) => c.id == item.categoryId),
                  );
            return KeyedSubtree(
              key: ValueKey('flat-header-${item.categoryId ?? 'etc'}'),
              // 그룹 사이 구분선(N-1개) — 첫 헤더 위엔 없음. 마지막 그룹 아래에도 없음.
              child: index == 0
                  ? header
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [_buildGroupDivider(), header],
                    ),
            );
          case _FlatKind.todo:
            return _CollapsibleFlatRow(
              key: ValueKey('flat-collapse-todo-${item.todo!.id}'),
              hidden: item.hidden,
              child: _buildTodoRow(item.todo!, reorderIndex: index),
            );
          case _FlatKind.add:
            // ReorderableListView는 모든 항목에 최상단 키를 요구한다 —
            // add-todo-* 키는 탭 대상(_PressableBox)에 있으므로 여기서 따로 감싼다.
            return _CollapsibleFlatRow(
              key: ValueKey('flat-collapse-add-${item.categoryId ?? 'etc'}'),
              hidden: item.hidden,
              child: _buildAddAffordance(categoryId: item.categoryId),
            );
        }
      },
    );
  }

  Widget _buildIndependentSection(List<TodoItem> todos) {
    // 좌우 패딩은 각 행 박스가 12px씩 갖는다 — 여기선 감싸지 않는다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "기타"는 회색(muted) 라벨. 항상 맨 아래 그룹으로 노출된다(PRD §1).
        _buildEtcHeaderRow(),
        // 펼침/접힘 애니메이션(요청 8).
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _etcExpanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTodoList(todos),
                    // "기타" 하단 "＋"(카테고리 미지정으로 추가) — 빈 상태에서도 노출.
                    if (!_selectionMode) _buildAddAffordance(categoryId: null),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// 한 섹션(카테고리 또는 기타)의 투두 목록 — 단순 나열(비 수동 정렬 모드용).
  /// 수동 정렬 모드에서는 이 경로 대신 _buildManualReorderable(전체 flat 드래그)을 쓴다.
  Widget _buildTodoList(List<TodoItem> todos) {
    if (todos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final todo in todos) _buildTodoRow(todo)],
    );
  }

  Widget _buildTodoRow(TodoItem todo, {int? reorderIndex}) {
    // FR-39: 담당자가 있는 투두는 담당자만 완료 가능(서버가 403으로 강제). 내 userId를
    // 알 때만 사전 비활성화한다 — 미지정(담당자 없음)·내가 담당·userId 미확정은 활성.
    final myId = _myUserId;
    final canComplete =
        todo.assignees.isEmpty ||
        myId == null ||
        todo.assignees.any((a) => a.userId == myId);
    return _TodoListRow(
      key: ValueKey('todo-row-${todo.id}'),
      todo: todo,
      slidableGroup: _slidableGroup,
      selectionMode: _selectionMode,
      selected: _selectedIds.contains(todo.id),
      reorderIndex: reorderIndex,
      canComplete: canComplete,
      onSelectToggle: () {
        _closeSwipeActions();
        _toggleSelected(todo.id);
      },
      // 체크 원 탭 = 완료 토글. 열린 스와이프 액션이 있으면 닫고 그대로 토글까지 실행한다.
      onToggle: () {
        _closeSwipeActions();
        _toggleTodo(todo);
      },
      // information 아이콘 탭 = 상세/수정 바텀시트(2026-08-09: 기존 "행 탭→시트"에서 이동).
      onEdit: () {
        _closeSwipeActions();
        _pendingCompletions.flushAll(); // 시트 열기 전에 대기 중 체크를 보낸다(요청 3).
        _openEditTodoSheet(todo);
      },
      // 제목/메모 인라인 편집 진입 시 화면 정리(시트는 안 연다).
      onEditStart: () {
        _closeSwipeActions();
        _pendingCompletions.flushAll();
      },
      // 제목/메모 인라인 저장(2026-08-09) — 나머지 필드는 기존값 재전송(PUT 전체 교체).
      onInlineSave: ({required title, detail}) =>
          _saveTodoEdits(todo, title: title, detail: detail),
      onDelete: () => _deleteTodo(todo), // 스와이프 [삭제] 또는 끝까지 당기기
    );
  }

  /// 제목/메모 인라인 편집 저장 — 낙관적으로 로컬을 먼저 바꾸고 서버에 반영한다.
  /// 실패하면 원복 + 인라인 에러(재조회 `_load`는 하지 않아 편집 입력이 유실되지 않는다).
  Future<void> _saveTodoEdits(
    TodoItem todo, {
    required String title,
    String? detail,
  }) async {
    final roomId = _roomId;
    if (roomId == null) return;
    final previous = _todos;
    setState(() {
      _todoErrorText = null;
      _todos = [
        for (final t in _todos)
          if (t.id == todo.id) _withTitleDetail(t, title, detail) else t,
      ];
    });
    try {
      final idToken = await widget.authService.getIdToken();
      await widget.api.updateTodo(
        idToken,
        roomId,
        todo.id,
        title: title,
        detail: detail,
        categoryId: todo.categoryId,
        assigneeUserIds: todo.assignees.map((a) => a.userId).toList(),
        // PUT은 전체 교체라 제목/메모만 바꿔도 나머지를 다시 실어 보내야 지워지지 않는다.
        dueDate: todo.dueDate,
      );
      _notifyTodoChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _todos = previous;
        _todoErrorText = '수정을 저장하지 못했어요. 다시 시도해 주세요';
      });
    }
  }

  // 제목/메모만 바꾼 사본(TodoItem.copyWith는 completed만 지원).
  TodoItem _withTitleDetail(TodoItem t, String title, String? detail) =>
      TodoItem(
        id: t.id,
        title: title,
        detail: detail,
        completed: t.completed,
        categoryId: t.categoryId,
        assignees: t.assignees,
        createdAt: t.createdAt,
        dueDate: t.dueDate,
      );

  /// 수동 정렬 flat 목록에서 투두를 드롭했을 때: 순서 변경(로컬 저장) + (드롭 위치가 다른
  /// 카테고리면) 카테고리 이동(서버 저장). 헤더/추가행은 드래그 불가라 oldIndex는 항상 투두다.
  void _onFlatReorder(int oldIndex, int newIndex) {
    _closeSwipeActions(); // 드래그도 "다른 동작" — 열려 있던 액션은 되돌린다.
    final roomId = _roomId;
    if (roomId == null) return;
    final items = _flatItems;
    if (oldIndex < 0 || oldIndex >= items.length) return;
    final moved = items[oldIndex];
    final movedTodo = moved.todo;
    if (moved.kind != _FlatKind.todo || movedTodo == null) return;

    // 대상 카테고리 판정 + 보이는 새 순서 계산은 순수 함수로(테스트 대상: computeFlatReorder).
    final result = computeFlatReorder(
      [
        for (final it in items)
          (kind: it.kind.name, categoryId: it.categoryId, todoId: it.todo?.id),
      ],
      oldIndex,
      newIndex,
    );
    final targetCat = result.targetCategoryId;
    // 필터로 숨겨진 투두는 기존 상대 순서로 뒤에 붙인다(순서 정보 유실 방지).
    final visibleSet = result.visibleOrder.toSet();
    final newOrder = [
      ...result.visibleOrder,
      for (final id in _currentOrderedIds())
        if (!visibleSet.contains(id)) id,
    ];

    final previousOrder = _manualOrder;
    final categoryChanged = movedTodo.categoryId != targetCat;
    setState(() {
      _manualOrder = newOrder;
      if (categoryChanged) {
        _todos = [
          for (final t in _todos)
            if (t.id == movedTodo.id) _withCategory(t, targetCat) else t,
        ];
      }
    });
    _orderStore.save(roomId, newOrder);
    if (categoryChanged) {
      _moveTodoAcross(roomId, movedTodo, targetCat, previousOrder);
    }
  }

  /// 드래그 드롭의 카테고리 이동만 떼어 호출하는 테스트 진입점.
  @visibleForTesting
  Future<void> debugMoveTodoAcross(TodoItem todo, int? targetCat) async {
    final roomId = _roomId;
    if (roomId == null) return;
    await _moveTodoAcross(roomId, todo, targetCat, _currentOrderedIds());
  }

  /// 카테고리 이동을 서버에 반영(낙관적). 실패하면 카테고리와 순서를 모두 원복하고 인라인 에러.
  Future<void> _moveTodoAcross(
    int roomId,
    TodoItem todo,
    int? targetCat,
    List<int> previousOrder,
  ) async {
    try {
      final idToken = await widget.authService.getIdToken();
      await widget.api.updateTodo(
        idToken,
        roomId,
        todo.id,
        title: todo.title,
        detail: todo.detail,
        categoryId: targetCat,
        assigneeUserIds: todo.assignees.map((a) => a.userId).toList(),
        // PUT은 전체 교체라 카테고리만 옮길 때도 마감일을 다시 실어 보내야 지워지지 않는다.
        dueDate: todo.dueDate,
      );
      _notifyTodoChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _todos = [
          for (final t in _todos)
            if (t.id == todo.id) _withCategory(t, todo.categoryId) else t,
        ];
        _manualOrder = previousOrder; // 순서도 함께 원복(카테고리만 되돌리면 불일치)
        _todoErrorText = '카테고리 이동에 실패했어요. 다시 시도해 주세요';
      });
      _orderStore.save(roomId, previousOrder);
    }
  }

  // categoryId를 명시적으로(널 포함) 바꾼 사본. TodoItem.copyWith는 completed만 지원하고
  // nullable copyWith는 "생략 vs null"을 구분 못 해 기타(null)로 이동을 못 하므로 직접 만든다.
  TodoItem _withCategory(TodoItem t, int? categoryId) => TodoItem(
    id: t.id,
    title: t.title,
    detail: t.detail,
    completed: t.completed,
    categoryId: categoryId,
    assignees: t.assignees,
    createdAt: t.createdAt,
    dueDate: t.dueDate,
  );

  /// 현재 수동 표시 순서로 정렬한 전체 투두 id — 순서 저장의 기준 배열.
  List<int> _currentOrderedIds() {
    final all = List<TodoItem>.from(_todos);
    if (_manualOrder.isNotEmpty) {
      int rank(TodoItem t) {
        final i = _manualOrder.indexOf(t.id);
        return i == -1 ? 1 << 30 : i;
      }

      all.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.id.compareTo(b.id);
      });
    }
    return all.map((t) => t.id).toList();
  }

  /// 카테고리/기타 하단 점선 원 추가 어포던스(1번박스) — 일반투두와 같은 크기·패딩·레이아웃.
  /// 텍스트 없이 점선 원만(요청 1번박스). 구분선은 그룹 헬퍼(_buildGroupDivider)가 별도로 그린다.
  /// 탭하면 해당 카테고리로 프리셀렉트된 투두 추가 시트.
  Widget _buildAddAffordance({int? categoryId}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _kHMargin),
      child: _PressableBox(
        key: ValueKey('add-todo-${categoryId ?? 'etc'}'),
        onTap: () {
          _openCreateTodoSheet(categoryId: categoryId);
        },
        // 투두 박스와 동일: 높이 _kRowH, 내부 좌우 12, 점선 원(22) + 12px 간격(스펙 3-C).
        child: const SizedBox(
          height: _kRowH,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _kRowInset),
            child: Row(
              children: [
                _DashedCircleAdd(),
                SizedBox(width: 12),
                // 텍스트 제거 — 일반투두의 제목 자리는 비운다(레이아웃/높이 동일).
                Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TodoListRow extends StatefulWidget {
  const _TodoListRow({
    super.key,
    required this.todo,
    required this.slidableGroup,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onInlineSave,
    this.onEditStart,
    this.reorderIndex,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectToggle,
    this.canComplete = true,
  });

  final TodoItem todo;
  final _SlidableGroup slidableGroup; // 열린 액션 패널을 하나로 유지하는 그룹
  final VoidCallback onToggle; // 체크 원 탭 = 완료 토글
  final VoidCallback onEdit; // information 아이콘 탭 = 상세/수정 시트(2026-08-09)
  final VoidCallback onDelete; // 좌측 스와이프 = 삭제

  /// 제목/메모 인라인 저장(2026-08-09). 나머지 필드(카테고리·담당자·마감일)는 호출부가
  /// 기존값을 재전송한다(PUT 전체 교체). 빈 메모는 null.
  final Future<void> Function({required String title, String? detail})
  onInlineSave;

  /// 편집 진입 순간 화면 정리(열린 스와이프 닫기 + 대기 중 완료 flush).
  final VoidCallback? onEditStart;
  final int? reorderIndex; // 수동 정렬 시 드래그 인덱스(null이면 드래그 불가, 롱프레스로 시작)
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelectToggle;

  /// 완료 권한(FR-39): 담당자 미지정이거나 내가 담당이면 true. 담당자가 있는데
  /// 내가 아니면 false → 체크박스를 회색 비활성으로 표시하고 탭을 막는다.
  final bool canComplete;

  @override
  State<_TodoListRow> createState() => _TodoListRowState();
}

class _TodoListRowState extends State<_TodoListRow> {
  late final TextEditingController _titleCtl = TextEditingController(
    text: widget.todo.title,
  );
  late final TextEditingController _memoCtl = TextEditingController(
    text: widget.todo.detail ?? '',
  );
  final FocusNode _titleFocus = FocusNode();
  final FocusNode _memoFocus = FocusNode();

  bool _editing = false;
  bool _committing = false;

  @override
  void didUpdateWidget(covariant _TodoListRow old) {
    super.didUpdateWidget(old);
    // 편집 중이 아닐 때만 외부 변경(리로드)을 컨트롤러에 반영 — 입력 덮어쓰기 방지.
    if (!_editing) {
      if (widget.todo.title != _titleCtl.text) {
        _titleCtl.text = widget.todo.title;
      }
      final memo = widget.todo.detail ?? '';
      if (memo != _memoCtl.text) _memoCtl.text = memo;
    }
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _memoCtl.dispose();
    _titleFocus.dispose();
    _memoFocus.dispose();
    super.dispose();
  }

  /// 제목/메모 탭 → 인라인 편집 진입 + 해당 필드에 포커스(키보드 즉시).
  void _enterEdit({required bool memo}) {
    if (_editing) {
      (memo ? _memoFocus : _titleFocus).requestFocus();
      return;
    }
    widget.onEditStart?.call(); // 열린 스와이프 닫기 + 대기 완료 flush
    setState(() => _editing = true);
    // 포커스는 다음 프레임에 — 그때 FocusNode가 트리에 붙는다(autofocus 2개 동시 지정 금지).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (memo ? _memoFocus : _titleFocus).requestFocus();
    });
  }

  /// 편집 종료 + (변경 시) 저장. 바깥 탭·키보드 done·information 어디서 불려도 **한 번만**.
  /// 빈 제목은 저장하지 않고 원래 제목으로 되돌린다. 저장 실패는 호출부가 인라인 에러로 처리
  /// (여기선 `_load` 같은 재조회를 하지 않아 입력이 유실되지 않는다).
  Future<void> _commit() async {
    // mounted 가드: 편집 중 행이 트리에서 빠지면(예: 남이 담당 재배정 → 리로드로 필터아웃)
    // 포커스 상실 콜백이 죽은 State에 setState를 때릴 수 있다.
    if (!mounted || !_editing || _committing) return;
    _committing = true;
    final rawTitle = _titleCtl.text.trim();
    final title = rawTitle.isEmpty ? widget.todo.title : rawTitle;
    final memo = _memoCtl.text.trim();
    final detail = memo.isEmpty ? null : memo;
    final changed = title != widget.todo.title || detail != widget.todo.detail;

    setState(() => _editing = false); // onFocusChange 재진입 즉시 차단
    FocusManager.instance.primaryFocus?.unfocus();
    if (rawTitle.isEmpty) _titleCtl.text = widget.todo.title; // 표시도 원복

    try {
      if (changed) await widget.onInlineSave(title: title, detail: detail);
    } finally {
      _committing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final todo = widget.todo;
    // 본문 15·400. 편집 입력은 항상 진한 잉크(_kInk) — 완료 투두를 편집해도 회색으로 안 나오게.
    // 읽기 표시만 완료 시 연회색 + 엄청 연한 회색 1px 취소선(2026-08-09).
    final baseTitleStyle = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.3, // 본문 line-height 130%(2026-08-09)
      color: _kInk,
    );
    final readTitleStyle = todo.completed
        ? baseTitleStyle.copyWith(
            color: AppColors.completedTodo,
            decoration: TextDecoration.lineThrough,
            decorationColor: AppColors.borderSoft,
            decorationThickness: 1,
          )
        : baseTitleStyle;
    // 메모 13 / muted (요구 1).
    final memoStyle = AppTypography.caption.copyWith(color: AppColors.muted);
    final trailing = todo.assignees.isNotEmpty
        ? _AssigneeAvatars(assignees: todo.assignees)
        : const SizedBox.shrink();

    // 일괄선택 모드: 편집 없음(기존 동작 유지). 행 전체 탭 = 선택 토글.
    if (widget.selectionMode) {
      return Padding(
        padding: const EdgeInsets.only(bottom: _kRowGap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kHMargin),
          child: _PressableBox(
            onTap: widget.onSelectToggle,
            // 일반 행과 동일한 상단 정렬·세로 여백 — 항목 선택 모드로 들어가도 제목이 위아래로
            // 튀지 않게(2026-08-09 상단 정렬 통일).
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _kRowH),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _kRowInset,
                  vertical: 11,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TodoCheckbox(
                      checked: widget.selected,
                      onTap: widget.onSelectToggle ?? () {},
                      size: 22,
                      borderColor: _kCircleBorder,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(todo.title, style: readTitleStyle)),
                    trailing,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final readOnly = !widget.canComplete;
    final hasMemo = (todo.detail ?? '').trim().isNotEmpty;

    // 인라인 입력은 **테두리·배경·패딩이 전혀 없어야** 읽기 Text와 위치가 어긋나지 않는다.
    // `InputDecoration.collapsed`는 enabled/focusedBorder를 null로 둬서 테마의 아웃라인 테두리가
    // 스며든다 — 그래서 모든 보더를 명시적으로 none 처리하고 isCollapsed + 패딩 0으로 둔다.
    InputDecoration bareInput(String hint, [TextStyle? hintStyle]) =>
        InputDecoration(
          isCollapsed: true,
          filled: false,
          contentPadding: EdgeInsets.zero,
          hintText: hint,
          hintStyle: hintStyle,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        );

    // ── 제목/메모 그룹 (제목 > 메모, 간격 4) ──
    final Widget group = _editing
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleCtl,
                focusNode: _titleFocus,
                style: baseTitleStyle,
                cursorColor: AppColors.primary,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _memoFocus.requestFocus(),
                decoration: bareInput('할 일 입력'),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _memoCtl,
                focusNode: _memoFocus,
                style: memoStyle,
                cursorColor: AppColors.primary,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  _commit();
                },
                decoration: bareInput(
                  '메모 추가',
                  memoStyle.copyWith(color: AppColors.mutedSoft),
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _enterEdit(memo: false),
                  child: Text(todo.title, style: readTitleStyle),
                ),
              ),
              if (hasMemo) ...[
                const SizedBox(height: 4),
                Semantics(
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _enterEdit(memo: true),
                    child: Text(todo.detail!, style: memoStyle),
                  ),
                ),
              ],
              // 첨부 사진 썸네일(2026-08-24 #65) — 읽기 모드 전용. 편집 진입 시
              // 사라지며 행이 줄어드는 점프는 의도다(편집 중엔 입력에 집중).
              // 간격 8: 메모 간격 4보다 한 단계 넓게(specs/design.md 투두 탭 절).
              if ((todo.imageUrl ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                TodoRowThumbnail(
                  key: ValueKey('todo-thumb-${todo.id}'),
                  url: todo.imageUrl!,
                ),
              ],
            ],
          );

    // 행 내용 — 순서: 체크박스 · (제목/메모 그룹) · [편집 시 information] · 프로필, 간격 10.
    Widget content = ConstrainedBox(
      key: ValueKey('todo-press-${todo.id}'),
      constraints: const BoxConstraints(minHeight: _kRowH),
      child: Padding(
        // 세로 11 — 한 줄 행은 22(콘텐츠)+22=44(_kRowH) 유지, 메모가 붙어 길어지면 위에서부터
        // 쌓이게 상단 정렬한다(2026-08-09 "중앙정렬 말고 위로").
        padding: const EdgeInsets.symmetric(
          horizontal: _kRowInset,
          vertical: 11,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TodoCheckbox(
              key: ValueKey('todo-checkbox-${todo.id}'),
              checked: todo.completed,
              onTap: widget.onToggle,
              size: 22,
              borderColor: _kCircleBorder,
              enabled: widget.canComplete,
            ),
            const SizedBox(width: 10),
            Expanded(child: group),
            if (_editing) ...[
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: '상세 보기',
                child: GestureDetector(
                  key: ValueKey('todo-info-${todo.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await _commit(); // 저장 커밋 후 최신 값으로 시트 열기(stale 방지)
                    if (mounted) widget.onEdit();
                  },
                  child: Image.asset(
                    'assets/icons/icon_information.png',
                    width: 24, // 프로필 아바타(_AssigneeAvatars 24)와 크기 통일
                    height: 24,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ],
            if (trailing is! SizedBox) const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );

    // 읽기전용(내 담당 아님) 흐림 — 편집 중엔 입력이 보이게 해제한다.
    if (readOnly && !_editing) {
      content = Opacity(opacity: 0.55, child: content);
    }

    // 편집 중: 바깥 탭으로 포커스 해제(TapRegion) + 그룹 포커스를 잃으면 저장(Focus).
    // 드래그/스와이프는 텍스트 선택과 충돌하므로 감싸지 않는다.
    if (_editing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: _kRowGap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kHMargin),
          child: TapRegion(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            child: Focus(
              onFocusChange: (has) {
                if (!has) _commit();
              },
              child: content,
            ),
          ),
        ),
      );
    }

    // 읽기 모드: 수동 정렬 시 롱프레스 드래그 + 좌측 스와이프 삭제.
    Widget row = content;
    if (widget.reorderIndex != null) {
      row = ReorderableDelayedDragStartListener(
        key: ValueKey('todo-drag-${todo.id}'),
        index: widget.reorderIndex!,
        child: row,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: _kRowGap),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kHMargin),
        child: _SwipeActionRow(
          key: ValueKey('todo-slidable-${todo.id}'),
          group: widget.slidableGroup,
          onDismissed: widget.onDelete,
          actions: [
            _RowActionButton(
              key: ValueKey('todo-delete-${todo.id}'),
              label: '삭제',
              background: AppColors.accentDanger,
              foreground: AppColors.onPrimary,
              onPressed: widget.onDelete,
            ),
          ],
          child: row,
        ),
      ),
    );
  }
}

/// 열린 스와이프 액션 패널을 화면에 **하나만** 유지하기 위한 컨트롤러 모음(요청).
/// 행/헤더가 만든 [SlidableController]를 등록해두고, 다른 동작이 시작되면 전부 닫는다.
/// 패키지의 `SlidableAutoCloseBehavior`를 쓰지 않는 이유: 열린 상태의 탭을 AbsorbPointer로
/// 먹어버려서 "닫고 그 동작도 바로 실행"(사용자 확정)이 불가능하다.
class _SlidableGroup {
  final List<SlidableController> _controllers = [];

  void register(SlidableController controller) => _controllers.add(controller);

  void unregister(SlidableController controller) =>
      _controllers.remove(controller);

  /// 열려 있는 패널을 모두 닫는다. [except]는 방금 열리는 중인 자신을 제외할 때 쓴다.
  void closeAll({SlidableController? except}) {
    // close()가 리스너를 통해 목록을 건드릴 수 있어 사본을 순회한다.
    for (final controller in List.of(_controllers)) {
      if (controller == except || controller.closing) continue;
      if (controller.ratio != 0) controller.close();
    }
  }
}

/// 눌림(pressed) 배경을 직접 그리는 탭 영역 — `InkWell` 대체.
/// InkWell을 쓰지 않는 이유: ① 스플래시가 남아 좌우로 슬라이드하는 동안 행에 배경색이
/// 깔려 보인다(요청: 슬라이드 중엔 투명), ② 리플이 박스를 넘어 번진다.
/// 수평 드래그가 제스처 아레나를 가져가면 onTapCancel이 즉시 떨어져 배경이 사라진다.
class _PressableBox extends StatefulWidget {
  const _PressableBox({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_PressableBox> createState() => _PressableBoxState();
}

class _PressableBoxState extends State<_PressableBox> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          // 눌리지 않은 상태는 투명 — 슬라이드 중에도 배경색이 생기지 않는다.
          color: _pressed ? AppColors.surfaceStrong : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: widget.child,
      ),
    );
  }
}

/// 스와이프 액션 버튼 — 시각 크기 50×28(라운드 8)이지만 **히트박스는 행 높이 전체**로
/// 넓힌다(design.md §6: 탭 영역 최소 44×44 — 파괴적인 [삭제]가 [수정] 옆 4px에 붙어 있어
/// 오터치 위험이 특히 크다). 탭하면 자기 패널을 닫고 콜백을 실행한다.
class _RowActionButton extends StatelessWidget {
  const _RowActionButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  /// 끝까지 당겨 삭제되는 구간에서 쓸 **배경만 좌우로 늘어난** 버전(요청 2).
  /// 높이(28)와 라벨은 그대로 두고 폭만 주어진 공간을 채운다 — 패널이 커질수록 배경이 넓어진다.
  Widget stretched() => _StretchedRowAction(
    label: label,
    background: background,
    foreground: foreground,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Slidable.of(context)?.close();
          onPressed();
        },
        child: SizedBox(
          width: _kActionBtnW,
          height: _kRowH, // 히트박스(44) — 시각 박스는 아래 28
          child: Center(
            child: Container(
              width: _kActionBtnW,
              height: _kActionBtnH,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `DismissiblePane`의 모션. 이 위젯은 **한 번 마운트되면 계속 남는다**(패키지가
/// `isDismissibleReady`를 되돌리지 않는다) — 그래서 스스로 두 모습을 오간다:
///  · 열린 상태(패널 폭 이내) → 평소의 버튼 배치
///  · 더 당긴 상태(삭제 확정 구간) → 배경이 좌우로 넓어진 버전
/// 이걸 구분하지 않고 늘어난 버전만 주면, 손을 떼고 패널이 닫힌 뒤에도 늘어난 채로 남는다.
class _DismissMotion extends StatelessWidget {
  const _DismissMotion({required this.actionsRow, required this.stretched});

  final Widget actionsRow;
  final Widget stretched;

  @override
  Widget build(BuildContext context) {
    final controller = Slidable.of(context);
    final extentRatio = ActionPane.of(context)?.extentRatio;
    if (controller == null || extentRatio == null) return actionsRow;
    return AnimatedBuilder(
      animation: controller.animation,
      builder: (context, _) {
        // 부동소수 오차로 경계에서 깜빡이지 않게 아주 작은 여유를 둔다.
        final past = controller.ratio.abs() > extentRatio + 0.001;
        return past ? stretched : actionsRow;
      },
    );
  }
}

/// 끝까지 당기는 동안(=삭제 확정 구간) 보여주는 액션 — 같은 색·높이의 배경이 **좌우로 꽉 찬다**.
/// 라벨은 오른쪽(원래 버튼이 있던 자리)에 남겨 무엇이 일어나는지 알 수 있게 한다.
/// 탭 대상이 아니다(손을 떼는 순간 삭제된다).
class _StretchedRowAction extends StatelessWidget {
  const _StretchedRowAction({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: _kActionBtnH,
        width: double.infinity,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

/// 좌측 스와이프로 [actions](50×28, 사이 4px)를 드러내는 행 래퍼.
/// 자기 [SlidableController]를 [group]에 등록해, 열리는 순간 다른 패널을 모두 닫는다.
/// [onDismissed]를 주면 끝까지 당겼을 때 그대로 실행된다(투두 삭제). 확인 모달이 필요한
/// 카테고리 삭제는 null로 둬서 전체 스와이프 즉시 실행을 막는다.
class _SwipeActionRow extends StatefulWidget {
  const _SwipeActionRow({
    super.key,
    required this.group,
    required this.actions,
    required this.child,
    this.onDismissed,
  });

  final _SlidableGroup group;

  /// 드러날 액션 버튼들. `_RowActionButton` 으로 타입을 좁혀 둔 이유는, 끝까지 당기는 구간에서
  /// 마지막 액션의 "배경만 늘어난" 버전(`stretched()`)이 필요하기 때문이다.
  final List<_RowActionButton> actions;
  final Widget child;
  final VoidCallback? onDismissed;

  @override
  State<_SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<_SwipeActionRow>
    with TickerProviderStateMixin {
  late final SlidableController _controller = SlidableController(this);
  // DismissiblePane은 Slidable에 key를 요구한다(리스트에서 제거될 때 상태가 다음 항목으로
  // 밀리지 않도록). 이 위젯은 호출자에게서 키를 받으니, 내부 Slidable엔 State와 1:1인 키를 준다.
  final Key _slidableKey = UniqueKey();
  bool _wasOpen = false;

  @override
  void initState() {
    super.initState();
    widget.group.register(_controller);
    _controller.animation.addListener(_handleSlide);
  }

  @override
  void dispose() {
    _controller.animation.removeListener(_handleSlide);
    widget.group.unregister(_controller);
    _controller.dispose();
    super.dispose();
  }

  /// 닫힘→열림으로 넘어가는 순간에만 다른 패널을 닫는다(매 프레임 호출 방지).
  void _handleSlide() {
    final open = _controller.ratio != 0;
    if (open && !_wasOpen) widget.group.closeAll(except: _controller);
    _wasOpen = open;
  }

  /// 드러날 폭 = [행과의 간격 4] + 버튼들(50) + [버튼 사이 간격 4].
  /// 버튼 크기를 픽셀로 고정해야 해서 실제 행 폭으로 나눠 비율(extentRatio)로 환산한다.
  double get _actionsExtent {
    final count = widget.actions.length;
    return _kActionGap + count * _kActionBtnW + (count - 1) * _kActionGap;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extentRatio = (_actionsExtent / constraints.maxWidth).clamp(
          0.05,
          0.9,
        );
        final onDismissed = widget.onDismissed;
        // 평소(패널이 열린 상태)의 버튼 배치 — BehindMotion 과 DismissiblePane 이 함께 쓴다.
        final actionsRow = Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.actions.length; i++) ...[
                if (i > 0) const SizedBox(width: _kActionGap),
                widget.actions[i],
              ],
            ],
          ),
        );
        return Slidable(
          key: _slidableKey,
          controller: _controller,
          // BehindMotion — StretchMotion은 고정 폭 버튼을 찌그러뜨린다(버튼 크기 고정 요청).
          endActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: extentRatio,
            // 끝까지(60% 이상) 당기면 그대로 실행(투두 삭제만). 그 구간에는 버튼 대신
            // **배경이 좌우로 넓어지는** 버전을 보여준다(요청 2) — 패널이 커질수록 같이 넓어진다.
            dismissible: onDismissed == null
                ? null
                : DismissiblePane(
                    onDismissed: onDismissed,
                    dismissThreshold: 0.6,
                    motion: _DismissMotion(
                      actionsRow: actionsRow,
                      stretched: widget.actions.last.stretched(),
                    ),
                  ),
            children: [Expanded(child: actionsRow)],
          ),
          child: widget.child,
        );
      },
    );
  }
}

class _AssigneeAvatars extends StatelessWidget {
  const _AssigneeAvatars({required this.assignees});

  final List<MemberBrief> assignees;

  // 담당자 뱃지 24px(스펙 3-B). 여럿이면 겹쳐 표시.
  static const double _size = 24;
  static const double _overlap = 12;

  @override
  Widget build(BuildContext context) {
    final shown = assignees.take(3).toList();
    final overflow = assignees.length - shown.length;
    final slotCount = shown.length + (overflow > 0 ? 1 : 0);
    final width = _size + (slotCount - 1) * _overlap;

    return SizedBox(
      width: width,
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(left: i * _overlap, child: _avatar(shown[i])),
          if (overflow > 0)
            Positioned(
              left: shown.length * _overlap,
              child: Container(
                width: _size,
                height: _size,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.border,
                ),
                child: Text('+$overflow', style: AppTypography.caption),
              ),
            ),
        ],
      ),
    );
  }

  Widget _avatar(MemberBrief member) =>
      AssigneeAvatar(member: member, size: _size);
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({
    required this.title,
    required this.initialName,
    required this.confirmLabel,
    required this.onSubmit,
  });

  final String title;
  final String initialName;
  final String confirmLabel;
  final Future<void> Function(String name) onSubmit;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  bool _loading = false;
  String? _errorText;

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '이름을 입력해 주세요');
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await widget.onSubmit(name);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = '저장하지 못했어요. 다시 시도해 주세요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 20,
            enabled: !_loading,
          ),
          if (_errorText != null)
            Text(
              _errorText!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.accentDanger,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: _loading ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _ConfirmDeleteCategoryDialog extends StatefulWidget {
  const _ConfirmDeleteCategoryDialog({required this.onConfirm});

  final Future<void> Function() onConfirm;

  @override
  State<_ConfirmDeleteCategoryDialog> createState() =>
      _ConfirmDeleteCategoryDialogState();
}

class _ConfirmDeleteCategoryDialogState
    extends State<_ConfirmDeleteCategoryDialog> {
  bool _loading = false;
  String? _errorText;

  Future<void> _confirm() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await widget.onConfirm();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = '삭제하지 못했어요. 다시 시도해 주세요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('카테고리를 삭제할까요?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('삭제하면 안의 투두는 기타로 남아요.'),
          if (_errorText != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _errorText!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.accentDanger,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: _loading ? null : _confirm,
          child: const Text(
            '삭제',
            style: TextStyle(color: AppColors.accentDanger),
          ),
        ),
      ],
    );
  }
}

/// 세그먼티드 컨트롤 — design.md §6 세그먼트 규격. 트랙 `surface-strong`+pill,
/// 선택칸만 `surface` 채움 + `elevation.float`(입체 카드) + `foreground` 텍스트.
class _SegmentedToggle extends StatelessWidget {
  const _SegmentedToggle({
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// 전환 시간 — design.md §6(모션 토큰 부재 임시값, `specs/OPEN.md`).
  static const _duration = Duration(milliseconds: 150);

  @override
  Widget build(BuildContext context) {
    // 트랙: 높이 40, radius.pill, 배경 surface-soft(2026-08-06 지정).
    return Container(
      key: const ValueKey('segmented-track'),
      height: _kSegHeight,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 선택 알약은 **하나뿐**이고 좌우로 미끄러진다(2026-08-06 요청). 칸마다 배경을
          // 켜고 끄면 이동이 아니라 "사라졌다 나타나기"가 된다.
          AnimatedAlign(
            duration: _duration,
            curve: Curves.easeOut,
            alignment: _thumbAlignment,
            child: FractionallySizedBox(
              widthFactor: 1 / segments.length,
              heightFactor: 1,
              child: Container(
                key: const ValueKey('segmented-thumb'),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < segments.length; i++)
                Expanded(child: _segment(i)),
            ],
          ),
        ],
      ),
    );
  }

  /// 칸 i의 중심에 알약을 놓는 정렬값 — 칸이 하나뿐이면 가운데.
  Alignment get _thumbAlignment {
    if (segments.length < 2) return Alignment.center;
    return Alignment(-1 + 2 * selectedIndex / (segments.length - 1), 0);
  }

  Widget _segment(int index) {
    final selected = index == selectedIndex;
    // 칸 자체는 배경이 없다(투명) — 배경은 위의 알약 하나가 맡는다.
    // 글씨색은 AnimatedDefaultTextStyle이 보간해 fade처럼 바뀐다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(index),
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: _duration,
          curve: Curves.easeOut,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.onPrimary : AppColors.muted,
          ),
          child: Text(segments[index]),
        ),
      ),
    );
  }
}

/// 더보기 ⋯ 플로팅 카드 — 항목 탭 시 값을 pop한다(design.md §6 드롭다운).
class _OverflowMenuCard extends StatelessWidget {
  const _OverflowMenuCard({
    required this.showCompleted,
    required this.sortLabel,
  });

  final bool showCompleted;
  final String sortLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppElevation.float,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Material(
          color: AppColors.surface,
          child: SizedBox(
            width: 240,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _item(
                  context,
                  icon: Icons.check_circle_outline,
                  label: '항목 선택',
                  value: 'select',
                ),
                _item(
                  context,
                  icon: Icons.list,
                  label: '카테고리 관리',
                  value: 'categories',
                ),
                _item(
                  context,
                  icon: showCompleted ? Icons.visibility : Icons.visibility_off,
                  label: '완료된 항목 보기',
                  value: 'completed',
                  trailing: showCompleted
                      ? const Icon(
                          Icons.check,
                          size: 18,
                          color: AppColors.primary,
                        )
                      : null,
                ),
                _item(
                  context,
                  icon: Icons.swap_vert,
                  label: '정렬',
                  value: 'sort',
                  trailing: Text(
                    sortLabel,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.content,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.foregroundSoft),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: AppTypography.body)),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing,
            ],
          ],
        ),
      ),
    );
  }
}

/// 점선 원 — 리스트 하단 인라인 추가 어포던스(1번박스). 일반투두의 좌측 체크 원과
/// 같은 22 원(테두리 #C7C7CC). 내부 아이콘 없음(스펙 3-C).
class _DashedCircleAdd extends StatelessWidget {
  const _DashedCircleAdd();

  @override
  Widget build(BuildContext context) {
    // 22×22 점선 원 — 일반투두 체크 원과 동일 크기. 행(48)이 세로 중앙 정렬(스펙 3-C).
    // 원 안에 **작은 + 아이콘**을 넣어 "추가"임을 알린다(2026-08-09 — 동그라미만으로 뜻이 안
    // 읽힌다는 피드백). 점선 테두리·크기는 그대로, + 는 작게·엄청 연한 회색(`color.border`).
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          CustomPaint(size: Size(22, 22), painter: _DashedCirclePainter()),
          Icon(Icons.add, size: 13, color: AppColors.border),
        ],
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter();

  static const double _strokeWidth = 1.5;
  static const int _dashCount = 20;
  static const double _gapFraction = 0.4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kCircleBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - _strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * pi / _dashCount;
    for (var i = 0; i < _dashCount; i++) {
      canvas.drawArc(rect, i * sweep, sweep * (1 - _gapFraction), false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) => false;
}

/// flat(수동정렬) 목록에서 접힌 그룹의 행 — 높이 0으로 **줄어들며** 사라진다(2026-08-05 요청).
///
/// `ReorderableListView`는 항목의 삽입·삭제를 애니메이션하지 않는다. 그래서 접을 때 행을
/// 목록에서 빼는 대신 남겨 두고, 여기서 자식을 빈 박스로 바꿔 [AnimatedSize]가 높이를
/// 애니메이션하게 한다. 다 접히면 높이 0이라 드롭 대상이 되지 못한다.
class _CollapsibleFlatRow extends StatelessWidget {
  const _CollapsibleFlatRow({
    super.key,
    required this.hidden,
    required this.child,
  });

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: hidden ? const SizedBox(width: double.infinity) : child,
    );
  }
}
