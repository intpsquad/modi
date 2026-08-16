import 'package:flutter/material.dart';

import '../../design/option_menu.dart';
import '../../design/tokens.dart';
import '../auth/auth_service.dart';
import 'archive_api.dart';
import 'archive_widgets.dart';

/// 댓글 행/입력바의 아바타 지름 — 시안(2026-08-09) 기준.
const double _kCommentAvatarSize = 36;

/// 시트 높이 — 화면의 62%(시안 비율). 키보드가 뜨면 viewInsets가 위로 밀어 올린다.
const double _kSheetHeightFactor = 0.62;

/// S-25-B 자료 댓글 바텀시트(2026-08-09) — 딤 + 드래그 핸들 + "댓글" 제목 + 목록(오래된순)
/// + 하단 입력바(내 아바타 + pill 입력). specs/0010-아카이브-탭.md.
///
/// ~~서버는 조회·작성만 지원한다(append-only) — 수정·삭제 UI는 백엔드 API가 생기면 후속.~~
/// → **2026-08-09에 백엔드가 들어왔고 UI도 붙었다**(`docs/backend/archive-comments-handoff.md`).
/// 내 댓글에만 `⋯`(수정/삭제)가 붙는다 — 서버도 작성자 본인이 아니면 403이다.
Future<void> showArchiveCommentsSheet(
  BuildContext context, {
  required ArchiveApi api,
  required AuthService authService,
  required int roomId,
  required int itemId,
  required ValueChanged<int> onCountChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
    isScrollControlled: true,
    builder: (context) => ArchiveCommentsSheet(
      api: api,
      authService: authService,
      roomId: roomId,
      itemId: itemId,
      onCountChanged: onCountChanged,
    ),
  );
}

class ArchiveCommentsSheet extends StatefulWidget {
  const ArchiveCommentsSheet({
    super.key,
    required this.api,
    required this.authService,
    required this.roomId,
    required this.itemId,
    required this.onCountChanged,
  });

  final ArchiveApi api;
  final AuthService authService;
  final int roomId;
  final int itemId;

  /// 작성 성공마다 최신 댓글 수를 부모(상세 하단 바 카운트)에 알린다 — 시트가 드래그로
  /// 닫혀도(결과 없음) 카운트가 어긋나지 않도록 pop 결과 대신 콜백을 쓴다.
  final ValueChanged<int> onCountChanged;

  @override
  State<ArchiveCommentsSheet> createState() => _ArchiveCommentsSheetState();
}

