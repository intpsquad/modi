import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../design/empty_state.dart';
import '../../design/line_tabs.dart';
import '../../design/option_menu.dart';
import '../../design/tokens.dart';
import '../auth/auth_service.dart';
import '../room/room_session.dart';
import 'archive_api.dart';
import 'archive_item_register_sheet.dart';
import 'archive_widgets.dart';

enum _SortMode { latest, likes }

/// 폴더 내부 상단 라인 탭 — 링크(url 있는 자료) / 텍스트(url 없는 메모형 자료) / 이미지(준비 중).
/// 순서(링크·텍스트·이미지)는 2026-08-08 디자이너 지정.
enum _ArchiveTab { link, text, image }

/// S-25-A 폴더 내 항목 목록 — specs/0010-아카이브-탭.md.
/// 읽기 전용(좋아요/핀 토글은 S-25-B). 검색·정렬은 서버가 아니라 이 화면에서 클라이언트로 처리하고,
/// 검색 대상은 페이로드를 가볍게 유지하기 위해 title/tags로 좁힌다(0010 참고).
class ArchiveFolderItemsScreen extends StatefulWidget {
  ArchiveFolderItemsScreen({
    super.key,
    required this.folderId,
    ArchiveApi? api,
    AuthService? authService,
    RoomSession? roomSession,
  }) : api = api ?? ArchiveApi(),
       authService = authService ?? AuthService(),
       roomSession = roomSession ?? appRoomSession;

  final int folderId;
  final ArchiveApi api;
  final AuthService authService;
  final RoomSession roomSession;

  @override
  State<ArchiveFolderItemsScreen> createState() =>
      _ArchiveFolderItemsScreenState();
}

class _ArchiveFolderItemsScreenState extends State<ArchiveFolderItemsScreen> {
  bool _loading = true;

  /// 한 번이라도 목록을 그린 뒤인가 — 그 뒤로는 재조회에 전체 스피너를 쓰지 않는다
  /// (다른 네 화면과 같은 패턴). 2026-08-05 신고: 자료를 등록하면 목록이 스피너로
  /// 갈아끼워져 깜박였다.
  bool _loadedOnce = false;
  String? _errorText;
  int? _roomId;
  String? _folderName;
  List<ArchiveItem> _items = [];

  /// 이미지 탭 피드 — 방의 투두 첨부 사진(폴더 무관, 2026-08-09 기획). 서버 미구현 동안엔
  /// `fetchTodoImages`가 빈 목록을 돌려줘 기존 "준비 중" 빈 상태가 그대로 보인다.
  List<ArchiveTodoImage> _images = [];
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.latest;
  _ArchiveTab _tab = _ArchiveTab.link;

  /// 링크/텍스트/이미지 탭을 좌우 스와이프로도 넘기기 위한 컨트롤러(2026-08-09 QA).
  /// 라인 탭 탭 → animateToPage, 스와이프 → onPageChanged가 `_tab`을 갱신한다.
  late final PageController _pageController = PageController(
    initialPage: _tab.index,
  );

  /// 상단바 검색 아이콘으로 여닫는 인라인 검색창(2026-08-08 디자인 — 검색은 상단바 액션).
  bool _searchOpen = false;

  /// ＋ 버튼 아래에 옵션창(링크/텍스트/이미지 추가)을 띄우는 앵커. 버튼 자체의
  /// `ValueKey('archive-register-button')`는 테스트가 이미 쓰고 있어 그대로 두고,
  /// `KeyedSubtree`로 감싸 이 키를 따로 붙인다(레이아웃에 영향 없음).
  final GlobalKey _addMenuAnchorKey = GlobalKey();

  // 방 전환 등으로 조회가 겹쳐 호출될 때 먼저 시작한 요청이 나중 요청 결과를 덮어쓰지 않도록 막는 가드.
  int _loadGeneration = 0;

  /// [tab]에 해당하는 자료(검색·정렬 전). 링크=url 있음, 텍스트=url 없음(메모형 등록).
  /// 이미지 탭은 이 목록을 쓰지 않는다(데이터 없어 준비 중 빈 상태).
  /// 세 탭이 PageView로 동시에 존재하므로 `_tab`이 아니라 인자로 받은 탭 기준으로 거른다.
  List<ArchiveItem> _tabItemsFor(_ArchiveTab tab) {
    bool hasUrl(ArchiveItem i) => i.url != null && i.url!.trim().isNotEmpty;
    // 이미지 자료(V26)는 링크/텍스트 어느 탭에도 새지 않는다 — 이미지 탭에서만 다룬다.
    return tab == _ArchiveTab.text
        ? _items.where((i) => !hasUrl(i) && i.imageUrl == null).toList()
        : _items.where(hasUrl).toList();
  }

