import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/ai_hint_banner.dart';
import '../../design/confirm_dialog.dart';
import '../../design/option_menu.dart';
import '../../design/tokens.dart';
import '../auth/auth_service.dart';
import '../room/room_session.dart';
import 'archive_api.dart';
import 'archive_comments_sheet.dart';
import 'archive_widgets.dart';
import 'crawl_status_badge.dart';
import 'link_label.dart';
import 'summary_text.dart';

/// 컴포넌트 사이 간격 — 디자인이 지정한 유일한 수직 리듬(2026-08-05). `AppSpacing.md`와 같은 값이지만
/// "이 화면의 컴포넌트 간격"이라는 뜻을 이름으로 남긴다.
const double _kComponentGap = AppSpacing.md;
const double _kPhotoHeight = 180;
const double _kLikeIconSize = 24;
const double _kLinkIconSize = 14;
const double _kTagGap = 4;
const double _kTagAddIconSize = 20;

/// 썸네일이 없을 때 그리는 이미지 플레이스홀더 글리프 크기(Figma 40×40, 사진 정중앙).
const double _kPhotoPlaceholderIconSize = 40;

/// 링크 아이콘 ↔ 도메인 텍스트 간격(Figma 6). `AppSpacing` 스케일(4·8·…) 밖이라 상수로 둔다.
const double _kLinkIconGap = 6;

/// AI 요약 문장 사이 간격(2026-08-08, 사용자 확정 6). `AppSpacing` 스케일 밖이라 상수로 둔다.
///
/// 🔴 **줄바꿈만으로는 부족했다.** 문장마다 줄을 바꿔도 `body` 행간(16 × 1.5 = 24)뿐이라, 긴 문장이
/// 여러 줄로 감기면 **"줄이 감긴 것"과 "문장이 바뀐 것"이 눈으로 구분되지 않는다** — 실기기에서
/// 두 번째 문장이 5줄로 감긴 자료가 그대로 그랬다. 6을 더해 문장 경계만 30이 되게 한다.
const double _kSentenceGap = 6;

/// 메모 최대 줄 수 — Figma가 높이를 40으로 고정했고(=`body-small` 14 × 1.43 × 2) 시안 문구 자체가
/// "최대글자 두줄까지 세보고 그걸로 고정"이다.
const int _kMemoMaxLines = 2;

/// S-25-B 항목 상세 — specs/0010-아카이브-탭.md.
/// 좋아요/핀 토글, 폴더 이동, 태그 편집, 삭제가 일어나는 유일한 화면(S-25-A는 표시만).
class ArchiveItemDetailScreen extends StatefulWidget {
  ArchiveItemDetailScreen({
    super.key,
    required this.itemId,
    ArchiveApi? api,
    AuthService? authService,
    RoomSession? roomSession,
    Future<bool> Function(Uri)? openLink,
  }) : api = api ?? ArchiveApi(),
       authService = authService ?? AuthService(),
       roomSession = roomSession ?? appRoomSession,
       openLink = openLink ?? _launchExternally;

  final int itemId;
  final ArchiveApi api;
  final AuthService authService;
  final RoomSession roomSession;

  /// 저장된 링크를 여는 방법. 테스트가 갈아끼우는 이음매다 — `url_launcher`는 플랫폼 채널이라
  /// 위젯 테스트에서 그대로 부를 수 없다(api·authService와 같은 주입 패턴).
  final Future<bool> Function(Uri) openLink;

  static Future<bool> _launchExternally(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  State<ArchiveItemDetailScreen> createState() =>
      _ArchiveItemDetailScreenState();
}

class _ArchiveItemDetailScreenState extends State<ArchiveItemDetailScreen> {
  bool _loading = true;
  String? _errorText;
  String? _actionErrorText;

  /// 「AI 요약 만들기」 진행 중. 서버가 요약+임베딩을 도느라 몇 초 걸리므로 버튼을 잠근다.
  bool _summarizing = false;
  int? _roomId;
  ArchiveItemDetail? _detail;

  /// 화면에 보이는 태그. 서버 저장이 즉시라 "저장 안 된 편집" 상태가 없다 —
  /// 낙관적으로 갈아끼우고 실패하면 되돌린다(2026-08-05, `_commitTags`).
  List<String> _editableTags = [];
  String? _tagErrorText;

  /// 앱바 ⋯ 버튼의 앵커 키 — 옵션창을 그 버튼 아래에 띄운다.
  final GlobalKey _menuAnchorKey = GlobalKey();

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
        _errorText = '자료를 불러오지 못했어요';
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
      final detail = await widget.api.fetchItemDetail(
        idToken,
        roomId,
        widget.itemId,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _detail = detail;
        _editableTags = [...detail.tags];
        _tagErrorText = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorText = '자료를 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  /// 「AI 요약 만들기」 — 사용자가 명시적으로 요청했을 때만 요약을 만든다(2026-08-06).
  ///
  /// 텍스트로 등록한 자료는 자동 요약을 하지 않는다. 짧은 메모는 본문이 곧 요약이라 얻는 것이
  /// 거의 없으면서 기다림만 생기기 때문이다(유저 테스트 피드백).
  ///
  /// 낙관적 갱신을 하지 않는다 — 결과가 서버에서 오는 문장이라 미리 그릴 것이 없다.
  Future<void> _createSummary() async {
    final roomId = _roomId;
    if (roomId == null || _summarizing) return;
    setState(() {
      _actionErrorText = null;
      _summarizing = true;
    });
    try {
      final idToken = await widget.authService.getIdToken();
      final updated = await widget.api.summarizeItem(
        idToken,
        roomId,
        widget.itemId,
      );
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _summarizing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _summarizing = false;
        _actionErrorText = '요약을 만들지 못했어요. 잠시 후 다시 시도해 주세요';
      });
    }
  }

