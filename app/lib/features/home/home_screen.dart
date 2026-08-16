import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../design/todo_checkbox.dart';
import '../../design/tokens.dart';
import '../auth/auth_service.dart';
import '../notifications/notifications_api.dart';
import '../room/no_room_hero.dart';
import '../room/room_session.dart';
import '../room/room_switcher_sheet.dart';
import '../shell/app_shell.dart';
import '../shell/tab_activation.dart';
import '../todos/pending_completion.dart';
import '../todos/todo_sync.dart';
import '../todos/todos_api.dart' show TodoNotAssigneeException;
import 'activity_banner.dart';
import 'archive_carousel.dart';
import 'avatar_progress_ring.dart';
import 'home_coach_anchors.dart';
import 'home_api.dart';
import 'home_hero.dart';
import 'week_calendar.dart';

/// S-04 홈 대시보드 — specs/0005-홈-대시보드.md.
/// "현재 방" 해석·전환은 [RoomSession](specs/0008-방-전환.md) 참고.
class HomeScreen extends StatefulWidget {
  HomeScreen({
    super.key,
    HomeApi? api,
    AuthService? authService,
    RoomSession? roomSession,
    TodoSync? todoSync,
    TabActivation? tabActivation,
    NotificationsApi? notificationsApi,
  }) : api = api ?? HomeApi(),
       authService = authService ?? AuthService(),
       roomSession = roomSession ?? appRoomSession,
       todoSync = todoSync ?? appTodoSync,
       tabActivation = tabActivation ?? appTabActivation,
       notificationsApi = notificationsApi ?? NotificationsApi();

  final HomeApi api;
  final AuthService authService;
  final RoomSession roomSession;
  final TodoSync todoSync;
  final TabActivation tabActivation;
  final NotificationsApi notificationsApi;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;

  /// 한 번이라도 대시보드를 그린 뒤인가 — 그 뒤로는 재조회에 전체 스피너를 쓰지 않는다(요청 6).
  bool _loadedOnce = false;
  String? _errorText;
  String? _todoErrorText;
  DashboardData? _data;
  int? _roomId;

  /// S-06 방없음 상태인가 — **방 목록을 실제로 읽어서 ACTIVE가 하나도 없었을 때만** true다.
  ///
  /// 🔴 `_roomId == null` 로 판단하면 안 된다. 조회가 실패해도 `_roomId` 는 null 로 남는데,
  /// 조용한 새로고침(`silent: true`)의 실패는 `_errorText` 를 채우지 않아
  /// **네트워크 오류가 "방이 없어요" 로 둔갑한다.** 조회 성공 여부를 따로 들고 있어야 갈린다.
  bool _noActiveRoom = false;

  /// 방 전환 시트가 열려 있는지 — 히어로 토글 회전에만 쓴다(2026-08-05 요청).
  bool _roomSwitcherOpen = false;
  DateTime? _weekStart;

  // 방 전환 등으로 _load()가 겹쳐 호출될 때 먼저 시작한 요청이 나중 요청 결과를 덮어쓰지 않도록 막는 가드.
  int _loadGeneration = 0;

  // 내가 유발한 투두 변경이면 내 리스너 리로드를 건너뛴다(낙관적 업데이트로 이미 반영).
  bool _selfTodoMutation = false;

  /// 홈 탭 재탭 시 맨 위로 스크롤(2026-08-09 QA)용 컨트롤러.
  final ScrollController _scrollController = ScrollController();

  /// 홈 벨 배지(S-41, specs/0017-알림-내역.md). 보조 정보라 로드 실패는 조용히 무시하고 배지를 숨긴다.
  int _unreadNotificationCount = 0;

  /// 내 투두 완료 체크를 2초 붙잡아 취소 가능하게(2026-08-09 재도입 — 투두 탭과 동일 규칙).
  /// 홈을 떠나거나(탭 전환·화면 이탈) 2초가 지나면 서버에 반영한다.
  final PendingCompletions _pending = PendingCompletions();