class _ArchiveCommentsSheetState extends State<ArchiveCommentsSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _loadFailed = false;
  bool _sending = false;
  String? _sendErrorText;
  List<ArchiveComment> _comments = [];

  /// 입력바에 보여줄 내 프로필 — `/me/profile`. 실패해도 시트는 동작한다(이니셜 폴백).
  ArchiveItemCreator? _me;

  /// 내 댓글 ⋯ 옵션창 앵커 — 리스트 재빌드에도 안정적이도록 댓글 id로 캐시한다.
  final Map<int, GlobalKey> _menuKeys = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadMe();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final idToken = await widget.authService.getIdToken();
      final comments = await widget.api.fetchComments(
        idToken,
        widget.roomId,
        widget.itemId,
      );
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
      widget.onCountChanged(comments.length);
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadMe() async {
    try {
      final idToken = await widget.authService.getIdToken();
      final me = await widget.api.fetchMyBrief(idToken);
      if (!mounted) return;
      setState(() => _me = me);
    } catch (_) {
      // 입력바 아바타는 장식 — 실패하면 이니셜 폴백('?')으로 둔다.
    }
  }

  /// 오래된순 목록이라 새 댓글은 맨 아래 — 열 때/작성 후 맨 아래로 붙인다(채팅형).
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _sendErrorText = null;
    });
    try {
      final idToken = await widget.authService.getIdToken();
      final created = await widget.api.createComment(
        idToken,
        widget.roomId,
        widget.itemId,
        body,
      );
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, created];
        _sending = false;
      });
      _controller.clear();
      widget.onCountChanged(_comments.length);
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      // 실패하면 입력값을 지우지 않는다 — 그대로 재시도할 수 있게.
      setState(() {
        _sending = false;
        _sendErrorText = '댓글을 등록하지 못했어요. 다시 시도해 주세요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      // 키보드가 뜨면 시트 전체를 위로 — 입력바가 키보드 위에 붙는다.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: media.size.height * _kSheetHeightFactor,
          child: Column(
            children: [
              // 드래그 핸들(40×4) — room_switcher_sheet와 같은 규격.
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(
                  top: AppSpacing.md,
                  bottom: AppSpacing.content,
                ),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.content),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('댓글', style: AppTypography.section),
                ),
              ),
              const SizedBox(height: AppSpacing.content),
              Expanded(child: _buildBody()),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('댓글을 불러오지 못했어요', style: AppTypography.title),
            const SizedBox(height: AppSpacing.cardGap),
            OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    if (_comments.isEmpty) {
      return Center(
        child: Text(
          '첫 댓글을 남겨보세요',
          style: AppTypography.bodySmall.copyWith(color: AppColors.mutedSoft),
        ),
      );
    }
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
      itemCount: _comments.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.lg),
      itemBuilder: (context, index) {
        final c = _comments[index];
        // 내 댓글만 ⋯(수정/삭제) — 서버가 작성자 본인만 허용(403)한다.
        final mine =
            c.author?.userId != null &&
            c.author!.userId == widget.authService.currentUserId;
        final key = mine ? (_menuKeys[c.id] ??= GlobalKey()) : null;
        return _CommentRow(
          comment: c,
          menuAnchorKey: key,
          onMenu: mine ? () => _openCommentMenu(c, key!) : null,
        );
      },
    );
  }

  /// 내 댓글 ⋯ → 수정/삭제 옵션창(2026-08-09).
  Future<void> _openCommentMenu(
    ArchiveComment comment,
    GlobalKey anchorKey,
  ) async {
    final choice = await showOptionMenu<String>(
      context: context,
      anchorKey: anchorKey,
      items: const [
        OptionMenuItem(label: '수정', value: 'edit'),
        OptionMenuItem(label: '삭제', value: 'delete', danger: true),
      ],
    );
    if (!mounted) return;
    if (choice == 'edit') {
      await _editComment(comment);
    } else if (choice == 'delete') {
      await _deleteComment(comment);
    }
  }

  Future<void> _editComment(ArchiveComment comment) async {
    final newBody = await showDialog<String>(
      context: context,
      builder: (context) => _CommentEditDialog(initialBody: comment.body),
    );
    if (newBody == null ||
        newBody.isEmpty ||
        newBody == comment.body ||
        !mounted) {
      return;
    }
    try {
      final idToken = await widget.authService.getIdToken();
      final updated = await widget.api.updateComment(
        idToken,
        widget.roomId,
        widget.itemId,
        comment.id,
        newBody,
      );
      if (!mounted) return;
      setState(() {
        _comments = [
          for (final c in _comments)
            if (c.id == comment.id) updated else c,
        ];
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('댓글 수정에 실패했어요')));
    }
  }

  Future<void> _deleteComment(ArchiveComment comment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('댓글을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final idToken = await widget.authService.getIdToken();
      await widget.api.deleteComment(
        idToken,
        widget.roomId,
        widget.itemId,
        comment.id,
      );
      if (!mounted) return;
      setState(() {
        _comments = _comments.where((c) => c.id != comment.id).toList();
      });
      widget.onCountChanged(_comments.length);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('댓글 삭제에 실패했어요')));
    }
  }

  /// 하단 고정 입력바 — 내 아바타 + pill 입력(전송은 키보드 액션/엔터).
  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.content,
        AppSpacing.md,
        AppSpacing.content,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_sendErrorText != null) ...[
            Text(
              _sendErrorText!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.accentDanger,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Row(
            children: [
              ArchiveAuthorAvatar(
                author: _me,
                size: _kCommentAvatarSize,
                semanticsPrefix: '내 프로필',
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  key: const ValueKey('archive-comment-field'),
                  controller: _controller,
                  enabled: !_sending,
                  maxLength: 500,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '댓글을 입력해주세요.',
                    hintStyle: AppTypography.bodySmall.copyWith(
                      color: AppColors.mutedSoft,
                    ),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.content,
                      vertical: AppSpacing.md,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: const BorderSide(color: AppColors.borderSoft),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: const BorderSide(color: AppColors.borderSoft),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      borderSide: const BorderSide(
                        color: AppColors.borderStrong,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 댓글 한 행 — 아바타 + [닉네임 / 본문]. 본문은 전체 표시(시트 안이라 말줄임 없음).
/// 댓글 수정 다이얼로그.
///
/// 🔴 **컨트롤러를 다이얼로그 자신이 소유해야 한다**(2026-08-16). 예전에는 `_editComment`가
/// 컨트롤러를 만들고 `showDialog` 가 반환하자마자 `dispose()` 했는데, 그 시점에 다이얼로그의
/// **닫힘 애니메이션이 아직 돌고 있어** 안의 `TextField` 가 죽은 컨트롤러로 다시 그려졌다:
///
///     A TextEditingController was used after being disposed.
///
/// 릴리스 빌드는 assert 가 빠져 조용히 넘어가고, 이 시트에 테스트가 없어서 아무도 못 봤다
/// (테스트를 처음 붙이면서 드러났다). `State.dispose()` 에 맡기면 위젯이 트리에서 완전히
/// 빠진 뒤에 정리되므로 이 창이 닫힌다.
class _CommentEditDialog extends StatefulWidget {
  const _CommentEditDialog({required this.initialBody});

  final String initialBody;

  @override
  State<_CommentEditDialog> createState() => _CommentEditDialogState();
}

class _CommentEditDialogState extends State<_CommentEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialBody,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('댓글 수정'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        maxLines: null,
        decoration: const InputDecoration(counterText: ''),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('저장'),
        ),
      ],
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, this.menuAnchorKey, this.onMenu});

  final ArchiveComment comment;

  /// 내 댓글일 때만 준다 — 우상단 ⋯(수정/삭제) 옵션창의 앵커·콜백.
  final GlobalKey? menuAnchorKey;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final author = comment.author;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArchiveAuthorAvatar(
          author: author,
          size: _kCommentAvatarSize,
          semanticsPrefix: '작성자',
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                author?.nickname ?? '(알 수 없음)',
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: author == null
                      ? AppColors.mutedSoft
                      : AppColors.foreground,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(comment.body, style: AppTypography.bodySmall),
            ],
          ),
        ),
        if (onMenu != null)
          GestureDetector(
            key: menuAnchorKey,
            behavior: HitTestBehavior.opaque,
            onTap: onMenu,
            child: Semantics(
              button: true,
              label: '댓글 더보기',
              child: const Padding(
                padding: EdgeInsets.only(left: AppSpacing.sm, top: 2),
                child: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: AppColors.mutedSoft,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
