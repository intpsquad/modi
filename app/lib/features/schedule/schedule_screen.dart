import 'package:flutter/material.dart';

import '../../design/empty_state.dart';
import '../../design/tokens.dart';
import '../../design/tab_header.dart';
import '../auth/auth_service.dart';
import '../room/room_session.dart';
import '../shell/app_shell.dart';
import '../shell/tab_activation.dart';
import 'holiday_card.dart';
import 'korean_holidays.dart';
import 'schedule_api.dart';
import 'schedule_form_sheet.dart';
import 'schedule_time_format.dart';

/// S-20 일정 탭 — specs/0009-일정-탭.md. 월간 그리드 + 선택한 날짜의 일정 리스트.
class ScheduleScreen extends StatefulWidget {
  ScheduleScreen({
    super.key,
    ScheduleApi? api,
    AuthService? authService,
    RoomSession? roomSession,
    TabActivation? tabActivation,
    this.today,
  }) : api = api ?? ScheduleApi(),
       authService = authService ?? AuthService(),
       roomSession = roomSession ?? appRoomSession,
       tabActivation = tabActivation ?? appTabActivation;

  final ScheduleApi api;
  final AuthService authService;
  final RoomSession roomSession;
  final TabActivation tabActivation;

  /// 오늘 날짜 고정용 — 앱에서는 항상 null이라 `DateTime.now()`를 쓰고, 테스트만 특정 달을
  /// 넣는다. 공휴일·일요일 색은 달력의 실제 날짜에 달려 있어, 시계를 붙잡지 못하면
  /// "12월 25일이 빨갛다"를 검증할 수 없다(todo_form_sheet.dart와 같은 패턴).
  ///
  /// 한 테스트 안에서 이 값을 바꿔 다시 pump하려면 **서로 다른 `key`를 달아라** — State가
  /// 재사용되면 `_visibleMonth`/`_selectedDate`는 initState 때 잡은 옛 날짜로 남는데
  /// `_today`만 새 값을 돌려줘 조용히 어긋난다(didUpdateWidget을 두지 않았다).
  @visibleForTesting
  final DateTime? today;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  bool _loading = true;

  /// 한 번이라도 그리드를 그린 뒤인가 — 그 뒤로는 재조회에 전체 스피너를 쓰지 않는다(요청 6).
  bool _loadedOnce = false;
  String? _errorText;
  int? _roomId;
  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  List<ScheduleItem> _monthSchedules = [];

  /// 이 화면이 "오늘"로 보는 날짜. 테스트가 `today`를 넣으면 그 날로 고정된다.
  DateTime get _today => _dateOnly(widget.today ?? DateTime.now());

  // 방 전환 등으로 조회가 겹쳐 호출될 때 먼저 시작한 요청이 나중 요청 결과를 덮어쓰지 않도록 막는 가드.
  int _loadGeneration = 0;

  static DateTime _monthOf(DateTime date) => DateTime(date.year, date.month, 1);
  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  List<ScheduleItem> get _selectedDateSchedules {
    final list = _monthSchedules
        .where((s) => s.coversDate(_selectedDate))
        .toList();
    // 종일(time=null) 먼저, 그 뒤 time 오름차순(specs/0009 §데이터). time은
    // "HH:mm:ss" 원문이라 사전식 비교가 곧 시간순이다.
    list.sort((a, b) {
      if (a.time == null && b.time == null) return 0;
      if (a.time == null) return -1;
      if (b.time == null) return 1;
      return a.time!.compareTo(b.time!);
    });
    return list;
  }

  /// 목록 스크롤 — 일정 탭을 (재)탭하면 맨 위로 되돌리는 데 쓴다(2026-08-10).
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // `widget`을 읽어야 해서 필드 초기화식이 아니라 여기서 잡는다.
    _visibleMonth = _monthOf(_today);
    _selectedDate = _today;
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

  /// 일정 탭이 다시 켜지면 조용히 최신 상태로 맞춘다(요청 1).
  void _onTabChanged() {
    if (!mounted) return;
    if (widget.tabActivation.index == AppShell.scheduleIndex) {
      _load(silent: true);
    }
  }