  @override
  void initState() {
    super.initState();
    widget.roomSession.addListener(_onRoomSessionChanged);
    widget.todoSync.addListener(_onExternalTodoChange);
    widget.tabActivation.addListener(_onTabChanged);
    widget.tabActivation.reselect.addListener(_onTabReselected);
    _load();
    _loadUnreadNotificationCount();
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final idToken = await widget.authService.getIdToken();
      final count = await widget.notificationsApi.fetchUnreadCount(idToken);
      if (mounted) setState(() => _unreadNotificationCount = count);
    } catch (_) {
      // 배지는 보조 정보 — 실패해도 홈 화면 자체는 그대로 쓸 수 있어야 한다.
    }
  }

  @override
  void dispose() {
    _pending.flushAll(); // 대기 중 완료는 화면을 떠날 때 서버로 보낸다(버리지 않음)
    widget.roomSession.removeListener(_onRoomSessionChanged);
    widget.todoSync.removeListener(_onExternalTodoChange);
    widget.tabActivation.removeListener(_onTabChanged);
    widget.tabActivation.reselect.removeListener(_onTabReselected);
    _scrollController.dispose();
    super.dispose();
  }

  /// 홈 탭을 **다시** 누르면(이미 홈인 상태) 맨 위로 부드럽게 스크롤한다(2026-08-09 QA).
  void _onTabReselected() {
    if (!mounted) return;
    if (widget.tabActivation.reselect.index != AppShell.homeIndex) return;
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// 홈 탭이 다시 켜지면 조용히 최신 대시보드로 맞춘다(요청 1).
  void _onTabChanged() {
    if (!mounted) return;
    if (widget.tabActivation.index == AppShell.homeIndex) {
      _load(silent: true);
      _loadUnreadNotificationCount();
    } else {
      // 홈을 떠나면 대기 중이던 완료 체크를 즉시 서버에 반영한다(취소 기회 종료).
      _pending.flushAll();
    }
  }

  void _onRoomSessionChanged() {
    if (!mounted) return;
    _load();
  }

  /// 다른 화면(투두 탭 등)에서 투두 완료가 바뀌면 대시보드를 다시 불러온다
  /// (오늘 투두·진행률 갱신). 내가 유발한 변경이면 스킵.
  void _onExternalTodoChange() {
    // 외부 변경은 조용히 갱신 — 전체 스피너로 초기화하지 않고 기존 대시보드를 유지한다.
    if (mounted && !_selfTodoMutation) _load(silent: true);
  }

  /// 다른 화면에 투두 변경을 알린다(자기 리스너는 스킵).
  void _notifyTodoChanged() {
    _selfTodoMutation = true;
    widget.todoSync.markChanged();
    _selfTodoMutation = false;
  }

  /// [silent]이면 실패해도 에러 화면으로 뒤엎지 않는다(외부 동기화 리로드용).
  ///
  /// 전체 스피너는 **첫 로드에만** 쓴다 — 한 번 대시보드를 보여준 뒤로는 재조회 중에도
  /// 화면을 유지하고 결과가 오면 내용만 갈아끼운다(요청 6).
  Future<void> _load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    setState(() {
      if (!silent && !_loadedOnce) _loading = true;
      _errorText = null;
      // 새로고침·방전환 시 이전 방의 토글 실패 인라인 에러가 남지 않도록 정리.
      _todoErrorText = null;
    });
    try {
      final idToken = await widget.authService.getIdToken();
      await widget.roomSession.loadRooms(idToken);
      final resolution = await widget.roomSession.resolveCurrentRoom();
      final roomId = resolution.roomId;
      if (roomId == null) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _data = null;
          _roomId = null;
          // 목록을 읽어서 ACTIVE가 없다고 **확인한** 자리 — 여기서만 S-06을 켠다.
          _noActiveRoom = true;
          _loading = false;
          _loadedOnce = true;
        });
        return;
      }

      if (resolution.switchedFromEnded && mounted) {
        final previousName = resolution.previousRoomName ?? '이전 방';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$previousName 방이 종료되어 다른 진행중인 방으로 전환했어요')),
        );
      }

      final now = DateTime.now();
      final weekStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));
      final data = await widget.api.fetchDashboard(
        idToken,
        roomId,
        weekStart: weekStart,
        weekEnd: weekEnd,
      );
      // 이 요청이 진행되는 동안 더 최신 _load()가 시작됐다면 이 결과는 버린다(오래된 응답이
      // 나중에 도착해 최신 상태를 덮어쓰는 경쟁 상태 방지).
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _roomId = roomId;
        _noActiveRoom = false;
        _weekStart = weekStart;
        _data = data;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (!silent) _errorText = '홈 정보를 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  /// 하단 네비 홈 버튼 롱프레스(AppShell)와 동일한 경로를 쓴다 — specs/0008-방-전환.md.
  ///
  /// 시트가 열려 있는 동안 히어로의 토글을 180도 돌려 둔다(2026-08-05 요청). 시트가 어떻게
  /// 닫히든(선택·바깥 탭·뒤로) `await`가 끝나므로 아이콘이 열린 채로 남지 않는다.
  Future<void> _openRoomSwitcher(BuildContext context) async {
    setState(() => _roomSwitcherOpen = true);
    try {
      await showRoomSwitcher(context, widget.roomSession);
    } finally {
      if (mounted) setState(() => _roomSwitcherOpen = false);
    }
  }

  /// 홈의 '내 투두'는 내 담당 **미완료**만 보여준다. 체크하면 **화면엔 즉시 체크 + 진행률 +1**,
  /// 실제 서버 반영은 **2초 뒤**(그 안에 다시 누르면 취소, 2026-08-09 재도입). 2초가 지나거나
  /// 홈을 떠나면 서버에 반영하고 목록에서 뺀다. 실패하면 진행률 원복 + 인라인 에러.
  void _toggleTodo(TodoBrief todo) {
    final data = _data;
    if (data == null || _roomId == null) return;
    setState(() => _todoErrorText = null);
    if (_pending.isPending(todo.id)) {
      // 2초 안에 다시 탭 = 취소: 체크 해제 + 진행률 -1.
      _pending.cancel(todo.id);
      setState(() => _data = _withDoneDelta(data, -1));
      return;
    }
    // 체크: 화면엔 체크(진행률 +1)로 두고 2초 뒤 커밋 예약.
    setState(() => _data = _withDoneDelta(data, 1));
    _pending.schedule(todo.id, () => _commitCompletion(todo));
  }

  /// 2초 뒤(또는 flush로) 실제 서버 반영 — 성공하면 목록에서 빼고 다른 화면에 동기화한다.
  /// 진행률 +1은 [_toggleTodo]에서 이미 반영했으므로 여기선 실패 시에만 되돌린다.
  Future<void> _commitCompletion(TodoBrief todo) async {
    final roomId = _roomId;
    if (roomId == null) return;
    try {
      final idToken = await widget.authService.getIdToken();
      await widget.api.setTodoCompleted(idToken, roomId, todo.id, true);
      if (mounted && _data != null) {
        setState(() => _data = _removeTodayTodo(_data!, todo.id));
      }
      _notifyTodoChanged(); // 투두 탭 등 다른 화면에 반영
    } on TodoNotAssigneeException catch (e) {
      if (!mounted) return;
      setState(() {
        if (_data != null) _data = _withDoneDelta(_data!, -1);
        _todoErrorText = e.message; // FR-39: 담당자 아님 전용 안내
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_data != null) _data = _withDoneDelta(_data!, -1);
        _todoErrorText = '완료 처리에 실패했어요. 다시 시도해 주세요';
      });
    }
  }

  /// 진행률(todoDone)만 delta 만큼 바꾼 사본(낙관적 체크/취소용).
  DashboardData _withDoneDelta(DashboardData d, int delta) => DashboardData(
    room: d.room,
    members: d.members,
    weekSchedules: d.weekSchedules,
    todayTodos: d.todayTodos,
    recentArchives: d.recentArchives,
    todoDone: d.todoDone == null ? null : d.todoDone! + delta,
    todoTotal: d.todoTotal,
  );

  /// 완료가 서버에 반영된 투두를 오늘 투두 목록에서 뺀 사본(진행률은 이미 반영됨).
  DashboardData _removeTodayTodo(DashboardData d, int id) => DashboardData(
    room: d.room,
    members: d.members,
    weekSchedules: d.weekSchedules,
    todayTodos: [
      for (final t in d.todayTodos)
        if (t.id != id) t,
    ],
    recentArchives: d.recentArchives,
    todoDone: d.todoDone,
    todoTotal: d.todoTotal,
  );

  void _goToBranch(BuildContext context, int index) {
    StatefulNavigationShell.of(context).goBranch(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: AppSpacing.cardGap),
              Text('홈을 불러오고 있어요', style: AppTypography.bodySmall),
            ],
          ),
        ),
      );
    }

    if (_errorText != null) {
      return SafeArea(
        child: Center(
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
        ),
      );
    }

    // S-06 방없음 상태(specs/0004-방-생성-참여.md, specs/0003-navigation.md).
    //
    // 🔴 판단 근거는 `_data == null` 도 `_roomId == null` 도 아닌 `_noActiveRoom` 이다
    // (그 필드 주석 참고). 앞의 둘은 **조회에 실패했을 때도 참**이라 네트워크 오류를
    // "방이 없어요" 로 둔갑시킨다.
    //
    // 타이틀이 고정인 이유: 라우터가 방 0개(`membership == none`)를 S-03 으로 보내므로
    // (app_router.dart), 여기까지 왔다는 건 방을 가지고 있다는 뜻이다. S-03 이 쓰는
    // `hasEverEnteredRoom()` 은 SharedPreferences 기반이라 기기를 갈아타면 false 가 나와
    // "첫 번째 방을 만들어볼까요?" 가 잘못 뜬다.
    //
    // 상단 바(방이름▾)보다 먼저 return 하는 자리다 — S-06 에는 방 전환 트리거가 없다
    // (specs/0008-방-전환.md).
    if (_noActiveRoom) {
      return const NoRoomHero(title: '현재 진행 중인 방이 없어요!');
    }

    final data = _data;
    final weekStart = _weekStart;
    if (data == null || weekStart == null) {
      // 방은 있는데 대시보드를 못 채운 예기치 못한 상태. 에러 문구는 위 `_errorText` 분기가
      // 이미 잡으므로 여기까지 오면 재시도만 제공한다.
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.content),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('홈 정보를 불러오지 못했어요', style: AppTypography.bodySmall),
                const SizedBox(height: AppSpacing.cardGap),
                OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
              ],
            ),
          ),
        ),
      );
    }

    // 라이브 활동 배너는 히어로 상단 바(방이름▾) 바로 아래에 얹는다(2026-08-07 요청).
    final activityMessages = homeActivityMessages(data);

    // 컬랩싱 히어로 — 스크롤하면 히어로가 접히며(D-day 축소+페이드, 진행률 페이드, 이미지→흰색)
    // 상단 앱바(방이름▾ / ☰)만 흰 배경으로 고정되고 그 아래 콘텐츠가 스크롤된다(specs/0005 3단계).
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: kHomeHeroExpandedHeight,
            backgroundColor: AppColors.canvas,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            flexibleSpace: HomeHero(
              room: data.room,
              progress: data.todoProgress,
              // 백엔드 정확값이 없으면 멤버 담당 합산 근사치로 표시(백엔드 붙으면 자동 정확값).
              todoDone: data.displayTodoDone,
              todoTotal: data.displayTodoTotal,
              menuOpen: _roomSwitcherOpen,
              // 롱프레스 보조 트리거는 하단 네비 홈 버튼으로 이관됐다 — specs/0008-방-전환.md.
              onRoomTap: () => _openRoomSwitcher(context),
              // 햄버거→알림 벨로 교체(2026-08-07 요청). 2026-08-09: 알림 설정 대신 알림
              // 내역(S-41)으로 이관 — 설정 자체는 마이페이지 메뉴에서 계속 접근 가능(specs/0017).
              onNotificationsTap: () {
                context.push('/mypage/notification-history').then((_) {
                  if (mounted) _loadUnreadNotificationCount();
                });
              },
              unreadNotificationCount: _unreadNotificationCount,
              banner: activityMessages.isEmpty
                  ? null
                  : ActivityCapsuleBanner(messages: activityMessages),
            ),
          ),
          SliverToBoxAdapter(
            // 흰 바디. 상단 좌우 라운드는 히어로 바닥의 불투명 lip이 담당한다(HomeHero 참고).
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 흰 바디 상단 여백 — lip 곡선이 이미 여백을 만들어 최소(2026-08-07 xxs로 더 축소).
                const SizedBox(height: AppSpacing.xxs),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.content),
                  child: Text('오늘의 현황', style: AppTypography.display),
                ),
                const SizedBox(height: AppSpacing.cardGap),
                _buildMemberRow(context, data.members),
                const SizedBox(height: AppSpacing.content),
                _buildWeekSection(context, data.weekSchedules, weekStart),
                const SizedBox(height: AppSpacing.content),
                _buildTodayTodos(context, data.todayTodos),
                const SizedBox(height: AppSpacing.content),
                _buildArchivePreview(context, data.previewArchives),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberRow(BuildContext context, List<MemberProgress> members) {
    final myId = widget.authService.currentUserId;
    final ranked = rankMembersByProgress(members);
    // 최초 홈 코치마크 2스텝 투어가 가리킬 첫 번째 비-본인 아바타(없으면 -1 → 앵커 미부착,
    // 셸이 아바타 스텝을 건너뛴다). specs/0008-방-전환.md.
    final firstOtherIndex = ranked.indexWhere(
      (entry) => entry.member.userId != myId,
    );
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
        itemCount: ranked.length,
        // 아바타 사이 간격 — 12(md)에서 8(sm)로 좁힘(2026-08-09 QA).
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final member = ranked[index].member;
          final isSelf = member.userId == myId;
          final rank = ranked[index].rank;
          final showMedal = ranked[index].medal;
          return SizedBox(
            width: 72,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isSelf
                  ? () => _goToBranch(context, 1)
                  : () => context.push('/member/${member.userId}'),
              child: Column(
                children: [
                  // 아바타 + (상위3) 순위 메달 배지(우상단). 메달 SVG가 금·은·동 디자인을
                  // 자체적으로 담아 번호·왕관은 넣지 않는다(2026-08-08 사용자 메달 아트로 교체).
                  SizedBox(
                    height: 70,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        Positioned(
                          bottom: 0,
                          child: AvatarProgressRing(
                            key: index == firstOtherIndex
                                ? homeFirstMemberAvatarKey
                                : null,
                            size: 64,
                            progress: member.progressRatio,
                            label: member.nickname.isNotEmpty
                                ? member.nickname[0]
                                : '?',
                            imageUrl: member.profileImage,
                          ),
                        ),
                        if (showMedal)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: _RankBadge(rank: rank),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    isSelf ? '${member.nickname}(나)' : member.nickname,
                    style: isSelf
                        ? AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.foreground,
                          )
                        : AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWeekSection(
    BuildContext context,
    List<ScheduleBrief> schedules,
    DateTime weekStart,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
      child: _SectionBox(
        children: [
          _BoxHeader(title: '이번 주 일정', onMore: () => _goToBranch(context, 2)),
          const SizedBox(height: AppSpacing.cardGap),
          WeekCalendar(schedules: schedules, weekStart: weekStart),
        ],
      ),
    );
  }

  Widget _buildTodayTodos(BuildContext context, List<TodoBrief> todos) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
      child: _SectionBox(
        children: [
          _BoxHeader(title: '내 투두', onMore: () => _goToBranch(context, 1)),
          const SizedBox(height: AppSpacing.cardGap),
          if (_todoErrorText != null) ...[
            Text(
              _todoErrorText!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.accentDanger,
              ),
            ),
            const SizedBox(height: AppSpacing.cardGap),
          ],
          if (todos.isEmpty)
            // 빈 상태: '+ 투두 추가하기' 버튼. 탭 시 투두 탭으로 이동하면서 **추가 시트를 바로**
            // 띄운다(2026-08-09 요청 — 투두 탭이 활성화되며 요청을 소비해 시트를 연다).
            _TodoEmptyAdd(
              onTap: () {
                widget.tabActivation.requestOpenTodoComposer();
                _goToBranch(context, 1);
              },
            )
          else
            for (final todo in todos)
              _TodoRow(
                key: ValueKey('todo-row-${todo.id}'),
                todo: todo,
                checked: _pending.isPending(todo.id),
                onToggle: () => _toggleTodo(todo),
              ),
        ],
      ),
    );
  }

  Widget _buildArchivePreview(BuildContext context, List<ArchiveBrief> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
          child: _SectionHeader(
            title: '모아보기',
            onMore: () => _goToBranch(context, 3),
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        if (items.isEmpty)
          // 점선 드롭존 카드(요청 2026-08-06). 탭 시 모아보기 탭 이동 — 홈 직접 첨부는
          // 폴더 필수·파일 업로드 미지원(백엔드 갭, 전달 완료)이라 우회.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
            child: _ArchiveDropzone(onTap: () => _goToBranch(context, 3)),
          )
        else
          // 캐러셀은 full-bleed(좌우 패딩은 내부에서 처리)로 카드가 화면 끝까지 스크롤된다.
          ArchiveCarousel(
            items: items,
            onTapItem: (item) => context.push('/archive/item/${item.id}'),
          ),
      ],
    );
  }
}