  Future<void> _togglePinned() async {
    final roomId = _roomId;
    final detail = _detail;
    if (roomId == null || detail == null) return;
    final previous = detail;
    final newPinned = !detail.pinned;
    setState(() {
      _actionErrorText = null;
      _detail = detail.copyWith(pinned: newPinned);
    });
    try {
      final idToken = await widget.authService.getIdToken();
      final updated = await widget.api.setItemPinned(
        idToken,
        roomId,
        widget.itemId,
        newPinned,
      );
      if (!mounted) return;
      setState(() => _detail = updated);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _detail = previous;
        _actionErrorText = '핀 고정 변경에 실패했어요';
      });
    }
  }

  Future<void> _toggleLiked() async {
    final roomId = _roomId;
    final detail = _detail;
    if (roomId == null || detail == null) return;
    final previous = detail;
    final newLiked = !detail.likedByMe;
    final newLikeCount = detail.likeCount + (newLiked ? 1 : -1);
    setState(() {
      _actionErrorText = null;
      _detail = detail.copyWith(likedByMe: newLiked, likeCount: newLikeCount);
    });
    try {
      final idToken = await widget.authService.getIdToken();
      final updated = await widget.api.setItemLiked(
        idToken,
        roomId,
        widget.itemId,
        newLiked,
      );
      if (!mounted) return;
      setState(() => _detail = updated);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _detail = previous;
        _actionErrorText = '좋아요 변경에 실패했어요';
      });
    }
  }

  /// 폴더 이동 — ⋯ 메뉴와 같은 옵션창(앵커드 팝오버)으로 폴더를 고른다(2026-08-09 QA —
  /// 기존 바텀시트에서 변경). 현재 폴더는 체크 아이콘으로 표시(선택해도 no-op).
  Future<void> _openMoveFolderMenu() async {
    final roomId = _roomId;
    final detail = _detail;
    if (roomId == null || detail == null) return;
    List<ArchiveFolder> folders;
    try {
      final idToken = await widget.authService.getIdToken();
      folders = await widget.api.fetchFolders(idToken, roomId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionErrorText = '폴더 목록을 불러오지 못했어요');
      return;
    }
    if (!mounted) return;
    final selectedFolderId = await showOptionMenu<int>(
      context: context,
      anchorKey: _menuAnchorKey,
      items: [
        for (final folder in folders)
          OptionMenuItem(
            label: folder.name,
            value: folder.id,
            icon: folder.id == detail.folderId
                ? Icons.check
                : Icons.folder_outlined,
          ),
      ],
    );
    if (selectedFolderId == null || selectedFolderId == detail.folderId) {
      return;
    }
    await _moveToFolder(selectedFolderId);
  }

  Future<void> _moveToFolder(int folderId) async {
    final roomId = _roomId;
    if (roomId == null) return;
    try {
      final idToken = await widget.authService.getIdToken();
      final updated = await widget.api.moveItemToFolder(
        idToken,
        roomId,
        widget.itemId,
        folderId,
      );
      if (!mounted) return;
      setState(() => _detail = updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionErrorText = '폴더 이동에 실패했어요');
    }
  }

  /// 태그 목록을 **즉시** 서버에 반영한다(2026-08-05 사용자 확정 — 예전의 "태그 저장" 버튼
  /// 일괄 저장을 폐기했다. 새 디자인에는 저장 버튼 자리가 없다).
  ///
  /// 좋아요·핀 토글과 같은 idiom: 화면을 먼저 바꾸고 PATCH를 보내고, 실패하면 이전 목록으로
  /// 되돌리고 인라인 안내를 띄운다. API는 목록 전체를 교체하는 단일 PATCH다(0010).
  Future<void> _commitTags(List<String> next) async {
    final roomId = _roomId;
    if (roomId == null) return;
    final previous = _editableTags;
    setState(() {
      _editableTags = next;
      _tagErrorText = null;
    });
    try {
      final idToken = await widget.authService.getIdToken();
      final updated = await widget.api.updateItemTags(
        idToken,
        roomId,
        widget.itemId,
        next,
      );
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _editableTags = [...updated.tags];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _editableTags = previous;
        _tagErrorText = '태그 저장에 실패했어요';
      });
    }
  }

  /// ⑥ 태그 줄의 `+` — 입력 시트를 열고 확정하면 곧바로 [_commitTags].
  /// 20자 제한과 중복 무시는 예전 입력창 로직을 그대로 옮겼다.
  Future<void> _openAddTagSheet() async {
    final tag = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
      isScrollControlled: true, // 키보드가 올라와도 입력창이 가리지 않게.
      builder: (sheetContext) => _AddTagSheet(existingTags: _editableTags),
    );
    if (tag == null || !mounted) return;
    if (_editableTags.contains(tag)) return;
    await _commitTags([..._editableTags, tag]);
  }

  /// 저장된 링크를 외부 브라우저로 연다(S-25-B, 2026-08-05).
  ///
  /// 🔴 **http(s)만 연다.** `url`은 사용자가 공유한 값에서 온다. 서버가 이미 스킴을 검증하지만
  /// (`JsoupUrlCrawler.validateUrl`) 여는 쪽에서도 막는다 — 옛 데이터나 서버 변경으로 다른 스킴이
  /// 들어오면 앱이 `intent:`·`javascript:` 같은 것을 열어주는 통로가 된다.
  ///
  /// 실패는 기존 액션들과 같은 자리(`_actionErrorText`)에 보여준다. 스낵바를 새로 들이지 않는다.
  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null || (scheme != 'http' && scheme != 'https')) {
      setState(() => _actionErrorText = '열 수 없는 주소예요');
      return;
    }
    setState(() => _actionErrorText = null);
    try {
      final opened = await widget.openLink(uri);
      if (!mounted || opened) return;
      setState(() => _actionErrorText = '링크를 열 수 있는 앱이 없어요');
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionErrorText = '링크를 열지 못했어요');
    }
  }

  Future<void> _confirmDelete() async {
    final roomId = _roomId;
    if (roomId == null) return;
    final confirmed = await showActionConfirmDialog(
      context: context,
      title: '이 자료를 삭제할까요?',
      message: '삭제하면 되돌릴 수 없어요.',
      confirmLabel: '삭제',
      confirmColor: AppColors.accentDanger,
    );
    if (confirmed != true) return;
    try {
      final idToken = await widget.authService.getIdToken();
      await widget.api.deleteItem(idToken, roomId, widget.itemId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _actionErrorText = '삭제에 실패했어요');
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    if (_loading || _errorText != null || _roomId == null || detail == null) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: AppBar(),
        body: SafeArea(child: _buildStateBody(context)),
      );
    }
    // 뒤로가기(`<`)는 AppBar 기본 버튼 = 테마의 actionIconTheme이 그려 준다(0003 하위 페이지 규칙).
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        // 제목 없음(2026-08-08 지정) — 뒤로가기 + [핀][⋯]만. 핀은 사진 위에선 잘 안 보여
        // 앱바 ⋯ 왼쪽으로 옮겼다(2026-08-09 QA). 핀과 ⋯ 사이 10px은 디자이너 지정 리터럴.
        actions: [
          _HeroPinButton(pinned: detail.pinned, onTap: _togglePinned),
          const SizedBox(width: 5),
          IconButton(
            key: _menuAnchorKey,
            tooltip: '자료 메뉴',
            onPressed: () => _showItemMenu(detail),
            icon: const Icon(Icons.more_horiz),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(top: false, bottom: false, child: _buildContent(detail)),
      // 하단 반응 바를 스크롤 영역 밖으로 빼 화면 하단에 고정한다(2026-08-08 — 본문 길이에
      // 따라 위치가 흔들리던 걸 고정 위치로 바꿔 달라는 요청). `_buildContent`는 이제 이
      // 부분을 렌더하지 않는다.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          // 20은 디자이너 지정값(간격 스케일 밖이라 리터럴) — 구분선이 화면 하단에서
          // 20px 뜬 위치에 오도록(2026-08-08, 50→35→30→20 순으로 조정).
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.content,
            0,
            AppSpacing.content,
            20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.borderSoft,
              ),
              const SizedBox(height: _kComponentGap),
              _buildBottomBar(detail),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: AppSpacing.cardGap),
            Text('자료를 불러오고 있어요', style: AppTypography.bodySmall),
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

  /// 새 상세 레이아웃(2026-08-05 지정) — 앱바 + 세로 스크롤. **컴포넌트 간격은 전부 12**.
  /// 순서: ①사진(핀만) ②제목 ③메모 ④구분선 ⑤링크 ⑥해시태그 ⑦AI 배너 ⑧본문(=AI 요약).
  /// 예전 "카드 오버레이 히어로"(280px SliverAppBar + 끌어올린 흰 시트)는 폐기했다.
  ///
  /// ⑨구분선+하단 반응 바는 **여기 없다** — 2026-08-08부터 스크롤 밖(`Scaffold.
  /// bottomNavigationBar`)으로 옮겨 화면 하단에 고정된다(`build()` 참고). 본문이 짧든
  /// 길든 위치가 흔들리지 않게 하기 위함. 아래쪽 여백을 넉넉히 둬 마지막 본문이 고정
  /// 바에 가리지 않게 한다.
  Widget _buildContent(ArchiveItemDetail detail) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.content,
        0,
        AppSpacing.content,
        120,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _withGaps([
          // 텍스트 자료(링크·이미지 아님)는 사진 없이 제목·글부터 바로 시작한다(2026-08-09 요청).
          if (!_isTextItem(detail)) _buildPhoto(detail),
          _buildTitle(detail),
          if (_hasMemo(detail)) _buildMemo(detail),
          const Divider(height: 1, thickness: 1, color: AppColors.borderSoft),
          // 텍스트로 등록한 자료엔 URL이 없다. 예전엔 이 줄이 날짜만 싣고 남았지만 날짜가 빠지면서
          // 보여줄 것이 없어졌다 — 빈 줄과 앞뒤 간격 12가 남지 않게 통째로 뺀다.
          if (detail.url != null) _buildLinkLine(detail),
          if (detail.crawlStatus != 'DONE')
            CrawlStatusBadge(status: detail.crawlStatus),
          if (_actionErrorText != null || _tagErrorText != null)
            _buildInlineError(),
          _buildTagsRow(),
          if (detail.summary != null)
            AiHintBanner(
              key: const ValueKey('archive-summary-banner'),
              text: 'MODI가 읽기 좋게 본문을 요약했어요',
            ),
          ..._buildBodyText(detail),
        ]),
      ),
    );
  }

  /// 댓글 시트 열기(2026-08-09) — 작성 성공마다 콜백으로 최신 개수를 받아 하단 바 카운트를
  /// 맞춘다(시트를 드래그로 닫아도 어긋나지 않게 pop 결과 대신 콜백).
  Future<void> _openComments(ArchiveItemDetail detail) async {
    final roomId = _roomId;
    if (roomId == null) return;
    await showArchiveCommentsSheet(
      context,
      api: widget.api,
      authService: widget.authService,
      roomId: roomId,
      itemId: widget.itemId,
      onCountChanged: (count) {
        if (!mounted) return;
        setState(() => _detail = _detail?.copyWith(commentCount: count));
      },
    );
  }

  /// 하단 반응 바(2026-08-08 신설) — 좋아요 + 댓글(2026-08-09) + 등록자 아바타. `build()`의
  /// `bottomNavigationBar`가 이 위젯을 화면 하단에 고정된 자리에 그린다(스크롤 밖).
  Widget _buildBottomBar(ArchiveItemDetail detail) {
    final ArchiveItemCreator? author = detail.createdBy;
    return Row(
      key: const ValueKey('archive-detail-bottom-bar'),
      children: [
        _LikeButton(
          liked: detail.likedByMe,
          count: detail.likeCount,
          onTap: _toggleLiked,
        ),
        const SizedBox(width: AppSpacing.base),
        _CommentButton(
          count: detail.commentCount,
          onTap: () => _openComments(detail),
        ),
        const Spacer(),
        // 등록자가 없으면 자리를 통째로 비운다 — 빈 원을 그리면 "누군가 있는데 이름만 없다"로 읽힌다.
        if (author != null) ArchiveAuthorAvatar(author: author),
      ],
    );
  }

  bool _hasMemo(ArchiveItemDetail detail) =>
      detail.memo != null && detail.memo!.trim().isNotEmpty;

  /// 텍스트 자료 판정 — 링크(url)도 이미지(imageUrl)도 아니면 텍스트다. 이때 상단 사진을 뺀다.
  bool _isTextItem(ArchiveItemDetail detail) =>
      (detail.url == null || detail.url!.trim().isEmpty) &&
      detail.imageUrl == null;

  /// 컴포넌트 사이에 12를 끼운다 — 없는 컴포넌트(메모·배너 등) 자리에 여백이 남지 않게
  /// **렌더되는 것들 사이에만** 넣는다.
  List<Widget> _withGaps(List<Widget> children) {
    final result = <Widget>[];
    for (final child in children) {
      if (result.isNotEmpty) {
        result.add(const SizedBox(height: _kComponentGap));
      }
      result.add(child);
    }
    return result;
  }

  /// ① 사진 — 좌우 여백을 뺀 폭 전체 × 180, `radius.card`. 핀은 사진 위가 아니라 앱바
  /// ⋯ 옆으로 옮겼다(2026-08-09 QA — 이미지 위에선 잘 안 보였다). 썸네일이 없으면
  /// `surface-soft` 면에 이미지 아이콘만 놓는다.
  Widget _buildPhoto(ArchiveItemDetail detail) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: SizedBox(
        height: _kPhotoHeight,
        width: double.infinity,
        // 폴더 직접 업로드 이미지 자료(V26)는 썸네일이 아니라 imageUrl이 사진 원본이다.
        child: _PhotoBackground(thumbnail: detail.imageUrl ?? detail.thumbnail),
      ),
    );
  }

  /// ② 제목 22. 핀 고정 표식은 사진 위 핀 버튼([_HeroPinButton])이 유일하게 맡는다
  /// (2026-08-08 재구성 전엔 제목 줄에도 작은 핀을 겹쳐 보여줬는데, 표식이 두 곳이라 지웠다).
  Widget _buildTitle(ArchiveItemDetail detail) {
    // 제목 20(2026-08-09 QA 축소) — **항상 전체 표시**(2026-08-09 재확정: 말줄임·터치
    // 펼침 없이 몇 줄이든 다 보여준다).
    return Text(
      detail.title,
      style: AppTypography.display.copyWith(fontSize: 20),
    );
  }

  /// ③ 메모 14 / muted — **2줄 고정**(넘치면 말줄임). 메모는 500자까지 쓸 수 있어 제한이 없으면
  /// 요약보다 긴 메모가 화면 절반을 차지한다.
  Widget _buildMemo(ArchiveItemDetail detail) => Text(
    detail.memo!.trim(),
    style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
    maxLines: _kMemoMaxLines,
    overflow: TextOverflow.ellipsis,
  );

  /// ⑤ 링크 — **한 줄 고정**(두 줄로 넘어가지 않게 말줄임).
  ///
  /// **등록 날짜를 더 이상 싣지 않는다**(2026-08-08 확정). 예전에는 `velog.io  |  2026.08.07`처럼
  /// 붙였는데 시안에서 빠졌다 — 날짜는 이 화면에서 아무 동작도 없는 값이었다.
  ///
  /// 링크가 없는 자료(텍스트 등록)는 이 줄 자체가 사라진다 — 빈 줄과 그 위아래 간격 12가
  /// 남지 않도록 호출부에서 통째로 뺀다.
  ///
  /// **탭하면 열린다는 게 안 보인다는 지적**(2026-08-08)에 `muted` 무채색 텍스트를 `primary` 색
  /// + 밑줄 + 끝에 외부링크 화살표로 바꿨다 — 강조색·밑줄·↗ 아이콘 조합은 "이건 링크다"를
  /// 가장 흔하게 신호하는 방식이라 별도 컴포넌트 없이 스타일만 바꿔 재사용한다.
  Widget _buildLinkLine(ArchiveItemDetail detail) {
    final url = detail.url!;
    final linkStyle = AppTypography.bodySmall.copyWith(
      color: AppColors.primary,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.primary,
    );
    return GestureDetector(
      onTap: () => _openUrl(url),
      child: Row(
        children: [
          Image.asset(
            'assets/icons/icon_link.png',
            width: _kLinkIconSize,
            height: _kLinkIconSize,
          ),
          const SizedBox(width: _kLinkIconGap),
          Flexible(
            child: Text(
              shortenLinkLabel(url),
              style: linkStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: _kLinkIconGap),
          const Icon(
            Icons.open_in_new,
            size: _kLinkIconSize,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }

  /// 좋아요·핀·폴더이동·태그 실패 안내 — 실패한 버튼과 같은 화면 위쪽에 둔다.
  Widget _buildInlineError() => Text(
    _actionErrorText ?? _tagErrorText!,
    style: AppTypography.bodySmall.copyWith(color: AppColors.accentDanger),
  );

  /// ⋯ — 공용 옵션창을 **앱바 버튼 아래**에 띄운다(2026-08-05 요청, 바텀시트 폐기).
  Future<void> _showItemMenu(ArchiveItemDetail detail) async {
    final hasMemo = detail.memo != null && detail.memo!.trim().isNotEmpty;
    final action = await showOptionMenu<String>(
      context: context,
      anchorKey: _menuAnchorKey,
      items: [
        OptionMenuItem(
          label: hasMemo ? '메모 편집' : '메모 추가',
          value: 'memo',
          icon: Icons.edit_note,
        ),
        const OptionMenuItem(
          label: '폴더 이동',
          value: 'move',
          icon: Icons.drive_file_move_outline,
        ),
        OptionMenuItem(
          label: detail.pinned ? '핀 해제' : '핀 고정',
          value: 'pin',
          icon: detail.pinned ? Icons.push_pin : Icons.push_pin_outlined,
        ),
        const OptionMenuItem(
          label: '삭제',
          value: 'delete',
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );
    switch (action) {
      case 'memo':
        await _editMemo();
      case 'move':
        await _openMoveFolderMenu();
      case 'pin':
        await _togglePinned();
      case 'delete':
        await _confirmDelete();
    }
  }

  /// 메모 추가/편집(2026-08-06) — 빈 값으로 저장하면 메모를 지운다.
  ///
  /// 다이얼로그가 스스로 제출·로딩·실패를 관리한다(`_ArchiveFolderNameDialog`와 같은 패턴,
  /// 2026-08-06 리뷰 반영 — 예전엔 다이얼로그가 값을 pop하고 곧바로 닫힌 뒤 부모가 네트워크를
  /// 불러 실패하면 입력값이 이미 사라진 채 처음부터 다시 열어야 했다).
  Future<void> _editMemo() async {
    final detail = _detail;
    final roomId = _roomId;
    if (detail == null || roomId == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _TextEditDialog(
        title: (detail.memo != null && detail.memo!.trim().isNotEmpty)
            ? '메모 편집'
            : '메모 추가',
        initialValue: detail.memo ?? '',
        hintText: '메모를 입력해 주세요',
        maxLength: 500,
        maxLines: 4,
        allowEmpty: true,
        failureText: '메모 저장에 실패했어요',
        onSubmit: (value) async {
          final idToken = await widget.authService.getIdToken();
          final updated = await widget.api.updateItemMemo(
            idToken,
            roomId,
            widget.itemId,
            value.isEmpty ? null : value,
          );
          if (!mounted) return;
          setState(() => _detail = updated);
        },
      ),
    );
  }

  /// ⑧ 본문 = **AI 요약문**(2026-08-05 사용자 확정). 크롤링 원문(`bodyText`)은 더 이상
  /// 화면에 싣지 않는다 — 배너가 "요약했어요"라고 말하고 그 아래 요약만 보여준다.
  ///
  /// 요약이 없을 때 `crawlStatus`를 봐야 하는 이유: 예전에는 본문이 없으면 무조건
  /// "자료를 분석하고 있어요"였고, `FAILED`(영원히 안 바뀜)인 항목에도 기다리라고 했다.
  /// 바로 위 [CrawlStatusBadge]의 "분석 실패"와 한 화면에서 모순됐다.
  /// (실제 사례: agoda 같은 SPA 링크는 서버가 받은 HTML에 글자가 0자라 크롤링이 실패한다.)
  ///
  /// 실패 문구가 재시도를 암시하지 않는 이유: **재크롤링** 수단이 없다(링크를 탭해 브라우저로
  /// 여는 건 원문을 보는 것일 뿐 본문을 다시 가져오는 게 아니다). 재크롤링은 `specs/0014`가
  /// 범위 밖으로 못 박았다 — 없는 기능을 가리키지 않는다.
  ///
  /// **안내 문구는 본문과 다른 스타일**(`design.md` §7 — `body-small`/`muted`)이라야 한다.
  /// 같은 스타일이면 "링크 내용을 가져오지 못했어요"가 그 링크의 첫 문장인지 시스템 안내인지
  /// 구분되지 않는다.
  ///
  /// `DONE`인데 요약이 없으면 문구를 지어내지 않고 영역을 통째로 비운다(간격도 안 생긴다).
  List<Widget> _buildBodyText(ArchiveItemDetail detail) {
    final summary = detail.summary;
    // 빈 문자열은 "요약 없음"과 같게 다룬다 — 서버가 `""`를 주면(앱은 널로 바꾸지 않는다)
    // 빈 Column 하나가 배너 아래에 남아 12 간격만 생긴다.
    if (summary != null && splitSummarySentences(summary).isNotEmpty) {
      // Figma가 본문을 `body`(16/150) + **`foreground-soft`**로 지정했다 — `body` 토큰의 기본색은
      // `foreground`(#222)라 여기서 한 단계 옅게 덮는다. 긴 요약이 제목만큼 진하면 무겁다.
      //
      // 🔴 **문장마다 줄을 바꿔 그린다**(2026-08-08). 4~6문장이 한 덩어리로 붙어 나와 읽기
      // 어렵다는 QA가 있었다. 서버 프롬프트에서 `\n`을 받는 방법을 먼저 재봤으나 모델이
      // 7~8/15건만 지켰다(`ai/docs/EXPERIMENTS.md` #33) — 그래서 저장값을 그대로 두고 여기서
      // 나눈다. 근거와 실제 데이터의 함정은 `summary_text.dart` 참고.
      //
      // 문장마다 별도 `Text`인 이유는 `_kSentenceGap`(6)을 정확히 주기 위해서다 — 한 `Text`에
      // `\n`을 넣으면 간격이 행간(24)으로 고정돼 감긴 줄과 구분되지 않는다.
      return [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: _kSentenceGap,
          children: [
            for (final sentence in splitSummarySentences(summary))
              Text(
                sentence,
                style: AppTypography.body.copyWith(
                  color: AppColors.foregroundSoft,
                ),
              ),
          ],
        ),
      ];
    }
    final placeholder = switch (detail.crawlStatus) {
      'PENDING' => '자료를 분석하고 있어요. 잠시 후 다시 확인해 주세요.',
      'FAILED' => '링크 내용을 가져오지 못했어요. 링크만 저장돼 있어요.',
      _ => null,
    };
    if (placeholder == null) {
      // 🔴 분석은 끝났는데 요약이 없는 자료 — 여기가 「AI 요약 만들기」 자리다(2026-08-06).
      // 텍스트로 등록한 자료가 이 상태로 들어오고(자동 요약을 하지 않는다), 요약이 실패했던
      // 링크 자료도 같은 버튼으로 되살릴 수 있다.
      final body = detail.bodyText;
      if (body != null && body.trim().isNotEmpty) {
        return [_buildSummaryButton()];
      }
      return const [];
    }
    return [
      Text(
        placeholder,
        style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
      ),
    ];
  }

  /// 「AI 요약 만들기」 버튼 — 분석은 끝났는데 요약이 없는 자료에만 보인다.
  ///
  /// 🔴 <b>왜 버튼인가</b>(2026-08-06 사용자 확정): 텍스트로 등록한 자료는 자동 요약을 하지 않는다.
  /// 직접 적은 짧은 메모는 본문이 곧 요약이라 얻는 것이 거의 없으면서 기다림만 생겼다
  /// (유저 테스트: "AI 응답 기다리는 시간이 아쉽다").
  ///
  /// 강조색을 쓰지 않는다 — 이 화면의 primary 는 좋아요·태그 쪽이고, 요약은 <b>원하면 하는</b>
  /// 보조 동작이다(design.md §1 "화면당 강조색은 하나").
  Widget _buildSummaryButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const ValueKey('archive-create-summary-button'),
        onPressed: _summarizing ? null : _createSummary,
        icon: _summarizing
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.auto_awesome, size: 16),
        label: Text(_summarizing ? '요약을 만들고 있어요…' : 'AI 요약 만들기'),
      ),
    );
  }

  /// ⑥ 해시태그 줄 — 높이 20 칩들을 4 간격으로 흘리고, 마지막에 추가(+) 버튼.
  /// 저장 버튼은 없다. 칩의 X와 + 시트 확정이 **곧바로** 서버에 반영된다.
  Widget _buildTagsRow() {
    return Wrap(
      spacing: _kTagGap,
      runSpacing: _kTagGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final tag in _editableTags)
          ArchiveTagChip(
            key: ValueKey('archive-item-tag-$tag'),
            label: tag,
            onDeleted: () =>
                _commitTags(_editableTags.where((t) => t != tag).toList()),
          ),
        GestureDetector(
          key: const ValueKey('archive-item-tag-add'),
          onTap: _openAddTagSheet,
          child: Image.asset(
            'assets/icons/icon_tag_add.png',
            width: _kTagAddIconSize,
            height: _kTagAddIconSize,
          ),
        ),
      ],
    );
  }
}