  /// 이 폴더에 직접 업로드한 이미지 자료(V26) — 핀 우선 + 최신순(다른 탭과 같은 규칙).
  List<ArchiveItem> get _folderImageItems {
    final items = _items.where((i) => i.imageUrl != null).toList();
    final pinned = items.where((i) => i.pinned).toList();
    final unpinned = items.where((i) => !i.pinned).toList();
    return [...pinned, ...unpinned];
  }

  List<ArchiveItem> _filteredSortedItemsFor(_ArchiveTab tab) {
    final query = _searchQuery.trim().toLowerCase();
    final tabItems = _tabItemsFor(tab);
    var items = query.isEmpty
        ? tabItems
        : tabItems
              .where(
                (item) =>
                    item.title.toLowerCase().contains(query) ||
                    item.tags.any((tag) => tag.toLowerCase().contains(query)),
              )
              .toList();
    // 핀 고정 항목은 정렬 기준과 무관하게 항상 최상단. 서버도 이미
    // pinned desc로 내려주지만, "좋아요순"이 likeCount만으로 재정렬하면 그 우선순위가
    // 깨진다. 그룹을 나눠 각자 정렬한 뒤 이어붙인다 — List.sort는 안정 정렬이 아니라서
    // 동순위 비교자(최신순)만으로는 원래 순서 보존을 보장할 수 없다.
    final pinned = items.where((item) => item.pinned).toList();
    final unpinned = items.where((item) => !item.pinned).toList();
    if (_sortMode == _SortMode.likes) {
      pinned.sort((a, b) => b.likeCount.compareTo(a.likeCount));
      unpinned.sort((a, b) => b.likeCount.compareTo(a.likeCount));
    }
    return [...pinned, ...unpinned];
  }

  /// 크롤링 실패(`FAILED`) 시 서버가 `title`에 원본 URL을 그대로 남겨둔다(등록 시점 임시값이
  /// 영영 안 바뀌는 경우 — `ArchiveItemService.registerItem` 주석 참고). 이 상태를 판별해
  /// 카드에서 URL 대신 짧은 안내 문구로 대체한다. `PENDING`은 곧 실제 제목으로 바뀔 예정이라
  /// 제외한다(URL이 잠깐 보여도 무방, 2026-08-08 확정).
  ///
  /// `title == url` 완전 일치가 아니라 **URL로 시작하는지**만 본다 — `title` 컬럼은 255자에서
  /// 잘리는데 `url`은 2048자까지 허용돼(`ArchiveTextLimits`), 255자 넘는 URL은 잘린 title이
  /// 원본 url과 더 이상 정확히 같지 않다. 실제 페이지 제목이 "http(s)://"로 시작하는 경우는
  /// 사실상 없으므로 이 판정이 더 안전하다.
  static bool _isUnresolvedFailedTitle(ArchiveItem item) {
    if (item.crawlStatus != 'FAILED') return false;
    final title = item.title.trim();
    return title.startsWith('http://') || title.startsWith('https://');
  }

  /// URL에서 도메인만 추출해 카드 출처로 쓴다(예: https://velog.io/@x/... → velog.io).
  /// 실패하거나 url이 없으면 서버 `source`로 폴백한다.
  String? _domain(ArchiveItem item) {
    final url = item.url;
    if (url != null && url.trim().isNotEmpty) {
      final host = Uri.tryParse(url.trim())?.host;
      if (host != null && host.isNotEmpty) {
        return host.startsWith('www.') ? host.substring(4) : host;
      }
    }
    return item.source;
  }