/// 홈 활동 배너 메시지 — 팀 진행률·D-day(대시보드에서 프론트가 파생)에 백엔드 활동 피드
/// (docs/backend/home-activity-feed.md, [DashboardData.activities])의 per-user/소셜/자료
/// 메시지를 이어붙인다. 서버가 이미 최신·중요순으로 내려주므로 그 순서를 그대로 따른다 — 팀
/// 진행률·D-day는 항상 배너 맨 앞에 둔다(방 전체에 관한 것이라 개인 활동보다 먼저 보여준다).
/// 순수 함수라 단위 테스트로 검증한다.
List<ActivityMessage> homeActivityMessages(DashboardData data) {
  final messages = <ActivityMessage>[];
  final done = data.displayTodoDone;
  final total = data.displayTodoTotal;
  // 완료 0개면 축하 문구(🎉)가 어색하므로 넣지 않는다.
  if (done != null && total != null && total > 0 && done > 0) {
    final percent = ((done / total) * 100).round();
    messages.add(ActivityMessage.plain('🎉 팀 진행률 $percent% · 완료 $done개'));
  }
  final remaining = data.room.daysRemaining;
  if (remaining >= 0) {
    messages.add(
      ActivityMessage.plain(
        remaining == 0 ? '🔥 오늘이 마감이에요' : '⏳ 마감까지 D-$remaining',
      ),
    );
  }
  for (final activity in data.activities) {
    final message = _activityEventMessage(activity);
    if (message != null) messages.add(message);
  }
  return messages;
}