/// ① 사진 배경.
///
/// **썸네일이 없으면 `surface-soft` 면에 이미지 아이콘만 놓는다**(2026-08-08 Figma). 예전 폴백이던
/// primary 빨강 그라데이션은 폐기했다 — 사진이 없는 자료가 대부분인데 화면 상단 180px가 매번
/// 강조색으로 채워져, 정작 강조해야 할 곳(좋아요·태그)과 경쟁했다.
///
/// 썸네일이 **실제로 그려졌을 때만** 검정 스크림을 덮는다. 위아래 양쪽인 이유는 좋아요가 상단,
/// 등록자가 하단에 얹히기 때문이다(예전엔 좋아요가 하단뿐이라 아래에서만 올라왔다).
/// design.md §이미지 위 텍스트 오버레이 예외(홈 히어로/아카이브 카드와 같은 계열).
class _PhotoBackground extends StatelessWidget {
  const _PhotoBackground({required this.thumbnail});

  final String? thumbnail;

  /// 사진 위 흰 아이콘이 밝은 사진에서도 읽히게 하는 스크림. 위아래 각 40% → 가운데 0%.
  static const _scrim = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x66000000), Color(0x00000000), Color(0x66000000)],
        stops: [0, 0.5, 1],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (thumbnail == null || thumbnail!.isEmpty) {
      return const _PhotoPlaceholder();
    }
    // 스크림을 `loadingBuilder`의 완료 분기 안에 두는 것이 핵심이다 — 바깥 Stack에 두면 로딩 실패로
    // 플레이스홀더가 나온 회색 면까지 어두워진다. `progress == null`이 곧 "다 그려졌다"다.
    return Image.network(
      thumbnail!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _PhotoPlaceholder(),
      loadingBuilder: (context, child, progress) => progress == null
          ? Stack(fit: StackFit.expand, children: [child, _scrim])
          : const _PhotoPlaceholder(),
    );
  }
}