  /// 목록 카드의 핀 토글 — 낙관적 반영 후 서버(`setItemPinned`), 실패 시 롤백.
  /// (상세 화면과 같은 동작을 목록에도 배선, 2026-08-08.)
  Future<void> _togglePin(ArchiveItem item) async {
    final roomId = _roomId;
    if (roomId == null) return;
    final next = !item.pinned;
    setState(() {
      _items = [
        for (final it in _items)
          if (it.id == item.id) it.copyWith(pinned: next) else it,
      ];
    });
    try {
      final idToken = await widget.authService.getIdToken();
      await widget.api.setItemPinned(idToken, roomId, item.id, next);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = [
          for (final it in _items)
            if (it.id == item.id) it.copyWith(pinned: item.pinned) else it,
        ];
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('고정 상태를 바꾸지 못했어요')));
    }
  }

  @override
  void initState() {
    super.initState();
    widget.roomSession.addListener(_onRoomSessionChanged);
    _load();
  }

  @override
  void dispose() {
    widget.roomSession.removeListener(_onRoomSessionChanged);
    _pageController.dispose();
    super.dispose();
  }

  /// 라인 탭 선택 → 해당 페이지로 애니메이션(인디케이터는 즉시 반영, 페이지는 미끄러진다).
  void _goToTab(_ArchiveTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
    _pageController.animateToPage(
      tab.index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
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
      await _fetchItems();
      // 이미지 피드는 링크/텍스트와 별도 소스 — 실패해도 본 목록을 막지 않게 뒤에서 조용히.
      await _fetchImages();
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorText = '항목 목록을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  /// 이미지 탭 피드 갱신 — 조용히(스피너 없이). 서버 미구현이면 빈 목록이 온다(모델 주석 참고).
  Future<void> _fetchImages() async {
    final roomId = _roomId;
    if (roomId == null) return;
    try {
      final idToken = await widget.authService.getIdToken();
      final images = await widget.api.fetchTodoImages(idToken, roomId);
      if (!mounted) return;
      setState(() => _images = images);
    } catch (_) {
      // 이미지 피드 실패는 본 목록과 무관 — 기존 값을 유지하고 조용히 넘어간다.
    }
  }

  /// 이미지 핀 토글 — 목록 카드 핀과 같은 낙관적 반영 + 실패 롤백.
  Future<void> _toggleImagePin(ArchiveTodoImage image) async {
    final roomId = _roomId;
    if (roomId == null) return;
    final next = !image.pinned;
    setState(() {
      _images = [
        for (final it in _images)
          if (it.id == image.id) it.copyWith(pinned: next) else it,
      ];
    });
    try {
      final idToken = await widget.authService.getIdToken();
      await widget.api.setTodoImagePinned(idToken, roomId, image.id, next);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _images = [
          for (final it in _images)
            if (it.id == image.id) it.copyWith(pinned: image.pinned) else it,
        ];
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('고정 상태를 바꾸지 못했어요')));
    }
  }

  /// [silent]이면 전체 스피너 없이 조용히 갱신한다 — 기존 목록을 그대로 두고 결과가 오면
  /// 그것만 갈아끼운다(등록 후 재조회·당겨서 새로고침).
  Future<void> _fetchItems({bool silent = false}) async {
    final roomId = _roomId;
    if (roomId == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      if (!silent && !_loadedOnce) _loading = true;
      _errorText = null;
    });
    try {
      final idToken = await widget.authService.getIdToken();
      final result = await widget.api.fetchFolderItems(
        idToken,
        roomId,
        widget.folderId,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _folderName = result.folderName;
        _items = result.items;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorText = '항목 목록을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  /// ＋ 버튼 → 옵션창(2026-08-08 지정) — 바로 등록 시트를 열지 않고 [링크 추가/텍스트
  /// 추가/이미지 추가] 중 고르게 한다. 이 화면 상세(`archive_item_detail_screen.dart`
  /// `_showItemMenu`)가 쓰는 것과 같은 공용 컴포넌트(`showOptionMenu`).
  Future<void> _showAddMenu() async {
    final selected = await showOptionMenu<String>(
      context: context,
      anchorKey: _addMenuAnchorKey,
      items: const [
        OptionMenuItem(label: '링크 추가', value: 'link'),
        OptionMenuItem(label: '텍스트 추가', value: 'text'),
        OptionMenuItem(label: '이미지 추가', value: 'image'),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'link':
        await _openRegisterSheet(ArchiveRegisterMode.link);
      case 'text':
        await _openRegisterSheet(ArchiveRegisterMode.text);
      case 'image':
        // 폴더 직접 업로드 이미지(V26, 2026-08-09 후속 확정) — 투두 첨부 이미지 피드와는 별개
        // 경로다. 등록시트가 사진 선택·업로드까지 맡는다.
        await _openRegisterSheet(ArchiveRegisterMode.image);
    }
  }

  Future<void> _openRegisterSheet(ArchiveRegisterMode mode) async {
    final roomId = _roomId;
    if (roomId == null) return;
    List<ArchiveFolder> folders;
    try {
      final idToken = await widget.authService.getIdToken();
      folders = await widget.api.fetchFolders(idToken, roomId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = '폴더 목록을 불러오지 못했어요');
      return;
    }
    if (!mounted) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
      isScrollControlled: true,
      builder: (context) => ArchiveItemRegisterSheet(
        folders: folders,
        initialFolderId: widget.folderId,
        initialMode: mode,
        onSubmit:
            ({required folderId, url, text, memo, imageUrl, title}) async {
              final idToken = await widget.authService.getIdToken();
              await widget.api.createItem(
                idToken,
                roomId,
                folderId,
                url: url,
                text: text,
                memo: memo,
                imageUrl: imageUrl,
                title: title,
              );
            },
        uploadImage: (bytes) async {
          final idToken = await widget.authService.getIdToken();
          return widget.api.uploadArchiveImage(idToken, roomId, bytes: bytes);
        },
      ),
    );
    // 바깥 탭으로 닫았으면(null) 아무 일도 하지 않는다 — 조회가 헛돌고 실패하면 에러까지
    // 떴다(2026-08-05 신고). 등록했을 때만, 그것도 **조용히** 다시 부른다.
    if (created != true) return;
    await _fetchItems(silent: true);
    // 🔴 **등록 성공을 따로 알리지 않는다 — 스낵바를 다시 넣지 말 것**(2026-08-06).
    //
    // 시트가 닫히는 것 자체가 성공 신호다: 실패하면 시트는 안 닫히고 그 자리에
    // "등록하지 못했어요"를 띄운다(ArchiveItemRegisterSheet). 게다가 바로 위에서 목록을
    // 다시 부르므로 **방금 넣은 자료가 화면에 나타난다** — 링크는 「분석 중」 배지로,
    // 텍스트는 완성된 채로.
    //
    // 원래 스낵바를 넣은 이유는 "등록이 비동기가 되면서 화면이 곧바로 조용해진다"였는데,
    // 배지·배너·즉시완료가 들어오면서 그 전제가 없어졌다. 화면이 이미 하는 말을 한 번 더
    // 하는 것이라 지운다.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        // 뒤로가기 아이콘과 폴더명을 가깝게 붙인다(요청).
        titleSpacing: 0,
        // 검색이 열리면 폴더명·검색·＋ 아이콘 전부를 검색바 하나로 갈아끼운다(2026-08-08
        // 디자이너 지정 — 아이콘 토글로 아래에 별도 줄을 여는 대신 상단바 자체가 바뀐다).
        // `title`은 leading(뒤로가기)과 actions 사이 남는 폭을 그대로 받으므로, 검색바를
        // 여기 꽂으면 별도 오프셋 계산 없이 바로 이어 붙는다.
        title: _searchOpen
            ? _buildSearchAppBarField()
            : Text(_folderName ?? '폴더'),
        // 검색·＋ 두 아이콘을 서로 가깝게(패딩 없음) — 디자이너 SVG
        // (`assets/icons/search.svg`, `plus.svg`) 사용.
        //
        // M3 IconButton은 `padding`을 0으로 줘도 접근성 최소 탭 영역(48×48,
        // `tapTargetSize`)만큼 보이지 않는 여백을 얹는다 — 버튼 박스끼리는 붙어도 그 안의
        // 18px/16px 아이콘이 48px 박스 한가운데 있어 아이콘 사이가 넓어 보인다. `style`로
        // `tapTargetSize: shrinkWrap`을 줘야 실제로 붙는다(2026-08-08 실측 확인).
        actions: _searchOpen
            ? const []
            : [
                IconButton(
                  key: const ValueKey('archive-search-toggle'),
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => setState(() => _searchOpen = true),
                  icon: SvgPicture.asset(
                    'assets/icons/search.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(
                      AppColors.foreground,
                      BlendMode.srcIn,
                    ),
                  ),
                  tooltip: '검색',
                ),
                // 10px는 design.md 간격 스케일(8=sm·12=md)에 없는 값 — 디자이너가 이 자리에만
                // 준 지정값이라 토큰화하지 않고 리터럴로 둔다(2026-08-08).
                const SizedBox(width: 10),
                KeyedSubtree(
                  key: _addMenuAnchorKey,
                  child: IconButton(
                    key: const ValueKey('archive-register-button'),
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _showAddMenu,
                    icon: SvgPicture.asset(
                      'assets/icons/plus.svg',
                      width: 16,
                      height: 16,
                      colorFilter: const ColorFilter.mode(
                        AppColors.foreground,
                        BlendMode.srcIn,
                      ),
                    ),
                    tooltip: '자료 추가',
                  ),
                ),
                const SizedBox(width: AppSpacing.content),
              ],
      ),
      // 검색바 밖(본문 아무 곳)을 탭하면 검색이 닫힌다(2026-08-08). `Listener`는 제스처
      // 아레나에 참여하지 않는 순수 관찰자라 카드·탭·정렬 드롭다운 등 하위 위젯의 탭 동작을
      // 가로막지 않는다 — 검색바 자체는 상단바(`title`) 쪽이라 이 영역 밖이라 안전하다.
      body: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          if (!_searchOpen) return;
          setState(() {
            _searchOpen = false;
            _searchQuery = '';
          });
        },
        child: SafeArea(child: _buildBody(context)),
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
                onPressed: () => _fetchItems(),
                child: const Text('다시 시도'),
              ),
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

    // 탭은 스크롤과 무관하게 상단 고정, 그 아래 탭별 콘텐츠는 좌우 스와이프로도 넘긴다
    // (2026-08-09 QA). 세 페이지가 동시에 존재하므로 각 페이지는 자기 탭 기준으로 렌더한다.
    // 검색창은 이 아래 별도 줄이 아니라 상단바 자체(위 `title`)로 옮겨 갔다.
    return Column(
      children: [
        LineTabs.underlineTrack(
          tabs: const ['링크', '텍스트', '이미지'],
          selectedIndex: _tab.index,
          onChanged: (i) => _goToTab(_ArchiveTab.values[i]),
        ),
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _tab = _ArchiveTab.values[i]),
            children: [
              // 링크·텍스트는 같은 목록 렌더(자료 종류만 다름), 이미지는 준비 중 빈 상태.
              _buildItemsTab(_ArchiveTab.link),
              _buildItemsTab(_ArchiveTab.text),
              _buildImageTab(),
            ],
          ),
        ),
      ],
    );
  }

  /// '이미지' 탭 — 두 소스를 섹션으로 나눠 보여준다: ① 이 폴더에 직접 업로드한 사진(V26,
  /// 2026-08-09 후속 확정, 폴더 스코프) ② 투두에 첨부한 사진(2026-08-09 기획, 방 전체 피드,
  /// 폴더 무관). 스코프가 서로 달라 하나로 합쳐 정렬하지 않고 섹션을 분리한다.
  /// 2열 그리드: 사진(정사각) + 우상단 핀 + (투두 사진만) 우하단 담당자 아바타 + 아래 제목.
  Widget _buildImageTab() {
    final folderImages = _folderImageItems;
    // 핀 고정이 항상 최상단, 그 안에서는 최신순(다른 탭과 같은 규칙).
    final pinned = _images.where((i) => i.pinned).toList();
    final unpinned = _images.where((i) => !i.pinned).toList();
    final todoImages = [...pinned, ...unpinned];
    final total = folderImages.length + todoImages.length;

    final headerStyle = AppTypography.caption.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.foreground,
    );
    final sectionHeaderStyle = AppTypography.caption.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.muted,
    );

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchItems(silent: true);
        await _fetchImages();
      },
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.content),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('총 $total개', style: headerStyle),
                // 정렬은 최신순 하나뿐(이미지엔 좋아요가 없다) — 드롭다운 없이 라벨만.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('최신순', style: headerStyle),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColors.foreground,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          if (total == 0)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.content),
              child: EmptyState(
                icon: Icons.image_outlined,
                message: '아직 이미지가 없어요\n＋ 버튼으로 사진을 올리거나 투두에 사진을 첨부해 보세요',
              ),
            )
          else ...[
            if (folderImages.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.content,
                ),
                child: Text('이 폴더에 올린 사진', style: sectionHeaderStyle),
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._buildFolderImageRows(folderImages),
            ],
            if (todoImages.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.content,
                ),
                child: Text('투두에 첨부된 사진', style: sectionHeaderStyle),
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._buildImageRows(todoImages),
            ],
          ],
        ],
      ),
    );
  }

  /// 2열 그리드 — GridView 대신 2개씩 묶은 Row를 이어붙인다(폴더 그리드와 같은 방식 —
  /// GridView는 lazy build라 오프스크린 카드가 위젯 테스트에 안 잡힌다).
  List<Widget> _buildImageRows(List<ArchiveTodoImage> images) {
    final rows = <List<ArchiveTodoImage>>[];
    for (var i = 0; i < images.length; i += 2) {
      rows.add(images.sublist(i, (i + 2).clamp(0, images.length)));
    }
    return [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.content,
            0,
            AppSpacing.content,
            AppSpacing.content,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.content),
                Expanded(
                  child: i < row.length
                      ? _TodoImageCell(
                          key: ValueKey('archive-image-${row[i].id}'),
                          image: row[i],
                          onPin: () => _toggleImagePin(row[i]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  /// 이 폴더에 직접 업로드한 이미지 자료(V26) 2열 그리드 — [_buildImageRows]와 같은 레이아웃,
  /// 담당자 아바타가 없고 탭하면 자료 상세로 이동한다는 점만 다르다.
  List<Widget> _buildFolderImageRows(List<ArchiveItem> items) {
    final rows = <List<ArchiveItem>>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(items.sublist(i, (i + 2).clamp(0, items.length)));
    }
    return [
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.content,
            0,
            AppSpacing.content,
            AppSpacing.content,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.content),
                Expanded(
                  child: i < row.length
                      ? _ArchiveImageCell(
                          key: ValueKey('archive-folder-image-${row[i].id}'),
                          item: row[i],
                          onPin: () => _togglePin(row[i]),
                          onTap: () async {
                            await context.push('/archive/item/${row[i].id}');
                            if (!mounted) return;
                            _fetchItems(silent: true);
                          },
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  Widget _buildItemsTab(_ArchiveTab tab) {
    return RefreshIndicator(
      onRefresh: () => _fetchItems(silent: true),
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.content),
        children: [
          _buildListHeader(tab),
          const SizedBox(height: AppSpacing.cardGap),
          _buildAnalyzingBanner(),
          _buildItemList(tab),
        ],
      ),
    );
  }

  /// 상단바 검색바(2026-08-08 디자이너 지정) — 폴더명·검색·＋ 아이콘 자리를 통째로 대체한다.
  /// 알약형(`radius.pill`), placeholder "검색할 내용을 입력해주세요.", 돋보기는 **오른쪽**
  /// suffix(기존 아이콘 위치 계승 — 같은 아이콘이 액션 자리에서 필드 안으로 옮겨온 것뿐이라
  /// 다시 누르면 검색이 닫힌다).
  Widget _buildSearchAppBarField() {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.content),
      child: TextField(
        key: const ValueKey('archive-search-field'),
        autofocus: true,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: '검색할 내용을 입력해주세요.',
          // #CCCCCC/레귤러/14pt는 design.md 색·타이포 스케일에 없는 지정값 — 이 검색바
          // placeholder 전용으로 리터럴을 쓴다(2026-08-08 디자이너 확정).
          hintStyle: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Color(0xFFCCCCCC),
          ),
          // borderSoft(#EBEBEB) — 디자이너가 이 검색바에 지정한 외곽선 색(2026-08-08).
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
            borderSide: const BorderSide(color: AppColors.borderStrong),
          ),
          suffixIcon: IconButton(
            key: const ValueKey('archive-search-toggle'),
            onPressed: () => setState(() {
              _searchOpen = false;
              _searchQuery = '';
            }),
            icon: const Icon(Icons.search, color: AppColors.foreground),
            tooltip: '검색 닫기',
          ),
        ),
      ),
    );
  }

  /// 이 폴더에서 아직 분석 중인 자료 수 — 검색·정렬과 무관하게 <b>폴더 전체</b>를 센다.
  ///
  /// 검색어로 걸러진 목록만 세면, 방금 넣은 자료가 검색 결과 밖이라 "분석 중 0건"이 되면서
  /// 사용자가 찾던 그 신호가 사라진다.
  int get _analyzingCount =>
      _items.where((item) => item.crawlStatus == 'PENDING').length;

  /// "분석 중 N건" 안내(2026-08-06 사용자 피드백).
  ///
  /// 🔴 <b>왜 필요한가.</b> 등록이 비동기가 되면서 [등록]을 눌러도 화면이 곧바로 조용해진다.
  /// 목록에 항목은 들어오지만 아직 제목이 URL이고 썸네일도 없어서, 사용자가 "공유가 된 건가?"를
  /// 확신하지 못한다는 피드백이 있었다. 개별 항목의 배지만으로는 눈에 안 띈다.
  ///
  /// 세는 것은 앱이 한다 — 목록 응답에 이미 항목별 `crawlStatus`가 있어 서버를 안 고쳐도 된다.
  ///
  /// ⚠️ <b>이 숫자는 스스로 줄지 않는다.</b> 폴링을 넣지 않기로 했으므로(2026-08-06 확정)
  /// 다시 불러와야 갱신된다. 그래서 문구로 "당겨서 새로고침"을 함께 알려준다. 완료 시점은
  /// 푸시 알림이 따로 맡는다.
  Widget _buildAnalyzingBanner() {
    final count = _analyzingCount;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.content,
        0,
        AppSpacing.content,
        AppSpacing.content,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.content,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          // 항목 배지와 같은 색을 쓴다 — 같은 상태를 가리키는 두 표시가 따로 놀지 않게.
          color: AppColors.accentWarningBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.hourglass_empty,
              size: 16,
              color: AppColors.accentWarningText,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '자료 $count건을 분석하고 있어요. 당겨서 새로고침하면 갱신돼요.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.accentWarningText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 리스트 헤더 — 좌측 "총 N개"(폴더 전체 링크 자료 수) + 우측 정렬 드롭다운(최신순/좋아요순).
  /// 핀 고정 자료는 정렬과 무관하게 항상 최상단(`_filteredSortedItemsFor`).
  Widget _buildListHeader(_ArchiveTab tab) {
    final headerStyle = AppTypography.caption.copyWith(
      fontWeight: FontWeight.w600,
      color: AppColors.foreground,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('총 ${_tabItemsFor(tab).length}개', style: headerStyle),
          PopupMenuButton<_SortMode>(
            key: const ValueKey('archive-sort-dropdown'),
            initialValue: _sortMode,
            onSelected: (mode) => setState(() => _sortMode = mode),
            tooltip: '정렬',
            position: PopupMenuPosition.under,
            itemBuilder: (context) => const [
              PopupMenuItem(value: _SortMode.latest, child: Text('최신순')),
              PopupMenuItem(value: _SortMode.likes, child: Text('좋아요순')),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _sortMode == _SortMode.latest ? '최신순' : '좋아요순',
                  style: headerStyle,
                ),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: AppColors.foreground,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemList(_ArchiveTab tab) {
    final items = _filteredSortedItemsFor(tab);

    if (_tabItemsFor(tab).isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
        // 아이콘 + 문구만(액션 버튼 없음) — 폴더 안에서는 상단바 ＋로 이미 추가할 수
        // 있어 빈 상태에 또 버튼을 두지 않는다(2026-08-08 확정).
        child: EmptyState(
          icon: tab == _ArchiveTab.text
              ? Icons.notes_outlined
              : Icons.link_off_rounded,
          message: tab == _ArchiveTab.text ? '아직 텍스트 자료가 없어요' : '아직 링크 자료가 없어요',
        ),
      );
    }

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.content),
        child: EmptyState(
          icon: Icons.search_off_rounded,
          message: '검색 결과가 없어요',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
      child: Column(
        children: [
          for (final item in items)
            _ArchiveItemTile(
              key: ValueKey('archive-item-${item.id}'),
              item: item,
              domain: _domain(item),
              titleUnresolved: _isUnresolvedFailedTitle(item),
              onTap: () async {
                await context.push('/archive/item/${item.id}');
                if (!mounted) return;
                _fetchItems();
              },
              onPin: () => _togglePin(item),
            ),
        ],
      ),
    );
  }
}

/// 폴더 자료 카드(2026-08-08 리디자인, specs/0010). 테두리 없이 큰 썸네일 + 우측 정보.
/// 상단[태그·분석배지 + 핀 토글] → 제목 2줄 → 하단[도메인 + 좋아요]. 썸네일 높이에 맞춰
/// 세 조각을 위·중·아래로 벌린다.
class _ArchiveItemTile extends StatelessWidget {
  const _ArchiveItemTile({
    super.key,
    required this.item,
    required this.domain,
    required this.titleUnresolved,
    required this.onTap,
    required this.onPin,
  });

  final ArchiveItem item;
  final String? domain;

  /// `_isUnresolvedFailedTitle` 결과 — true면 제목 자리에 URL 대신 안내 문구를 보여준다.
  final bool titleUnresolved;
  final VoidCallback onTap;
  final VoidCallback onPin;

  static const double _thumbSize = 112;

  @override
  Widget build(BuildContext context) {
    final hasChips = item.tags.isNotEmpty || item.crawlStatus != 'DONE';
    // 텍스트 자료(링크·이미지 아님)는 왼쪽 썸네일을 아예 두지 않는다(2026-08-09 요청) —
    // 링크는 OG 썸네일, 이미지는 업로드 사진이 있지만 텍스트는 보여줄 이미지가 없어
    // 회색 플레이스홀더만 남았다. 텍스트는 글부터 바로 시작한다.
    final isText =
        (item.url == null || item.url!.trim().isEmpty) && item.imageUrl == null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isText) ...[
              SizedBox(
                width: _thumbSize,
                height: _thumbSize,
                child: ArchiveThumbnail(
                  url: item.thumbnail,
                  radius: AppRadius.card,
                ),
              ),
              const SizedBox(width: AppSpacing.content),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단 — 좌: 태그 칩(+분석 배지) 한 줄 / 우: 핀. 좋아요는 목록에 표시하지
                  // 않는다(좋아요는 상세(S-25-B)에서만 보고 누른다, 2026-08-08 확정).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: hasChips
                            ? SingleLineChips(
                                chips: [
                                  if (item.crawlStatus != 'DONE')
                                    ChipSpec.crawlStatus(item.crawlStatus),
                                  for (final tag in item.tags)
                                    ChipSpec.tag(tag),
                                ],
                              )
                            : const SizedBox(height: ArchiveTagChip.height),
                      ),
                      // 카드 우상단에 좋아요 수(2026-08-09) — 카드 높이를 안 건드리게 아주 작게
                      // (하트 12 + 수). 목록에선 표시만, 누르는 건 상세(S-25-B)에서.
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        Icons.favorite_border,
                        size: 12,
                        color: AppColors.mutedSoft,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${item.likeCount}',
                        style: AppTypography.badge.copyWith(
                          color: AppColors.mutedSoft,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _PinButton(pinned: item.pinned, onTap: onPin),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // 제목 2줄. 분석 실패로 제목이 원본 URL 그대로면(`titleUnresolved`) URL을
                  // 그대로 노출하지 않고 안내 문구로 대체한다 — 긴 URL이 2줄을 채우면 지저분하다.
                  Text(
                    titleUnresolved ? '제목을 가져오지 못했어요' : item.title,
                    style: titleUnresolved
                        ? AppTypography.title.copyWith(color: AppColors.muted)
                        : AppTypography.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // 도메인(있을 때만 — 텍스트 자료는 도메인이 없어 생략).
                  if (domain != null && domain!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      domain!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.mutedSoft,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 카드 우상단 핀 토글 24×24. 미고정 = 회색 라인 아이콘(`majesticons_pin-line.svg`,
/// #C1C1C1 `border-strong`), 고정 = 채워진 핑크 핀(`primary_pin.svg`, `primary` 틴트) —
/// 2026-08-08 디자이너 지정: 색만 바꾸지 않고 아이콘 자체를 다른 그림으로 바꾼다.
class _PinButton extends StatelessWidget {
  const _PinButton({required this.pinned, required this.onTap});

  final bool pinned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey('archive-pin-${pinned ? 'on' : 'off'}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SvgPicture.asset(
        pinned
            ? 'assets/icons/primary_pin.svg'
            : 'assets/icons/majesticons_pin-line.svg',
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          pinned ? AppColors.primary : AppColors.borderStrong,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

/// 이미지 탭 셀(2026-08-09) — 정사각 사진 + 우상단 핀 + 우하단 담당자 아바타 + 아래 관련
/// 투두 제목(1줄 말줄임, 탭하면 전체 펼침 — 상세 제목과 같은 패턴).
class _TodoImageCell extends StatefulWidget {
  const _TodoImageCell({super.key, required this.image, required this.onPin});

  final ArchiveTodoImage image;
  final VoidCallback onPin;

  @override
  State<_TodoImageCell> createState() => _TodoImageCellState();
}

class _TodoImageCellState extends State<_TodoImageCell> {
  /// 제목이 …으로 잘렸을 때 제목을 터치하면 전체를 펼친다. 다시 터치하면 접힘.
  bool _titleExpanded = false;

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ArchiveThumbnail(
                url: image.imageUrl,
                radius: AppRadius.card,
                placeholderIcon: Icons.image_outlined,
              ),
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: _PinButton(pinned: image.pinned, onTap: widget.onPin),
              ),
              if (image.assignee != null)
                Positioned(
                  bottom: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: ArchiveAuthorAvatar(
                    author: image.assignee,
                    size: 24,
                    semanticsPrefix: '담당자',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _titleExpanded = !_titleExpanded),
          child: Text(
            image.todoTitle,
            style: AppTypography.title,
            maxLines: _titleExpanded ? null : 1,
            overflow: _titleExpanded
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// 폴더 직접 업로드 이미지 자료(V26) 셀 — [_TodoImageCell]과 같은 정사각 그리드지만 담당자
/// 아바타가 없고(투두처럼 배정 담당자 개념이 없다), 사진을 탭하면 자료 상세로 이동한다(삭제·메모
/// 편집 등은 링크/텍스트 자료와 같은 상세 화면을 그대로 쓴다).
class _ArchiveImageCell extends StatefulWidget {
  const _ArchiveImageCell({
    super.key,
    required this.item,
    required this.onPin,
    required this.onTap,
  });

  final ArchiveItem item;
  final VoidCallback onPin;
  final VoidCallback onTap;

  @override
  State<_ArchiveImageCell> createState() => _ArchiveImageCellState();
}

class _ArchiveImageCellState extends State<_ArchiveImageCell> {
  /// 제목이 …으로 잘렸을 때 제목을 터치하면 전체를 펼친다 — [_TodoImageCellState]와 같은 패턴.
  bool _titleExpanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: widget.onTap,
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ArchiveThumbnail(
                  url: item.imageUrl,
                  radius: AppRadius.card,
                  placeholderIcon: Icons.image_outlined,
                ),
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: _PinButton(pinned: item.pinned, onTap: widget.onPin),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _titleExpanded = !_titleExpanded),
          child: Text(
            item.title,
            style: AppTypography.title,
            maxLines: _titleExpanded ? null : 1,
            overflow: _titleExpanded
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
