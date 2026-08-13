import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../home/home_coach_anchors.dart';
import '../room/room_session.dart';
import '../room/room_switch_hint.dart';
import '../room/room_switcher_sheet.dart';
import 'tab_activation.dart';

/// 하단 5탭 셸(홈/투두/일정/모아보기/마이) — specs/0003-navigation.md ShellRoute.
/// 홈 버튼 롱프레스는 S-07 방 전환 시트를 여는 보조 트리거다 — specs/0008-방-전환.md.
/// 상단 방 컨텍스트(방이름▾, ☰)는 기능 구현 시 각 탭 화면에서 채운다.
class AppShell extends StatefulWidget {
  AppShell({
    super.key,
    required this.navigationShell,
    RoomSession? roomSession,
    TabActivation? tabActivation,
  }) : roomSession = roomSession ?? appRoomSession,
       tabActivation = tabActivation ?? appTabActivation;

  final StatefulNavigationShell navigationShell;
  final RoomSession roomSession;

  /// 활성 탭을 화면들에 알리는 신호 — 탭이 켜지면 그 화면이 조용히 다시 불러온다(요청 1).
  final TabActivation tabActivation;

  /// 탭별 아이콘 — 단색 SVG 1종을 상태별로 틴트한다(2026-08-07: 크기·해상도 제각각이던
  /// PNG 10종에서 광학 크기·스트로크를 통일한 SVG 5종으로 교체). inactive=muted, active=primary.
  static const tabs = [
    (label: '홈', svg: 'assets/icons/nav_home.svg'),
    (label: '투두', svg: 'assets/icons/nav_todo.svg'),
    (label: '일정', svg: 'assets/icons/nav_schedule.svg'),
    (label: '모아보기', svg: 'assets/icons/nav_archive.svg'),
    (label: '마이', svg: 'assets/icons/nav_my.svg'),
  ];

  /// 네비 아이콘 렌더 크기(Material 기본 아이콘과 동일 24).
  static const navIconSize = 24.0;

  /// 탭 인덱스 — `tabs` 순서와 같아야 한다. 각 화면이 "내 탭이 켜졌는지"를 이 값으로 판단한다.
  /// 홈은 롱프레스 트리거와 코치마크가 가리키는 위치이기도 하다.
  static const homeIndex = 0;
  static const todosIndex = 1;
  static const scheduleIndex = 2;
  static const archiveIndex = 3;
  static const mypageIndex = 4;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _navBarKey = GlobalKey();
  OverlayEntry? _hintEntry;

  /// 지금 떠 있는 코치마크 단계(intro=2스텝 투어, multi=단일 리마인더). null이면 없음.
  RoomSwitchHintStage? _activeStage;

  /// intro 투어 스텝 — 0=네비바 홈, 1=멤버 아바타. specs/0008-방-전환.md.
  int _tourStep = 0;