/// 썸네일이 없을 때의 사진 자리 — `surface-soft` 면 + 정중앙 이미지 아이콘 40 (`muted-soft`).
///
/// Figma는 굵기 3.33 라운드캡의 선 아이콘인데, 디자이너 PNG가 아직 없어 Material 아웃라인
/// 아이콘으로 근사한다. 에셋을 받으면 `Image.asset`으로 바꾼다(`specs/OPEN.md`).
class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceSoft,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: _kPhotoPlaceholderIconSize,
          color: AppColors.mutedSoft,
        ),
      ),
    );
  }
}

/// 앱바 ⋯ 왼쪽 핀 토글(2026-08-09 QA — 사진 위에서 앱바로 이동). 아이콘 에셋은
/// `archive_folder_items_screen.dart`의 `_PinButton`과 같다(24×24, 미고정
/// `majesticons_pin-line.svg`, 고정 `primary_pin.svg`/`primary`). 단 **미고정 색은
/// 앱바 ⋯ 아이콘과 맞춰 `foreground`(#222)** — 폴더 카드 핀(`border-strong` #C1C1C1)과
/// 여기만 다르다(앱바에선 ⋯와 나란히 있어 톤을 통일해야 자연스럽다).
class _HeroPinButton extends StatelessWidget {
  const _HeroPinButton({required this.pinned, required this.onTap});

