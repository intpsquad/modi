import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/confirm_dialog.dart';
import '../../design/empty_state.dart';
import '../../design/option_menu.dart';
import '../../design/tokens.dart';
import '../../design/tab_header.dart';
import '../auth/auth_service.dart';
import '../room/room_session.dart';
import '../shell/app_shell.dart';
import '../shell/tab_activation.dart';
import 'archive_api.dart';
import 'archive_widgets.dart';

/// S-25 아카이브 폴더 목록 — specs/0010-아카이브-탭.md.
/// 상단 우측 + 버튼으로 바로 폴더를 추가한다(2026-08-08: 검색·⋯ 메뉴 제거).
class ArchiveScreen extends StatefulWidget {
  ArchiveScreen({
    super.key,
    ArchiveApi? api,
    AuthService? authService,
    RoomSession? roomSession,
    TabActivation? tabActivation,
  }) : api = api ?? ArchiveApi(),
       authService = authService ?? AuthService(),
       roomSession = roomSession ?? appRoomSession,
       tabActivation = tabActivation ?? appTabActivation;

  final ArchiveApi api;
  final AuthService authService;
  final RoomSession roomSession;
  final TabActivation tabActivation;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  bool _loading = true;

  /// 한 번이라도 폴더 목록을 그린 뒤인가 — 그 뒤로는 재조회에 전체 스피너를 쓰지 않는다(요청 6).
  bool _loadedOnce = false;
  String? _errorText;
  int? _roomId;
  List<ArchiveFolder> _folders = [];

  /// 폴더 카드 ⋮ 버튼의 앵커 키 — 옵션창을 **그 버튼 아래**에 띄우려면 위치를 알아야 한다.
  /// build 안에서 새로 만들면 리빌드마다 키가 바뀌어 앵커를 잃으므로 여기 모아 둔다.
  final Map<int, GlobalKey> _folderMoreKeys = {};

  GlobalKey _folderMoreKey(int folderId) =>
      _folderMoreKeys.putIfAbsent(folderId, () => GlobalKey());

  // 방 전환 등으로 조회가 겹쳐 호출될 때 먼저 시작한 요청이 나중 요청 결과를 덮어쓰지 않도록 막는 가드.
  int _loadGeneration = 0;