  @override
  void initState() {
    super.initState();
    // 방 개수가 실행 중에 2개를 넘어서면(방 참여·생성 직후) 코치마크 2단계를 다시 판정한다.
    widget.roomSession.addListener(_onRoomSessionChanged);
    // 시작 탭은 알리지 않는다 — 화면들이 방금 첫 조회를 걸었는데 또 부르게 된다.
    widget.tabActivation.syncInitial(widget.navigationShell.currentIndex);
    // 네비바가 레이아웃된 뒤에야 홈 버튼 위치를 알 수 있다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowHint());
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomSession != widget.roomSession) {
      oldWidget.roomSession.removeListener(_onRoomSessionChanged);
      widget.roomSession.addListener(_onRoomSessionChanged);
    }
    // 홈이 아닌 탭으로 옮겨가면 홈 버튼을 가리키던 코치마크는 의미가 없다.
    if (widget.navigationShell.currentIndex != AppShell.homeIndex) {
      _removeHint();
    }
    _publishActiveTab();
  }

  /// 활성 탭을 각 화면에 알린다(요청 1: 탭을 켜면 그 화면이 조용히 다시 불러온다).
  /// build 중에 리스너를 깨우면 "빌드 도중 setState" 가 되므로 프레임 뒤로 미룬다.
  void _publishActiveTab() {
    final index = widget.navigationShell.currentIndex;
    if (widget.tabActivation.index == index) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.tabActivation.index = index;
    });
  }

  @override
  void dispose() {
    widget.roomSession.removeListener(_onRoomSessionChanged);
    _removeHint();
    super.dispose();
  }

  void _onRoomSessionChanged() {
    if (!mounted) return;
    _maybeShowHint();
  }

  /// 네비바에서 홈 버튼이 차지하는 칸의 중심(글로벌 좌표).
  /// NavigationBar는 하단 안전영역만큼 아래에 여백을 두므로 그만큼을 빼고 세로 중심을 잡는다.
  Offset? _homeButtonCenter() {
    final box = _navBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final cellWidth = box.size.width / AppShell.tabs.length;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final destinationHeight = box.size.height - bottomInset;
    return box.localToGlobal(
      Offset(cellWidth * (AppShell.homeIndex + 0.5), destinationHeight / 2),
    );
  }

  /// 멤버 아바타(홈 첫 비-본인) 중심의 글로벌 좌표. 홈 레이아웃 전이거나 솔로 방이면 null.
  Offset? _memberAvatarCenter() {
    final box =
        homeFirstMemberAvatarKey.currentContext?.findRenderObject()
            as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  Future<void> _maybeShowHint() async {
    if (_hintEntry != null) return;
    if (widget.navigationShell.currentIndex != AppShell.homeIndex) return;

    final activeRoomCount = widget.roomSession.rooms
        .where((room) => room.isActive)
        .length;
    final stage = await RoomSwitchHintPrefs.pendingStage(
      activeRoomCount: activeRoomCount,
    );
    // prefs 조회 사이에 상황이 바뀔 수 있어 다시 확인한다.
    if (stage == null || !mounted || _hintEntry != null) return;
    if (widget.navigationShell.currentIndex != AppShell.homeIndex) return;

    // 홈 버튼(첫 스텝 대상)이 아직 레이아웃 안 됐으면 이번엔 건너뛴다 — 다음 트리거 때 다시.
    if (_homeButtonCenter() == null) return;

    _activeStage = stage;
    _tourStep = 0;
    final entry = OverlayEntry(builder: (context) => _buildHint());
    _hintEntry = entry;
    Overlay.of(context).insert(entry);
  }

  /// 현재 단계·스텝에 맞는 코치마크를 그린다(스텝 전환 시 [OverlayEntry.markNeedsBuild]로 갱신).
  Widget _buildHint() {
    final stage = _activeStage;
    if (stage == null) return const SizedBox.shrink();

    // 방 2개 이상 리마인더 — 기존 단일 스텝(버튼 없음·바깥 탭으로 닫힘).
    if (stage == RoomSwitchHintStage.multi) {
      final center = _homeButtonCenter();
      if (center == null) return const SizedBox.shrink();
      return RoomSwitchHintOverlay(
        targetCenter: center,
        onTryNow: _openRoomSwitcher,
        onDismiss: () => _dismissHint(stage),
      );
    }

    // intro 2스텝 투어 — 바깥 탭으로 안 닫히고 우하단 버튼으로만 진행·종료.
    if (_tourStep == 0) {
      final center = _homeButtonCenter();
      if (center == null) return const SizedBox.shrink();
      return RoomSwitchHintOverlay(
        targetCenter: center,
        onTryNow: _openRoomSwitcher, // 구멍 롱프레스로 방 전환 실습 유지
        onDismiss: () {},
        dismissOnOutsideTap: false,
        primaryLabel: '다음',
        onPrimary: _advanceTour,
      );
    }

    final avatarCenter = _memberAvatarCenter();
    if (avatarCenter == null) return const SizedBox.shrink();
    return RoomSwitchHintOverlay(
      targetCenter: avatarCenter,
      onDismiss: () {},
      dismissOnOutsideTap: false,
      bubbleBelow: true,
      title: '팀원을 눌러 콕 찔러보세요',
      body: '진행 상황을 보고 콕 찔러 독려할 수 있어요',
      semanticsLabel: '팀원 아바타를 누르면 진행 상황을 보고 콕 찔러 독려할 수 있어요. 완료 버튼으로 안내를 닫습니다.',
      primaryLabel: '완료',
      onPrimary: () => _dismissHint(RoomSwitchHintStage.intro),
    );
  }

  /// intro 홈 스텝 → 아바타 스텝. 아바타가 없으면(솔로 방) 그대로 투어를 끝낸다.
  void _advanceTour() {
    if (_memberAvatarCenter() == null) {
      _dismissHint(RoomSwitchHintStage.intro);
      return;
    }
    _tourStep = 1;
    _hintEntry?.markNeedsBuild();
  }

  void _dismissHint(RoomSwitchHintStage stage) {
    _removeHint();
    RoomSwitchHintPrefs.markShown(stage);
  }

  void _removeHint() {
    _hintEntry?.remove();
    _hintEntry = null;
    _activeStage = null;
    _tourStep = 0;
  }

  /// 탭은 이동시키지 않는다 — 롱프레스는 "방 전환" 전용 제스처다(specs/0008-방-전환.md).
  Future<void> _openRoomSwitcher() async {
    _removeHint();
    await RoomSwitchHintPrefs.markUsed();
    if (!mounted) return;
    await showRoomSwitcher(context, widget.roomSession);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      // 플로팅 하단 네비 — 흰 배경 + 상단 좌우 24px 라운드 + 위쪽 은은한 그림자로
      // 스크롤 콘텐츠와 분리(design.md §6). 그림자는 클립 밖 컨테이너가, 라운드는 ClipRRect가.
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.navBar),
          ),
          boxShadow: AppElevation.navBar,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.navBar),
          ),
          child: Stack(
            children: [
              NavigationBar(
                key: _navBarKey,
                selectedIndex: widget.navigationShell.currentIndex,
                onDestinationSelected: (index) {
                  // 탭을 누르면 **항상 그 탭의 최상위 페이지로**(하위페이지가 열려 있으면 pop) +
                  // **맨 위로 스크롤**(2026-08-09 요청). initialLocation:true가 브랜치를 루트
                  // 라우트로 되돌리고, reselect 신호로 각 탭 화면이 스크롤을 0으로 되돌린다.
                  widget.navigationShell.goBranch(index, initialLocation: true);
                  widget.tabActivation.reselect.notify(index);
                },
                backgroundColor: Colors.transparent,
                destinations: [
                  for (final tab in AppShell.tabs)
                    NavigationDestination(
                      icon: SvgPicture.asset(
                        tab.svg,
                        width: AppShell.navIconSize,
                        height: AppShell.navIconSize,
                        colorFilter: const ColorFilter.mode(
                          AppColors.muted,
                          BlendMode.srcIn,
                        ),
                      ),
                      selectedIcon: SvgPicture.asset(
                        tab.svg,
                        width: AppShell.navIconSize,
                        height: AppShell.navIconSize,
                        colorFilter: const ColorFilter.mode(
                          AppColors.primary,
                          BlendMode.srcIn,
                        ),
                      ),
                      label: tab.label,
                    ),
                ],
              ),
              // NavigationDestination 내부 Tooltip이 롱프레스를 먼저 가져가므로, 네비바를 감싸는
              // GestureDetector로는 롱프레스를 잡을 수 없다(실측). 홈 칸 위에만 translucent 레이어를
              // 얹어 롱프레스만 가로채고 탭은 아래 NavigationBar로 그대로 통과시킨다.
              Positioned.fill(
                child: Row(
                  children: [
                    for (var index = 0; index < AppShell.tabs.length; index++)
                      Expanded(
                        child: index == AppShell.homeIndex
                            ? GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onLongPress: _openRoomSwitcher,
                                child: const SizedBox.expand(),
                              )
                            : const SizedBox.expand(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