  final bool pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: pinned ? '핀 해제' : '핀 고정',
      child: GestureDetector(
        key: ValueKey('archive-detail-pin-${pinned ? 'on' : 'off'}'),
        onTap: onTap,
        child: SvgPicture.asset(
          pinned
              ? 'assets/icons/primary_pin.svg'
              : 'assets/icons/majesticons_pin-line.svg',
          width: 24,
          height: 24,
          // 미고정 핀은 앱바 ⋯ 아이콘과 같은 색(`foreground` #222)으로 맞춘다(2026-08-09 QA).
          // 고정 상태는 그대로 핑크(primary)로 "켜짐"을 나타낸다.
          colorFilter: ColorFilter.mode(
            pinned ? AppColors.primary : AppColors.foreground,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}

/// 하단 반응 바의 좋아요 — 아이콘 24 + 카운트가 가로로 나란히 온다(2026-08-08, 사진 위 세로
/// 스택 오버레이에서 하단 바 가로 배치로 옮겨오며 레이아웃도 바꿨다). 흰 배경 위라 배경별
/// 색 분기가 필요 없어졌다 — 아이돌 색은 항상 `muted`.
///
/// 좋아요를 누른 상태는 `primary`다(강조색이 곧 "눌렀다"는 신호다).
///
/// 🔴 <b>`muted-soft`가 아니라 `muted`인 이유.</b> Figma는 카운트 채우기를 `muted`로 지정했는데 처음엔 하트 색(시안이
/// iOS 시스템 색 `Grey/Medium`을 물고 있어 프로젝트 토큰이 아니었다)에 묶어 둘 다 `muted-soft`로 넣었다. 그건 시안과
/// 다를뿐더러 design.md §접근성이 **`muted-soft`(#929292)를 비활성 텍스트에만** 쓰라고 못 박은 것을 어긴다 —
/// `muted`(#6A6A6A)가 흰 배경에서 대비가 더 넉넉하다. 하트도 같은 이유로 `muted`를 쓴다 — 누를 수 있는
/// 컨트롤이라 장식용 플레이스홀더 아이콘과 다르다.
class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.liked,
    required this.count,
    required this.onTap,
  });

