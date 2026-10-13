import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// 콕찌르기 결과를 **버튼 안에서** 보여준다(#105). 따로 뜨는 요소는 없다.
  _PokeFeedback _pokeFeedback = _PokeFeedback.none;
  Timer? _pokeFeedbackReset;

  /// 결과 라벨을 보여주는 시간.
  ///
  /// 🔴 임시값이다 — `specs/design.md`에 모션(duration·easing) 절이 아예 없다
  /// (`specs/OPEN.md`「모션/애니메이션 토큰 부재」). 토큰이 생기면 여기를 바꾼다.
  static const _pokeFeedbackDuration = Duration(milliseconds: 1200);

  /// 카테고리 접힘/펼침 상태 — key는 categoryId(미분류는 null). 기본 펼침.
  final Map<int?, bool> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadCharacter();
  }

  @override
  void dispose() {
    // 🔴 반드시 취소한다. 남겨두면 화면을 떠난 뒤 setState 가 불리고, 위젯 테스트에서는
    // "A Timer is still pending…" 으로 **무관한 테스트까지** 깨진다.
    _pokeFeedbackReset?.cancel();
    super.dispose();
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
      if (mounted) _showPokeFeedback(_PokeFeedback.sent);
    } catch (_) {
      // 성공과 **대칭**으로 실패도 같은 자리(버튼 안)에서 알린다. 한쪽만 바꾸면
      // "누른 자리에서 결과를 본다"는 의도가 절반만 지켜진다(#105).
      if (mounted) _showPokeFeedback(_PokeFeedback.failed);
    } finally {
      if (mounted) setState(() => _poking = false);
    }
  }

  /// 결과를 버튼 안에 잠깐 띄웠다가 원래 라벨로 되돌린다.
  void _showPokeFeedback(_PokeFeedback feedback) {
    // 연속으로 누르면(30초당 10회까지 허용된다) 이전 타이머가 남아 먼저 꺼버린다.
    _pokeFeedbackReset?.cancel();
    setState(() => _pokeFeedback = feedback);
    unawaited(
      feedback == _PokeFeedback.sent
          ? HapticFeedback.lightImpact()
          : HapticFeedback.heavyImpact(),
    );
    _pokeFeedbackReset = Timer(_pokeFeedbackDuration, () {
      if (mounted) setState(() => _pokeFeedback = _PokeFeedback.none);
    });
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
            _PokeButton(
              loading: _poking,
              feedback: _pokeFeedback,
              onTap: _poke,
            ),
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
/// 콕찌르기 결과 — **버튼 안에서** 알린다(#105).
enum _PokeFeedback {
  none('찌르기'),
  sent('찔렀어요'),
  failed('안 됐어요');

  const _PokeFeedback(this.label);

  final String label;
}

/// 찌르기 버튼. **결과를 버튼 자신이 보여준다** — 따로 뜨는 토스트·스낵바가 없다(#105).
///
/// 원래는 화면 맨 아래 기본 [SnackBar]였다. 버튼은 프로필 행 오른쪽(화면 위쪽)인데 반응은 맨
/// 아래에 떠서 눈이 따라가야 했고, 모양도 프레임워크 기본값이라 톤이 튀었다. 버튼 위에 말풍선을
/// 띄우는 안도 만들어 봤지만 "덧붙인 느낌"이 남아 접었다.
///
/// 지금 방식은 누른 그 자리에서 라벨이 잠깐 바뀌는 것뿐이다 — 페이스북 콕찌르기·링크드인 연결
/// 요청·듀오링고 응원이 쓰는 방식이고, NN/g 도 버튼을 누른 뒤의 상태 변화를 "시스템 상태 보이기"의
/// 대표적인 형태로 든다.
class _PokeButton extends StatefulWidget {
  const _PokeButton({
    required this.loading,
    required this.feedback,
    required this.onTap,
  });

  final bool loading;
  final _PokeFeedback feedback;
  final VoidCallback onTap;

  @override
  State<_PokeButton> createState() => _PokeButtonState();
}

class _PokeButtonState extends State<_PokeButton>
    with SingleTickerProviderStateMixin {
  /// 🔴 임시값 — 모션 토큰이 없다(`specs/OPEN.md`「모션/애니메이션 토큰 부재」).
  static const _reactionDuration = Duration(milliseconds: 320);

  /// 색이 "뿅" 바뀌는 시간. 짧아야 톡 치는 느낌이 난다.
  static const _colorDuration = Duration(milliseconds: 140);

  late final AnimationController _reaction = AnimationController(
    vsync: this,
    duration: _reactionDuration,
  );

  @override
  void didUpdateWidget(_PokeButton old) {
    super.didUpdateWidget(old);
    // 결과가 막 도착한 순간에만 반응한다. 되돌아갈 때(→ none)는 조용히 바뀐다.
    if (widget.feedback != old.feedback &&
        widget.feedback != _PokeFeedback.none) {
      _reaction.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _reaction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feedback = widget.feedback;
    return Semantics(
      button: true,
      // 결과가 나오면 스크린리더에도 그대로 읽힌다 — 화면과 같은 것을 말한다.
      label: feedback.label,
      child: AnimatedBuilder(
        animation: _reaction,
        builder: (context, child) {
          // 실패는 짧게 좌우로 흔든다. 성공과 글자만 다르면 1.2초 깜빡임 사이에 놓치기 쉽다.
          final shake = feedback == _PokeFeedback.failed
              ? math.sin(_reaction.value * math.pi * 3) *
                    4 *
                    (1 - _reaction.value)
              : 0.0;
          return Transform.translate(offset: Offset(shake, 0), child: child);
        },
        child: Material(
          // 결과에 따라 색이 **살짝 뿅** 바뀐다. Material 이 색 전환을 스스로
          // 애니메이션하므로(animationDuration) 따로 컨트롤러를 두지 않는다.
          //
          // 둘 다 기존 토큰이다 — 새 색을 만들지 않는다. 실패에 `accentDanger` 를 쓰는 건
          // design.md §2 가 허용하는 **의미 전용** 사용이다(강조 용도 혼용이 아니다).
          color: switch (feedback) {
            _PokeFeedback.none => AppColors.primary,
            _PokeFeedback.sent => AppColors.primaryActive,
            _PokeFeedback.failed => AppColors.accentDanger,
          },
          animationDuration: _colorDuration,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            onTap: widget.loading ? null : widget.onTap,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [_icon(), const SizedBox(width: 6), _label(context)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon() {
    if (widget.loading) {
      return const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.onPrimary,
        ),
      );
    }
    final icon = Image.asset(
      'assets/icons/icon_light.png',
      width: 16,
      height: 16,
      color: AppColors.onPrimary,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.bolt, size: 16, color: AppColors.onPrimary),
    );
    if (widget.feedback != _PokeFeedback.sent) return icon;
    // 성공하면 아이콘이 위로 살짝 튀었다 내려앉는다.
    return AnimatedBuilder(
      animation: _reaction,
      builder: (context, child) {
        final t = math.sin(_reaction.value * math.pi);
        return Transform.translate(
          offset: Offset(0, -3 * t),
          child: Transform.scale(scale: 1 + 0.25 * t, child: child),
        );
      },
      child: icon,
    );
  }

  /// 라벨은 **가장 긴 문구만큼 자리를 미리 잡아 둔다.**
  ///
  /// 안 그러면 "찌르기" → "안 됐어요" 로 바뀔 때 버튼이 넓어지고, 같은 Row 안에서 Expanded 로
  /// 이름·완료율을 쥐고 있는 칸이 그만큼 줄어 **글자가 말줄임으로 흔들린다.**
  ///
  /// 숨긴 Text 를 겹쳐 두는 방법도 있지만, 그러면 같은 글자가 트리에 둘이 되어 `find.text` 가
  /// 두 개를 잡는다(테스트에서 실제로 걸렸다). 그래서 폭을 직접 재고 Text 는 하나만 둔다.
  Widget _label(BuildContext context) {
    final style = AppTypography.body.copyWith(
      color: AppColors.onPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final widest = _PokeFeedback.values
        .map((f) {
          final painter = TextPainter(
            text: TextSpan(text: f.label, style: style),
            textDirection: direction,
            textScaler: scaler,
          )..layout();
          return painter.width;
        })
        .reduce(math.max);
    return SizedBox(
      width: widest,
      child: Text(
        widget.feedback.label,
        style: style,
        textAlign: TextAlign.center,
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