  /// 일정 탭을 누를 때마다(전환·재탭) 맨 위로 부드럽게 스크롤한다(2026-08-10 요청).
  void _onTabReselected() {
    if (!mounted) return;
    if (widget.tabActivation.reselect.index != AppShell.scheduleIndex) return;
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
      await _fetchMonthSchedules(silent: silent);
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorText = '일정을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  // 전체 화면 스피너는 첫 로드에만 쓴다 — 그 뒤(월 이동·당겨서 새로고침·일정 추가 후 재조회)
  // 는 기존 그리드를 유지한 채 조회하고 결과가 오면 갈아끼운다(요청 6).
  Future<void> _fetchMonthSchedules({bool silent = false}) async {
    final roomId = _roomId;
    if (roomId == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      if (!silent && !_loadedOnce) _loading = true;
      _errorText = null;
    });
    try {
      final idToken = await widget.authService.getIdToken();
      final monthStart = _visibleMonth;
      final monthEnd = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0);
      final schedules = await widget.api.fetchSchedules(
        idToken,
        roomId,
        start: monthStart,
        end: monthEnd,
      );
      // 이 요청이 진행되는 동안 더 최신 조회가 시작됐다면 이 결과는 버린다(오래된 응답이
      // 나중에 도착해 최신 상태를 덮어쓰는 경쟁 상태 방지).
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _monthSchedules = schedules;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorText = '일정을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  Future<void> _changeMonth(int delta) async {
    final newMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + delta,
      1,
    );
    // 새 달로 넘어가면 선택일도 그 달로 옮긴다(선택 = 유일한 채운 원이라
    // 안 옮기면 새 달에 강조가 사라지고 하단 헤더가 이전 달 날짜로 남는다).
    final today = _today;
    final newSelected =
        (today.year == newMonth.year && today.month == newMonth.month)
        ? today
        : newMonth;
    setState(() {
      _visibleMonth = newMonth;
      _selectedDate = newSelected;
      _monthSchedules = []; // 이전 달 점이 새 달 위에 잠깐 남지 않게 비운다.
    });
    await _fetchMonthSchedules(silent: true);
  }

  void _selectDate(DateTime date) {
    setState(() => _selectedDate = date);
  }

  Future<void> _openCreateSheet() async {
    final roomId = _roomId;
    if (roomId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
      isScrollControlled: true,
      builder: (context) => ScheduleFormSheet(
        date: _selectedDate,
        onSubmit:
            ({
              required title,
              required date,
              time,
              endDate,
              endTime,
              detail,
              place,
            }) async {
              final idToken = await widget.authService.getIdToken();
              await widget.api.createSchedule(
                idToken,
                roomId,
                title: title,
                date: date,
                time: time,
                endDate: endDate,
                endTime: endTime,
                detail: detail,
                place: place,
              );
            },
      ),
    );
    await _fetchMonthSchedules();
  }

  Future<void> _openEditSheet(ScheduleItem schedule) async {
    final roomId = _roomId;
    if (roomId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
      isScrollControlled: true,
      builder: (context) => ScheduleFormSheet(
        date: schedule.date,
        initial: schedule,
        onSubmit:
            ({
              required title,
              required date,
              time,
              endDate,
              endTime,
              detail,
              place,
            }) async {
              final idToken = await widget.authService.getIdToken();
              await widget.api.updateSchedule(
                idToken,
                roomId,
                schedule.id,
                title: title,
                date: date,
                time: time,
                endDate: endDate,
                endTime: endTime,
                detail: detail,
                place: place,
              );
            },
        onDelete: () async {
          final idToken = await widget.authService.getIdToken();
          await widget.api.deleteSchedule(idToken, roomId, schedule.id);
        },
      ),
    );
    await _fetchMonthSchedules();
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
            Text('일정을 불러오고 있어요', style: AppTypography.bodySmall),
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
      onRefresh: () => _fetchMonthSchedules(silent: true),
      color: AppColors.primary,
      child: ListView(
        controller: _scrollController,
        // 헤더는 투두·마이페이지처럼 상단 flush로 둔다 — 위 패딩을 주면 4개 탭 제목의
        // 세로 위치가 어긋난다(2026-08-08 QA). 아래 여백만 유지.
        padding: const EdgeInsets.only(bottom: AppSpacing.content),
        children: [
          _buildTopBar(),
          const SizedBox(height: AppSpacing.content),
          _buildMonthHeader(),
          const SizedBox(height: AppSpacing.cardGap),
          _buildMonthGrid(),
          const SizedBox(height: AppSpacing.content),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpacing.content),
          _buildDayList(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return TabHeader(
      title: '일정',
      action: IconButton(
        onPressed: _openCreateSheet,
        icon: const Icon(Icons.add, color: AppColors.primary),
        tooltip: '일정 추가',
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left, color: AppColors.foreground),
          ),
          Text(
            '${_visibleMonth.year}년 ${_visibleMonth.month}월',
            style: AppTypography.title,
          ),
          IconButton(
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_right, color: AppColors.foreground),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthGrid() {
    final monthStart = _visibleMonth;
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    // 일요일 시작(목업). Dart weekday는 월=1…일=7 → %7 로 일=0 앞칸 계산.
    final leadingBlanks = monthStart.weekday % 7;
    // 다중일 일정은 구간에 속한 모든 날짜에 점을 찍는다(2026-08-04, 이어주는
    // 선 없이 날짜마다 점만 — 사용자 확정, specs/OPEN.md).
    final scheduleDates = <DateTime>{};
    for (final s in _monthSchedules) {
      final start = _dateOnly(s.date);
      final end = _dateOnly(s.endDate ?? s.date);
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        scheduleDates.add(d);
      }
    }
    final todayDate = _today;

    final cells = <DateTime?>[
      for (var i = 0; i < leadingBlanks; i++) null,
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(_visibleMonth.year, _visibleMonth.month, d),
    ];
    // 7일씩 주(week) 행으로 나눈다 — home_screen.dart의 _WeekCalendar와 동일하게 Row를
    // 이어붙이는 방식을 쓴다(GridView.count는 정사각형 비율 탓에 셀이 과도하게 커진다).
    final weeks = <List<DateTime?>>[];
    for (var i = 0; i < cells.length; i += 7) {
      final end = (i + 7 <= cells.length) ? i + 7 : cells.length;
      final week = cells.sublist(i, end);
      weeks.add([...week, for (var p = week.length; p < 7; p++) null]);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
      child: Column(
        children: [
          const _WeekdayHeader(),
          const SizedBox(height: AppSpacing.xs),
          for (final week in weeks)
            Row(
              children: [
                for (final cell in week)
                  Expanded(
                    child: cell == null
                        ? const SizedBox(height: 44)
                        : _DayCell(
                            key: ValueKey('schedule-cell-${_formatIso(cell)}'),
                            day: cell.day,
                            isToday: cell == todayDate,
                            isSelected: cell == _selectedDate,
                            // 일요일 판정은 공휴일 표와 무관하게 항상 동작한다 —
                            // 표에 없는 연도로 넘어가도 일요일은 계속 빨갛다.
                            isHoliday:
                                cell.weekday == DateTime.sunday ||
                                KoreanHolidays.isHoliday(cell),
                            hasSchedule: scheduleDates.contains(cell),
                            onTap: () => _selectDate(cell),
                          ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDayList() {
    final isToday = _selectedDate == _today;
    final headerText = isToday
        ? '오늘 일정'
        : '${_selectedDate.month}월 ${_selectedDate.day}일 일정';
    final schedules = _selectedDateSchedules;
    // 공휴일이면 목록 맨 위에 읽기전용 공휴일 항목을 일정처럼 보여준다.
    final holidayName = KoreanHolidays.nameOf(_selectedDate);
    final listItems = <Widget>[
      if (holidayName != null) HolidayCard(name: holidayName),
      for (final schedule in schedules)
        _ScheduleCard(
          key: ValueKey('schedule-card-${schedule.id}'),
          schedule: schedule,
          onTap: () => _openEditSheet(schedule),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.content),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(headerText, style: AppTypography.section),
              Text(
                '${_selectedDate.month}월 ${_selectedDate.day}일 '
                '(${_weekdayLabel(_selectedDate)})',
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.cardGap),
          if (listItems.isEmpty)
            // 추가 버튼이 우상단(+)에 따로 있어, 여기선 안내 문구만(요청 2026-08-06).
            const EmptyState(message: '일정이 없어요')
          else
            // 간격은 카드 "사이"에만 둔다 — Figma 리스트가 세로 오토레이아웃 간격 8·패딩 0이라
            // 마지막 카드 뒤에는 여백이 없다(예전엔 카드가 스스로 bottom 패딩을 달고 있었다).
            // `Column.spacing`이 그 규칙을 코드로 직접 드러낸다.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.sm,
              children: listItems,
            ),
        ],
      ),
    );
  }

  static const _weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];

  String _weekdayLabel(DateTime date) => _weekdayLabels[date.weekday % 7];

  String _formatIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  // 일요일 시작(목업). 일요일 라벨만 accent-danger 강조 — 아래 날짜 셀의 휴일 색과 같은 색이라
  // 헤더와 날짜가 한 덩어리로 읽힌다(2026-08-07 사용자 확정, 종전 primary에서 변경).
  static const _labels = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++)
          Expanded(
            child: Center(
              child: Text(
                _labels[i],
                style: AppTypography.caption.copyWith(
                  color: i == 0 ? AppColors.accentDanger : AppColors.muted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isHoliday,
    required this.hasSchedule,
    required this.onTap,
  });

  final int day;
  final bool isToday;
  final bool isSelected;

  /// 일요일이거나 관공서 공휴일 — 둘을 색으로 구분하지 않는다(달력 관행).
  final bool isHoliday;
  final bool hasSchedule;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 선택일 = primary 채운 원(목업). 오늘(비선택) = primary 텍스트로 구분.
    // 휴일은 그 아래 순위다 — 선택·오늘은 사용자가 지금 조작 중인 상태라 날짜 속성보다 앞선다.
    final Color textColor = isSelected
        ? AppColors.onPrimary
        : isToday
        ? AppColors.primary
        : isHoliday
        ? AppColors.accentDanger
        : AppColors.foreground;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      // 빈 칸(SizedBox height 44, design.md §189 터치영역)과 같은 높이로 고정해
      // 첫/마지막 주 행만 커지는 것을 막는다.
      child: SizedBox(
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
              ),
              child: Text(
                '$day',
                style: AppTypography.bodySmall.copyWith(
                  color: textColor,
                  fontWeight: (isSelected || isToday)
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            SizedBox(
              width: AppSpacing.xs,
              height: AppSpacing.xs,
              child: hasSchedule
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // 원 아래 흰 배경 위의 연분홍 이벤트 점(목업).
                        color: AppColors.primary.withValues(alpha: 0.45),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 오늘 일정 카드 — 흰 배경 + 좌측 세로 컬러 바 + 제목 + (시간 · 장소) 부제.
///
/// 치수는 2026-08-07 Figma 오토레이아웃 실측값이다. 카드 높이 58은 설정값이 아니라
/// `패딩 10 + (제목 20 + 2 + 부제 16) + 패딩 10`으로 **파생**되므로, 타이포를 바꾸면 같이 움직인다.
///
/// ⚠️ 10·3·34·2는 `specs/design.md`의 4px 스케일 밖 값이다(12·8만 토큰). 디자이너 확정값이라
/// 그대로 반영하되 정식화 여부는 `specs/OPEN.md` 미결 — 임의로 토큰에 맞춰 반올림하지 말 것.
class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({super.key, required this.schedule, required this.onTap});

  /// 좌측 세로 컬러 바 — Figma 3×34, 반경 2. 카드 높이를 채우지 않고 세로 중앙에 고정된다.
  static const _barWidth = 3.0;
  static const _barHeight = 34.0;
  static const _barRadius = 2.0;

  /// 카드 세로 패딩(가로는 `AppSpacing.md`=12)과 바↔텍스트 간격. 둘 다 Figma 값.
  static const _paddingVertical = 10.0;
  static const _barGap = 10.0;

  /// 헤어라인 두께. **패딩에서 이만큼 뺀다** — Figma의 "내부(inside)" 스트로크는 프레임 크기를
  /// 늘리지 않고 패딩 영역 위에 겹쳐 그려지는데, Flutter의 `BoxDecoration.border`는 자식을
  /// 그만큼 안쪽으로 밀어낸다. 그대로 두면 카드가 58이 아니라 60이 되고 바의 x도 12가 아닌 13이 된다.
  ///
  /// ⚠️ **테두리와 패딩이 이 값으로 묶여 있다** — 테두리를 없애면 패딩도 12/10으로 되돌려야 한다
  /// (안 그러면 11/9가 조용히 남는다). `strokeAlignOutside`는 대안이 아니다: 자식은 안 밀지만
  /// 테두리를 박스 바깥에 그려 실제 페인트 크기가 60이 된다.
  static const _borderWidth = 1.0;

  final ScheduleItem schedule;
  final VoidCallback onTap;

  /// 다중일이면 "M월 D일 - M월 D일", 단일일이면 null(부제에서 생략).
  String? get _dateRangeLabel {
    final endDate = schedule.endDate;
    if (endDate == null) return null;
    return '${schedule.date.month}월 ${schedule.date.day}일 - '
        '${endDate.month}월 ${endDate.day}일';
  }

  /// 종료 시간이 있으면 "오전 10:00 - 오후 12:00" 범위, 없으면 시작 시간만
  /// 단일 표기. 초는 절대 표시하지 않는다.
  String? get _timeRangeLabel {
    final start = formatServerTimeKorean(schedule.time);
    if (start == null) return null;
    final end = formatServerTimeKorean(schedule.endTime);
    return end == null ? start : '$start - $end';
  }

  String? get _subtitle {
    final place = schedule.place?.trim();
    final parts = <String>[
      ?_dateRangeLabel,
      ?_timeRangeLabel,
      if (place != null && place.isNotEmpty) place,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        // 클립 없음 — 바가 3×34로 패딩 안에 완전히 들어와 라운드 코너에 걸릴 자식이 없다
        // (풀 하이트 띠였을 땐 필요했다).
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border, width: _borderWidth),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md - _borderWidth,
          vertical: _paddingVertical - _borderWidth,
        ),
        child: Row(
          children: [
            Container(
              width: _barWidth,
              height: _barHeight,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(_barRadius),
              ),
            ),
            const SizedBox(width: _barGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule.title,
                    style: AppTypography.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    // caption(13/16) — 부제 높이 16이 Figma 실측값이고, 카드 58이 여기서 나온다.
                    // 토큰 기본 색이 이미 muted라 copyWith 불필요.
                    Text(
                      subtitle,
                      style: AppTypography.caption,
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