/// 활동 이벤트 타입별 문구 템플릿(docs/backend/home-activity-feed.md §2). 닉네임·대상·개수는
/// [ActivitySegment.bold]로 강조한다. actor가 필요한 타입인데 서버가 안 줬으면(있어선 안 되는
/// 상태다) 그 항목은 조용히 건너뛴다 — 빈 문구를 보여주는 것보다 낫다.
ActivityMessage? _activityEventMessage(ActivityEvent e) {
  switch (e.type) {
    case 'TODO_COMPLETED':
      return _withActor(
        e,
        (actor) => [actor, ActivitySegment('님이 투두 ${e.count ?? 1}개를 완료했어요 🔥')],
      );
    case 'TODO_COMPLETED_SHARED':
      // 공동 담당(2명 이상) 완료 — 주체는 팀, 대표닉만 굵게(2026-08-08 QA). targetName=대표닉,
      // count=담당자 총원(서버가 기존 필드를 재사용, docs/backend/live-banner-copy-handoff.md §2).
      final representative = e.targetName;
      if (representative == null) return null;
      final others = (e.count ?? 1) - 1;
      return ActivityMessage([
        ActivitySegment(bannerName(representative), bold: true),
        ActivitySegment(' 외 $others명이 함께 맡은 투두를 끝냈어요 🎉'),
      ]);
    case 'TODO_ALL_DONE':
      return _withActor(
        e,
        (actor) => [actor, const ActivitySegment('님이 맡은 투두를 다 끝냈어요 🎉')],
      );
    case 'TODO_ADDED':
      return _withActor(
        e,
        (actor) => [actor, const ActivitySegment('님이 투두를 추가했어요')],
      );
    case 'SCHEDULE_ADDED':
      return _withActor(
        e,
        (actor) => [actor, const ActivitySegment('님이 새로운 일정을 등록했어요')],
      );
    case 'SCHEDULE_SOON':
      return ActivityMessage.plain('곧 시작되는 일정이 있어요');
    case 'ARCHIVE_ADDED':
      return _withActor(
        e,
        (actor) => [
          actor,
          ActivitySegment('님이 ${e.targetName ?? '폴더'}에 자료를 추가했어요'),
        ],
      );
    case 'ARCHIVE_LIKE_MILESTONE':
      return _withActor(
        e,
        (actor) => [
          actor,
          ActivitySegment('님 자료에 좋아요 ${e.count ?? 0}개 달성! ❤️'),
        ],
      );
    case 'POKE':
      return _withActor(
        e,
        (actor) => [
          actor,
          ActivitySegment('님이 ${bannerName(e.targetName ?? '')}님을 콕 찔렀어요 👋'),
        ],
      );
    case 'POKE_ACCUMULATED':
      return _withActor(
        e,
        (actor) => [actor, ActivitySegment('님 콕이 ${e.count ?? 0}개 쌓였어요')],
      );
    case 'MEMBER_JOINED':
      return _withActor(
        e,
        (actor) => [actor, const ActivitySegment('님이 방에 들어왔어요')],
      );
    case 'WEEKLY_SUMMARY':
      final diff = e.secondaryCount ?? 0;
      final sign = diff >= 0 ? '+$diff' : '$diff';
      return ActivityMessage.plain('이번 주 완료 ${e.count ?? 0}개 (지난주 $sign) 📈');
    case 'NUDGE_NONE_TODAY':
      // 방 전체가 오늘 하나도 완료 못 한 상태(개인 아님)임을 분명히(2026-08-08 QA).
      return ActivityMessage.plain('오늘 아직 아무도 완료한 사람이 없어요 🥹');
    case 'NUDGE_QUIET_MEMBER':
      return _withActor(
        e,
        (actor) => [actor, ActivitySegment('님이 ${e.count ?? 0}일째 조용해요.. 😓')],
      );
    case 'NUDGE_UNASSIGNED':
      // 방에 담당자 없는 미완료 투두가 있을 때 지정 유도(2026-08-08 QA). 서버가 count>0일 때만 보낸다.
      return ActivityMessage.plain('${e.count ?? 0}개의 투두가 주인을 찾고 있어요! 🙋');
    default:
      // MILESTONE_PROGRESS·DDAY는 프론트가 이미 위에서 파생하므로 서버가 보내도 무시한다
      // (중복 방지, docs/backend/home-activity-feed.md §4). 모르는 타입도 조용히 무시.
      return null;
  }
}