  /// 목록 스크롤 — 모아보기 탭을 (재)탭하면 맨 위로 되돌리는 데 쓴다(2026-08-10).
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.roomSession.addListener(_onRoomSessionChanged);
    widget.tabActivation.addListener(_onTabChanged);
    widget.tabActivation.reselect.addListener(_onTabReselected);
    _load();
  }

  @override
  void dispose() {
    widget.roomSession.removeListener(_onRoomSessionChanged);
    widget.tabActivation.removeListener(_onTabChanged);
    widget.tabActivation.reselect.removeListener(_onTabReselected);
    _scrollController.dispose();
    super.dispose();
  }

  /// 모아보기 탭이 다시 켜지면 조용히 최신 목록으로 맞춘다(요청 1).
  void _onTabChanged() {
    if (!mounted) return;
    if (widget.tabActivation.index == AppShell.archiveIndex) {
      _load(silent: true);
    }
  }

  /// 모아보기 탭을 누를 때마다(전환·재탭) 맨 위로 부드럽게 스크롤한다(2026-08-10 요청).
  void _onTabReselected() {
    if (!mounted) return;
    if (widget.tabActivation.reselect.index != AppShell.archiveIndex) return;
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _onRoomSessionChanged() {
    if (!mounted) return;
    _load();
  }

  /// [silent]이면 전체 스피너 없이 조용히 갱신한다(탭 재진입 등).
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
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _roomId = roomId);
      await _fetchFolders(silent: silent);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorText = '폴더 목록을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  // 전체 화면 스피너는 첫 로드에만 — 그 뒤(폴더 추가/이름수정/삭제 후 재조회, 당겨서 새로고침)
  // 는 기존 목록을 유지한 채 조회하고 결과가 오면 갈아끼운다(요청 6).
  Future<void> _fetchFolders({bool silent = false}) async {
    final roomId = _roomId;
    if (roomId == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      if (!silent && !_loadedOnce) _loading = true;
      _errorText = null;
    });
    try {
      final idToken = await widget.authService.getIdToken();
      final folders = await widget.api.fetchFolders(idToken, roomId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _folders = folders;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorText = '폴더 목록을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  Future<void> _createFolderDialog() async {
    final roomId = _roomId;
    if (roomId == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ArchiveFolderNameDialog(
        title: '폴더 추가',
        initialName: '',
        confirmLabel: '추가하기',
        onSubmit: (name) async {
          final idToken = await widget.authService.getIdToken();
          await widget.api.createFolder(idToken, roomId, name);
        },
      ),
    );
    await _fetchFolders();
  }

  /// 폴더 ⋮ — 공용 옵션창을 **그 카드의 버튼 아래**에 띄운다(2026-08-05 요청).
  /// 예전에는 화면 아래에서 올라오는 바텀시트라 어떤 폴더의 메뉴인지 위상으로 알 수 없었다.
  Future<void> _showFolderActions(ArchiveFolder folder) async {
    final action = await showOptionMenu<String>(
      context: context,
      anchorKey: _folderMoreKey(folder.id),
      items: const [
        OptionMenuItem(
          label: '이름 수정',
          value: 'rename',
          icon: Icons.edit_outlined,
        ),
        OptionMenuItem(
          label: '삭제',
          value: 'delete',
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );
    if (action == 'rename') {
      await _renameFolderDialog(folder);
    } else if (action == 'delete') {
      await _confirmDeleteFolder(folder);
    }
  }

  Future<void> _renameFolderDialog(ArchiveFolder folder) async {
    final roomId = _roomId;
    if (roomId == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ArchiveFolderNameDialog(
        title: '폴더 수정',
        initialName: folder.name,
        confirmLabel: '저장하기',
        onSubmit: (name) async {
          final idToken = await widget.authService.getIdToken();
          await widget.api.renameFolder(idToken, roomId, folder.id, name);
        },
      ),
    );
    await _fetchFolders();
  }

  Future<void> _confirmDeleteFolder(ArchiveFolder folder) async {
    final roomId = _roomId;
    if (roomId == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _ConfirmDeleteFolderDialog(
        onConfirm: () async {
          final idToken = await widget.authService.getIdToken();
          await widget.api.deleteFolder(idToken, roomId, folder.id);
        },
      ),
    );
    await _fetchFolders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(child: _buildBody(context)),
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
            Text('폴더를 불러오고 있어요', style: AppTypography.bodySmall),
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.content),
          child: Text('진행 중인 방이 없어요', style: AppTypography.title),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchFolders,
      color: AppColors.primary,
      child: ListView(
        controller: _scrollController,
        // 헤더는 투두·마이페이지처럼 상단 flush로 둔다 — 위 패딩을 주면 4개 탭 제목의
        // 세로 위치가 어긋난다(2026-08-08 QA). 아래 여백만 유지.
        padding: const EdgeInsets.only(bottom: AppSpacing.content),
        children: [
          _buildTopBar(),
          const SizedBox(height: AppSpacing.content),
          _buildFolderList(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return TabHeader(
      title: '모아보기',
      action: IconButton(
        onPressed: _createFolderDialog,
        icon: const Icon(Icons.add, color: AppColors.foreground),
        tooltip: '폴더 추가',
      ),
    );
  }

  Widget _buildFolderList() {
    final folders = _folders;

    if (folders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
        child: EmptyState(
          icon: Icons.folder_outlined,
          message: '아직 폴더가 없어요',
          actionLabel: '폴더 추가하기',
          onAction: _createFolderDialog,
        ),
      );
    }

    // 2열 그리드 — 스케줄 주(週) 그리드처럼 Row를 이어붙여 모든 카드를 트리에
    // 올린다(GridView의 lazy build로 오프스크린 카드가 테스트에서 안 잡히는 문제 회피).
    final rows = <List<ArchiveFolder?>>[];
    for (var i = 0; i < folders.length; i += 2) {
      rows.add([
        folders[i],
        if (i + 1 < folders.length) folders[i + 1] else null,
      ]);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.content),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < 2; c++) ...[
                    if (c == 1) const SizedBox(width: AppSpacing.content),
                    Expanded(
                      child: row[c] == null
                          ? const SizedBox.shrink()
                          : _ArchiveFolderCard(
                              key: ValueKey('archive-folder-${row[c]!.id}'),
                              folder: row[c]!,
                              onTap: () =>
                                  context.push('/archive/folder/${row[c]!.id}'),
                              moreKey: _folderMoreKey(row[c]!.id),
                              onMore: () => _showFolderActions(row[c]!),
                            ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ArchiveFolderCard extends StatelessWidget {
  const _ArchiveFolderCard({
    super.key,
    required this.folder,
    required this.onTap,
    required this.moreKey,
    required this.onMore,
  });

  final ArchiveFolder folder;
  final VoidCallback onTap;

  /// ⋮ 버튼에 붙이는 앵커 키 — 옵션창을 이 버튼 아래에 띄우는 데 쓰인다.
  final GlobalKey moreKey;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 썸네일(정사각) + 우상단 작은 ⋮.
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ArchiveThumbnail(
                    url: folder.thumbnail,
                    radius: AppRadius.card,
                    placeholderIcon: Icons.folder,
                  ),
                ),
                Positioned(
                  top: AppSpacing.xs,
                  right: AppSpacing.xs,
                  child: Material(
                    color: AppColors.canvas.withValues(alpha: 0.85),
                    shape: const CircleBorder(),
                    child: InkWell(
                      key: moreKey,
                      customBorder: const CircleBorder(),
                      onTap: onMore,
                      child: const Padding(
                        padding: EdgeInsets.all(AppSpacing.xs),
                        child: Icon(
                          Icons.more_vert,
                          size: 18,
                          color: AppColors.foreground,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            folder.name,
            style: AppTypography.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '저장된 항목 ${folder.itemCount}개',
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _ArchiveFolderNameDialog extends StatefulWidget {
  const _ArchiveFolderNameDialog({
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
  State<_ArchiveFolderNameDialog> createState() =>
      _ArchiveFolderNameDialogState();
}

class _ArchiveFolderNameDialogState extends State<_ArchiveFolderNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  bool _loading = false;
  String? _errorText;

  Future<void> _submit() async {
    if (_loading) return;
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
    // 폴더 추가/이름수정 — 아이콘 없이 제목 + 밑줄 입력 + [취소 | 확인](디자이너 지정 2026-08-08).
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
      // 팝업 318×184 고정(디자이너 지정). 좌우 18은 135버튼 2개+간격(12)이 318에 맞도록 계산한 값.
      child: SizedBox(
        width: 318,
        height: 184,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: AppTypography.title,
                textAlign: TextAlign.center,
              ),
              // 밑줄형 입력 — 142px 선(#DDDDDD 1px) + 중앙 placeholder(14/regular #929292).
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: SizedBox(
                      width: 142,
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        maxLength: 20,
                        enabled: !_loading,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.foreground,
                        ),
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '20자 이내 입력 가능',
                          hintStyle: AppTypography.bodySmall.copyWith(
                            color: AppColors.mutedSoft,
                          ),
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          border: const UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _errorText!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.accentDanger,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    width: 135,
                    height: 48,
                    child: AppDialogButton(
                      label: '취소',
                      background: AppColors.surfaceStrong,
                      foreground: AppColors.foreground,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  SizedBox(
                    width: 135,
                    height: 48,
                    child: AppDialogButton(
                      label: widget.confirmLabel,
                      background: AppColors.primary,
                      foreground: AppColors.onPrimary,
                      onPressed: _submit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmDeleteFolderDialog extends StatefulWidget {
  const _ConfirmDeleteFolderDialog({required this.onConfirm});

  final Future<void> Function() onConfirm;

  @override
  State<_ConfirmDeleteFolderDialog> createState() =>
      _ConfirmDeleteFolderDialogState();
}

class _ConfirmDeleteFolderDialogState
    extends State<_ConfirmDeleteFolderDialog> {
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
      title: const Text('폴더를 삭제할까요?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('폴더 안의 자료도 모두 함께 삭제돼요. 되돌릴 수 없어요.'),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
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