  final bool liked;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: liked ? '좋아요 취소' : '좋아요',
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: _kLikeIconSize,
              color: liked ? AppColors.primary : AppColors.muted,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '$count',
              style: AppTypography.badge.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// 하단 반응 바의 댓글 버튼(2026-08-09) — [_LikeButton]과 같은 규격(아이콘 24 + 카운트
/// `badge`/`muted`). 탭하면 댓글 시트가 열린다.
class _CommentButton extends StatelessWidget {
  const _CommentButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '댓글 $count개 보기',
      child: GestureDetector(
        key: const ValueKey('archive-detail-comments'),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: _kLikeIconSize,
              color: AppColors.muted,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '$count',
              style: AppTypography.badge.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// 태그 추가 입력 시트 — 확정하면 태그 문자열을 pop해 돌려준다(빈 값이면 null).
/// 화면에 저장 버튼이 없어진 대신 여기의 "추가"가 곧 저장이다.
class _AddTagSheet extends StatefulWidget {
  const _AddTagSheet({required this.existingTags});

  final List<String> existingTags;

  @override
  State<_AddTagSheet> createState() => _AddTagSheetState();
}

class _AddTagSheetState extends State<_AddTagSheet> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final tag = _controller.text.trim();
    if (tag.isEmpty) return;
    if (tag.length > 20) {
      setState(() => _errorText = '태그는 20자 이내로 입력해 주세요');
      return;
    }
    if (widget.existingTags.contains(tag)) {
      setState(() => _errorText = '이미 있는 태그예요');
      return;
    }
    Navigator.of(context).pop(tag);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.content,
        right: AppSpacing.content,
        top: AppSpacing.content,
        // 키보드 높이만큼 밀어 올린다.
        bottom: AppSpacing.content + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('태그 추가', style: AppTypography.title),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('archive-item-tag-input'),
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '태그 이름',
              errorText: _errorText,
            ),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(
            key: const ValueKey('archive-item-tag-submit'),
            onPressed: _submit,
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }
}

/// 메모/링크 편집에 함께 쓰는 텍스트 입력 다이얼로그(2026-08-06, `_ArchiveFolderNameDialog`와 같은
/// 자기완결형 패턴 — 2026-08-06 리뷰 반영).
///
/// **다이얼로그가 스스로 제출·로딩·실패를 관리한다.** 예전엔 값을 pop해 곧바로 닫힌 뒤 부모가
/// 네트워크를 불러 실패하면, 이미 사라진 입력값을 사용자가 처음부터 다시 타이핑해야 했다. 이제는
/// [onSubmit]이 실패(예외)하면 다이얼로그가 열린 채로 인라인 에러만 보여주고 입력값을 그대로
/// 유지한다 — 성공([onSubmit]이 정상 반환)해야만 닫힌다.
class _TextEditDialog extends StatefulWidget {
  const _TextEditDialog({
    required this.title,
    required this.initialValue,
    required this.hintText,
    required this.onSubmit,
    this.maxLength,
    this.maxLines = 1,
    this.allowEmpty = false,
    this.failureText = '저장하지 못했어요. 다시 시도해 주세요',
  });