ActivityMessage? _withActor(
  ActivityEvent e,
  List<ActivitySegment> Function(ActivitySegment actorSegment) build,
) {
  final nickname = e.actorNickname;
  if (nickname == null) return null;
  return ActivityMessage(
    build(ActivitySegment(bannerName(nickname), bold: true)),
  );
}

/// 배너에 보이는 닉네임 표시 상한(2026-08-08 QA 확정). 긴 닉네임이 한 줄 롤링 티커를
/// 깨지 않게 **6자까지만** 보이고 넘으면 `…`. 자소(grapheme) 단위로 세서 이모지 닉네임도
/// 안전하게 자른다. 모든 배너 문구의 닉네임(행위자·콕 대상 등)에 공통 적용한다.
@visibleForTesting
String bannerName(String name) {
  const maxChars = 6;
  final chars = name.characters;
  return chars.length > maxChars ? '${chars.take(maxChars)}…' : name;
}

/// 홈 · 내 투두 빈 상태 — 입력필드처럼 보이는 컨테이너.
/// 스펙 44h/#F9FAFB/#E5E8EB/#B0B8C1 → surfaceSoft/borderSoft/mutedSoft·small(8) 매핑.
/// 내 투두 빈 상태 — '+ 투두 추가하기' primary 텍스트 버튼(2026-08-07 요청).
class _TodoEmptyAdd extends StatelessWidget {
  const _TodoEmptyAdd({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Center(
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('투두 추가하기'),
          // 빈 상태는 차분하게 — muted 회색(모아보기 드롭존과 톤 통일). 핑크는 실제 액션에만.
          // 기본 48px 탭 영역을 없애 위아래 여백을 최소화(shrinkWrap + minimumSize zero).
          style: TextButton.styleFrom(
            foregroundColor: AppColors.muted,
            textStyle: AppTypography.bodySmall,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

/// 홈 · 모아보기 빈 상태 — 점선 드롭존 카드(요청 2026-08-06).
/// 스펙 1.5 dashed #CDD0D5/흰 배경/72~80h → borderStrong/surface·small(8) 매핑.
class _ArchiveDropzone extends StatelessWidget {
  const _ArchiveDropzone({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.small),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: CustomPaint(
          painter: const _DashedRRectPainter(
            color: AppColors.border,
            radius: AppRadius.small,
            strokeWidth: 1.5,
          ),
          child: SizedBox(
            height: 84,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, size: 26, color: AppColors.mutedSoft),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '자료를 모아보세요',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
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

/// 둥근 사각형 점선 테두리(Flutter 기본 미지원 → 홈 드롭존 전용 페인터).
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 1.5,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  static const _dashLength = 7.0;
  static const _gapLength = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final source = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashLength;
        dashed.addPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          Offset.zero,
        );
        distance = next + _gapLength;
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;
}

/// "더보기 ›" — 라벨 + 꺽쇠 PNG(muted 틴트). 섹션/박스 헤더 공용(2026-08-07: 텍스트 '>'에서
/// 디자이너 PNG 꺽쇠로 교체).
class _MoreLabel extends StatelessWidget {
  const _MoreLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '더보기',
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(width: AppSpacing.xs),
        // 꺽쇠는 두꺼워서 muted면 텍스트보다 진해 보인다 → mutedSoft로 한 톤 낮춰 톤 맞춤.
        Image.asset(
          'assets/icons/angle_bracket.png',
          width: 8,
          height: 12,
          fit: BoxFit.contain,
          color: AppColors.mutedSoft,
          colorBlendMode: BlendMode.srcIn,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onMore});

  final String title;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTypography.section),
        TextButton(onPressed: onMore, child: const _MoreLabel()),
      ],
    );
  }
}

/// 섹션 박스 — #F7F7F7 + 16px 라운드. 헤더+내용을 함께 담는다(이번주·투두).
/// 멤버 아바타줄 순위 계산(2026-08-08). 진행률 높은 순으로 배치하고 공동
/// 순위(같은 메달)를 매긴다. 위젯 밖 순수 함수라 단위 테스트로 규칙을 고정한다.
///
/// 정렬 키: ① 진행률(%) 내림차순 → ② 완료 개수(assignedDone) 많은 순 → ③ 서버가 준 순서
/// (가입순, 원본 인덱스). Dart `sort`는 안정성을 보장하지 않아 원본 인덱스를 마지막 키로 쓴다.
///
/// 등수: 진행률·완료개수가 **모두 같으면 공동 등수**(같은 메달). 다음 등수는 앞선 인원수만큼
/// 건너뛴다(올림픽식 — 공동 1등 2명이면 은 없이 다음이 3등=동).
///
/// 메달(`medal`)은 `rank <= 3` **이면서 진행률 > 0** 일 때만 준다 — 아무것도 안 한 0%는 상위
/// 등수여도 메달 제외(2026-08-08 사용자 확정: 전원 0%인데 다 금메달이 되는 걸 막는다).
@visibleForTesting
List<({MemberProgress member, int rank, bool medal})> rankMembersByProgress(
  List<MemberProgress> members,
) {
  final indexed = members.indexed.toList()
    ..sort((a, b) {
      final byRatio = b.$2.progressRatio.compareTo(a.$2.progressRatio);
      if (byRatio != 0) return byRatio;
      final byDone = b.$2.assignedDone.compareTo(a.$2.assignedDone);
      if (byDone != 0) return byDone;
      return a.$1.compareTo(b.$1);
    });
  final ordered = [for (final e in indexed) e.$2];
  final result = <({MemberProgress member, int rank, bool medal})>[];
  for (var i = 0; i < ordered.length; i++) {
    int rank;
    if (i == 0) {
      rank = 1;
    } else {
      final prev = ordered[i - 1];
      final cur = ordered[i];
      final tiedWithPrev =
          prev.progressRatio == cur.progressRatio &&
          prev.assignedDone == cur.assignedDone;
      rank = tiedWithPrev ? result[i - 1].rank : i + 1;
    }
    result.add((
      member: ordered[i],
      rank: rank,
      medal: rank <= 3 && ordered[i].progressRatio > 0,
    ));
  }
  return result;
}

/// 멤버 아바타의 순위 메달 배지(상위 3명, 2026-08-08 ).
/// 금·은·동 디자인은 SVG 아트(`assets/icons/icon_badge_medal_*.svg`, 23×30, 사용자 제공)에
/// 담겨 있어 코드로 색·번호를 그리지 않는다. 아바타 우상단에 얹는다.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  static const _asset = <int, String>{
    1: 'assets/icons/icon_badge_medal_gold.svg',
    2: 'assets/icons/icon_badge_medal_silver.svg',
    3: 'assets/icons/icon_badge_medal_bronze.svg',
  };

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(_asset[rank]!, width: 23, height: 30);
  }
}

class _SectionBox extends StatelessWidget {
  const _SectionBox({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// 박스 안 상단 헤더 — 제목(title 16/600) + "더보기 ›"(꺽쇠 PNG). design.md §3 title 토큰.
class _BoxHeader extends StatelessWidget {
  const _BoxHeader({required this.title, required this.onMore});

  final String title;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTypography.title),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onMore,
          child: const _MoreLabel(),
        ),
      ],
    );
  }
}

/// 홈의 오늘 투두 한 줄. **행 전체(체크 원 + 제목 + 오른쪽 빈 공간)가 완료 토글 영역**이다 —
/// 투두 탭으로 가는 길은 섹션 헤더의 "더보기"뿐이다(2026-08-05 요청): 제목을 누르면 탭이
/// 넘어가 버려서, 정작 자주 하는 완료 체크는 22px 원을 정확히 눌러야 했다.
class _TodoRow extends StatelessWidget {
  const _TodoRow({
    super.key,
    required this.todo,
    required this.onToggle,
    this.checked,
  });

  final TodoBrief todo;
  final VoidCallback onToggle;

  /// 대기(2초) 중이면 서버엔 아직 미완료지만 화면엔 체크로 보인다. null이면 todo.completed.
  final bool? checked;

  @override
  Widget build(BuildContext context) {
    final isChecked = checked ?? todo.completed;
    return InkWell(
      onTap: onToggle,
      child: Row(
        children: [
          TodoCheckbox(
            key: ValueKey('todo-checkbox-${todo.id}'),
            checked: isChecked,
            onTap: onToggle,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                todo.title,
                style: AppTypography.title.copyWith(
                  color: isChecked
                      ? AppColors.completedTodo
                      : AppColors.foreground,
                  // 완료 시 엄청 연한 회색 1px 취소선(2026-08-09, 투두탭·멤버투두와 공통).
                  decoration: isChecked ? TextDecoration.lineThrough : null,
                  decorationColor: AppColors.borderSoft,
                  decorationThickness: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