  final String title;
  final String initialValue;
  final String hintText;

  /// 실제 저장(네트워크 호출)을 한다. 예외를 던지면 다이얼로그가 [failureText]를 보여주고 열린
  /// 채로 남는다 — 재시도 시 입력값이 그대로 있다.
  final Future<void> Function(String value) onSubmit;
  final int? maxLength;
  final int maxLines;

  /// true면 빈 값 제출을 허용한다(메모 지우기처럼 "빈 값"이 유효한 의도일 때).
  /// false(기본)면 빈 값 제출 시 안내만 보여주고 [onSubmit]을 부르지 않는다.
  final bool allowEmpty;
  final String failureText;

  @override
  State<_TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<_TextEditDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);
  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final value = _controller.text.trim();
    if (value.isEmpty && !widget.allowEmpty) {
      setState(() => _errorText = '값을 입력해 주세요');
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await widget.onSubmit(value);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = widget.failureText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 폴더 추가 팝업(`_ArchiveFolderNameDialog`)과 같은 디자인(2026-08-09 QA) — surface 카드 +
    // 중앙 제목 + [취소 | 저장] AppDialogButton. 메모는 여러 줄이라 입력은 박스형·멀티라인.
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
      child: SizedBox(
        width: 318,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: AppTypography.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_loading,
                maxLength: widget.maxLength,
                maxLines: widget.maxLines,
                minLines: widget.maxLines,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.foreground,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.hintText,
                  hintStyle: AppTypography.bodySmall.copyWith(
                    color: AppColors.mutedSoft,
                  ),
                  counterText: '',
                  contentPadding: const EdgeInsets.all(AppSpacing.sm),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    borderSide: const BorderSide(color: AppColors.borderStrong),
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
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: AppDialogButton(
                        label: '취소',
                        background: AppColors.surfaceStrong,
                        foreground: AppColors.foreground,
                        onPressed: _loading
                            ? () {}
                            : () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: AppDialogButton(
                        label: '저장',
                        background: AppColors.primary,
                        foreground: AppColors.onPrimary,
                        onPressed: _submit,
                      ),
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
