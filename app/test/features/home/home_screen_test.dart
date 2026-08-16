import 'dart:async';

import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/home/home_api.dart';
import 'package:app/features/home/home_hero.dart';
import 'package:app/features/home/home_screen.dart';
import 'package:app/features/room/no_room_hero.dart';
import 'package:app/features/room/room_api.dart';
import 'package:app/features/room/room_session.dart';
import 'package:app/features/todos/todo_sync.dart';
import 'package:app/features/todos/todos_api.dart'
    show TodoNotAssigneeException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRoomApi extends RoomApi {
  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async {
    return [
      {
        'id': 1,
        'name': '테스트방',
        'goal': '매일 커밋',
        'status': 'ACTIVE',
        'startDate': '2026-01-01',
        'endDate': '2026-12-31',
      },
    ];
  }
}

class _NoActiveRoomApi extends RoomApi {
  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async {
    return [
      {
        'id': 2,
        'name': '종료방',
        'goal': '끝',
        'status': 'ENDED',
        'startDate': '2025-01-01',
        'endDate': '2025-12-31',
      },
    ];
  }
}

class _MultiRoomListApi extends RoomApi {
  _MultiRoomListApi(this.rooms);

  final List<Map<String, dynamic>> rooms;

  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async => rooms;
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({this.currentUserId});

  @override
  Future<String> getIdToken() async => 'fake-token';

  @override
  final String? currentUserId;
}

DashboardData _dashboard({
  String roomName = '테스트방',
  List<TodoBrief> todayTodos = const [],
  List<ArchiveBrief> recentArchives = const [],
  List<ArchiveBrief>? previewArchives,
  int? todoDone,
  int? todoTotal,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DashboardData(
    room: RoomInfo(
      id: 1,
      name: roomName,
      goal: '매일 커밋',
      startDate: today,
      endDate: today.add(const Duration(days: 5)),
      status: 'ACTIVE',
    ),
    members: [
      MemberProgress(
        userId: 'uid-a',
        nickname: '철수',
        assignedTotal: 3,
        assignedDone: 2,
      ),
    ],
    weekSchedules: const [],
    todayTodos: todayTodos,
    recentArchives: recentArchives,
    previewArchives: previewArchives,
    todoDone: todoDone,
    todoTotal: todoTotal,
  );
}

class _FakeHomeApi extends HomeApi {
  _FakeHomeApi({
    DashboardData? dashboard,
    this.throwOnFetch = false,
    Map<int, DashboardData>? dashboardsByRoom,
    this.fetchOverride,
  }) : dashboard = dashboard ?? _dashboard(),
       dashboardsByRoom = dashboardsByRoom ?? {};

  DashboardData dashboard;
  final Map<int, DashboardData> dashboardsByRoom;
  bool throwOnFetch;
  // 담당자 아닌 투두 완료 시도(서버 403, FR-39)를 흉내낸다.
  bool throwNotAssigneeOnComplete = false;
  int fetchCallCount = 0;
  final List<bool> completeCalls = [];
  final Future<DashboardData> Function(int roomId)? fetchOverride;

  @override
  Future<DashboardData> fetchDashboard(
    String idToken,
    int roomId, {
    required DateTime weekStart,
    required DateTime weekEnd,
  }) async {
    fetchCallCount++;
    if (throwOnFetch) {
      throw StateError('네트워크 오류');
    }
    if (fetchOverride != null) return fetchOverride!(roomId);
    return dashboardsByRoom[roomId] ?? dashboard;
  }

  @override
  Future<void> setTodoCompleted(
    String idToken,
    int roomId,
    int todoId,
    bool completed,
  ) async {
    if (throwNotAssigneeOnComplete) {
      throw TodoNotAssigneeException();
    }
    completeCalls.add(completed);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('대시보드 데이터를 불러오면 D-day/멤버/오늘투두/아카이브가 보인다', (tester) async {
    final fakeApi = _FakeHomeApi(
      dashboard: _dashboard(
        todayTodos: [TodoBrief(id: 1, title: '투두1', completed: false)],
        recentArchives: [
          ArchiveBrief(id: 9, title: '자료1', pinned: false, likeCount: 2),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('테스트방'), findsOneWidget);
    expect(find.textContaining('D-'), findsOneWidget);
    expect(find.text('철수'), findsOneWidget);
    expect(find.text('투두1'), findsOneWidget);
    expect(find.text('자료1'), findsOneWidget);
    // 섹션 라벨(타이포 조정 패스)
    expect(find.text('오늘의 현황'), findsOneWidget);
    expect(find.text('이번 주 일정'), findsOneWidget);
    expect(find.text('내 투두'), findsOneWidget);
    expect(find.text('모아보기'), findsOneWidget);
  });

  /// 홈 활동 피드(2026-08-06, docs/backend/home-activity-feed.md)가 실제로 배너에 뜨는지 —
  /// 진행률·D-day를 만들지 않도록 마감이 지난 방을 써서 활동 이벤트가 배너의 첫 문구가 되게 한다.
  testWidgets('대시보드 activities가 있으면 활동 배너에 그 문구가 보인다', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dashboard = DashboardData(
      room: RoomInfo(
        id: 1,
        name: '테스트방',
        goal: '매일 커밋',
        startDate: today.subtract(const Duration(days: 10)),
        endDate: today.subtract(const Duration(days: 1)),
        status: 'ACTIVE',
      ),
      members: const [],
      weekSchedules: const [],
      todayTodos: const [],
      recentArchives: const [],
      activities: [
        ActivityEvent(
          type: 'MEMBER_JOINED',
          actorNickname: '지훈',
          actorUserId: 'uid-jihoon',
          createdAt: DateTime.now(),
        ),
      ],
    );
    final fakeApi = _FakeHomeApi(dashboard: dashboard);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('지훈'), findsOneWidget);
    expect(find.textContaining('방에 들어왔어요'), findsOneWidget);
  });

  testWidgets('빈 상태면 투두는 추가 버튼, 모아보기는 드롭존', (tester) async {
    // _dashboard는 weekSchedules·todayTodos·recentArchives가 모두 비어 3카드 빈 상태.
    final fakeApi = _FakeHomeApi(dashboard: _dashboard(todayTodos: []));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 2026-08-07 요청: 투두 빈 상태는 '+ 투두 추가하기' 버튼(입력필드형 폐기).
    expect(find.text('+ 투두를 입력하세요'), findsNothing);
    expect(find.widgetWithText(TextButton, '투두 추가하기'), findsOneWidget);
    // 모아보기 = 점선 드롭존에 '+' + '자료를 모아보세요'.
    expect(find.text('자료를 모아보세요'), findsOneWidget);
  });

  testWidgets('모아보기 미리보기는 previewArchives(핀 우선)를 우선 쓴다', (tester) async {
    final fakeApi = _FakeHomeApi(
      dashboard: _dashboard(
        recentArchives: [
          ArchiveBrief(id: 1, title: '최신자료', pinned: false, likeCount: 0),
        ],
        previewArchives: [
          ArchiveBrief(id: 2, title: '핀자료', pinned: true, likeCount: 0),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('핀자료'), findsOneWidget);
    expect(find.text('최신자료'), findsNothing);
  });

  testWidgets('previewArchives가 없으면 recentArchives(최신순)로 폴백한다', (tester) async {
    final fakeApi = _FakeHomeApi(
      dashboard: _dashboard(
        recentArchives: [
          ArchiveBrief(id: 1, title: '최신자료', pinned: false, likeCount: 0),
        ],
        // previewArchives 미지정 → 서버 미반영 상황
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('최신자료'), findsOneWidget);
  });

  // ---- 완료 체크는 즉시 서버로 나가고 목록에서 빠진다 (2026-08-07, 기존 2초 되돌리기 폐기) ----

  testWidgets('체크하면 2초간 남아 취소 가능하고, 2초 뒤 서버로 완료가 나간다', (tester) async {
    // 2026-08-09 재도입: 홈도 투두 탭처럼 2초 지연(취소 가능) 후 반영한다.
    final fakeApi = _FakeHomeApi(
      dashboard: _dashboard(
        todayTodos: [TodoBrief(id: 1, title: '지연대상', completed: false)],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final checkbox = find.byKey(const ValueKey('todo-checkbox-1'));
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();

    // 2초 동안은 체크된 채 목록에 남아 되돌릴 수 있다 — 아직 서버로 안 나갔다.
    expect(find.text('지연대상'), findsOneWidget);
    expect(fakeApi.completeCalls, isEmpty);

    // 2초가 지나면 서버로 완료가 나가고 목록에서 빠진다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('지연대상'), findsNothing);
    expect(fakeApi.completeCalls, [true]);
  });

  testWidgets('체크박스를 탭하면 즉시 완료 처리되고 API가 호출된다', (tester) async {
    final fakeApi = _FakeHomeApi(
      dashboard: _dashboard(
        todayTodos: [TodoBrief(id: 1, title: '투두1', completed: false)],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('투두1'), findsOneWidget);

    // 히어로가 커져 오늘투두가 접힘 아래에 있을 수 있어 먼저 노출시킨다.
    final checkbox = find.byKey(const ValueKey('todo-checkbox-1'));
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    // 완료는 2초 뒤에 서버로 나간다(요청 3) — 그 시간을 보내야 실제 커밋된다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // 체크하면 완료 처리되고 '내 투두'(미완료) 목록에서 사라진다.
    expect(fakeApi.completeCalls, [true]);
    expect(find.text('투두1'), findsNothing);
  });

  testWidgets('담당자 아닌 투두 완료 시 담당자 전용 안내가 뜨고 토글이 롤백된다', (tester) async {
    final fakeApi = _FakeHomeApi(
      dashboard: _dashboard(
        todayTodos: [TodoBrief(id: 1, title: '투두1', completed: false)],
      ),
    )..throwNotAssigneeOnComplete = true;

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final checkbox = find.byKey(const ValueKey('todo-checkbox-1'));
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    // 완료는 2초 뒤에 서버로 나간다(요청 3) — 그 시간을 보내야 실제 커밋된다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // FR-39: 일반 실패 문구가 아니라 담당자 전용 안내가 보여야 한다.
    expect(find.text(TodoNotAssigneeException.defaultMessage), findsOneWidget);
    expect(find.text('완료 처리에 실패했어요. 다시 시도해 주세요'), findsNothing);
    // 낙관적 토글이 롤백되어 투두가 목록에 그대로 남는다.
    expect(find.text('투두1'), findsOneWidget);
  });

  testWidgets('방 전체 진행률이 있으면 히어로에 진행률 바와 완료/전체 개수가 보인다', (tester) async {
    final fakeApi = _FakeHomeApi(
      dashboard: _dashboard(todoDone: 24, todoTotal: 40),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('함께 달성한 투두'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('백엔드 진행률이 없으면 멤버 담당 합산 근사치로 진행률 바를 보여준다', (tester) async {
    // 기본 대시보드: 멤버 1명(담당 3 중 2 완료), todoDone/todoTotal 없음.
    final fakeApi = _FakeHomeApi(dashboard: _dashboard());

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('함께 달성한 투두'), findsOneWidget);
    expect(find.text('67%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  /// S-06 방없음 상태 — 종료된 방만 가진 사용자가 홈에 오면 S-03 과 **같은 히어로**가 뜬다
  /// (specs/0004-방-생성-참여.md). 2026-08-16 이전에는 맨 텍스트 + OutlinedButton "코드 입력"
  /// 이라는 임시 화면이었다.
  testWidgets('진행 중인 방이 없으면 S-06 히어로와 CTA 2종이 보인다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _FakeHomeApi(),
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _NoActiveRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NoRoomHero), findsOneWidget);
    expect(find.byIcon(Icons.card_giftcard), findsOneWidget);
    expect(find.text('팀과 함께할 방을 만들거나, 초대코드로 참여하세요'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '방 만들기'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '초대코드로 참여하기'), findsOneWidget);

    // 🔴 S-03 과 갈리는 지점 — 홈에 도달했다는 건 방을 가졌다는 뜻이라 타이틀이 고정이다.
    // SharedPreferences 가 비어 있어도(기기 교체 등) "첫 번째 방을…" 이 뜨면 안 된다.
    expect(find.text('현재 진행 중인 방이 없어요!'), findsOneWidget);
    expect(find.text('첫 번째 방을 만들어볼까요?'), findsNothing);

    // S-06 에는 방 전환 트리거(방이름▾)가 없다 — specs/0008-방-전환.md.
    expect(find.byType(HomeHero), findsNothing);
  });

  /// 🔴 조용한 새로고침(silent)의 실패는 `_errorText` 를 채우지 않는다. 그 상태를
  /// `_roomId == null` 로 판단하면 **네트워크 오류가 "방이 없어요" 로 둔갑한다.**
  /// 방 목록을 실제로 읽어서 ACTIVE가 없다고 확인했을 때만 S-06 이어야 한다.
  testWidgets('조용한 새로고침이 실패한 것을 S-06 방없음으로 오인하지 않는다', (tester) async {
    final sync = TodoSync();
    final fakeApi = _FakeHomeApi(throwOnFetch: true);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          todoSync: sync,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 여기까지는 첫 로드(비-silent) 실패라 _errorText 분기가 잡는다.

    // 🔴 이 신호가 silent 재조회를 돌린다. _load()가 시작하며 _errorText 를 비우는데
    // silent 라 다시 채우지 않는다 → _errorText·_roomId·_data 가 전부 null 인 구간.
    // `_roomId == null` 로 S-06 을 판단하면 여기서 "방이 없어요" 가 뜬다.
    sync.markChanged();
    await tester.pumpAndSettle();

    expect(find.byType(NoRoomHero), findsNothing);
    expect(find.text('현재 진행 중인 방이 없어요!'), findsNothing);
    expect(find.text('홈 정보를 불러오지 못했어요'), findsOneWidget);
  });

  testWidgets('진행 중인 방이 있으면 S-06 히어로가 뜨지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: _FakeHomeApi(dashboard: _dashboard()),
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NoRoomHero), findsNothing);
  });

  testWidgets('로드 실패 시 에러 안내와 재시도 버튼이 보이고, 재시도하면 다시 호출한다', (tester) async {
    final fakeApi = _FakeHomeApi(throwOnFetch: true);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('홈 정보를 불러오지 못했어요'), findsOneWidget);
    expect(fakeApi.fetchCallCount, 1);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(fakeApi.fetchCallCount, 2);
  });

  testWidgets('방이름을 탭해 다른 진행중 방으로 전환하면 대시보드가 새 방으로 갱신된다', (tester) async {
    final fakeApi = _FakeHomeApi(
      dashboardsByRoom: {
        1: _dashboard(roomName: '방A'),
        2: _dashboard(roomName: '방B'),
      },
    );
    final roomSession = RoomSession(
      roomApi: _MultiRoomListApi([
        {
          'id': 1,
          'name': '방A',
          'goal': '목표A',
          'status': 'ACTIVE',
          'startDate': '2026-01-01',
          'endDate': '2026-12-31',
        },
        {
          'id': 2,
          'name': '방B',
          'goal': '목표B',
          'status': 'ACTIVE',
          'startDate': '2026-01-01',
          'endDate': '2026-12-31',
        },
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: roomSession,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('방A'), findsOneWidget);

    await tester.tap(find.text('방A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('room-switch-2')));
    await tester.pumpAndSettle();

    expect(find.text('방B'), findsOneWidget);
  });

  testWidgets('마지막으로 본 방이 종료됐으면 다른 방으로 자동 전환되고 안내가 뜬다', (tester) async {
    SharedPreferences.setMockInitialValues({'last_viewed_room_id': 1});
    final fakeApi = _FakeHomeApi(
      dashboardsByRoom: {2: _dashboard(roomName: '방B')},
    );
    final roomSession = RoomSession(
      roomApi: _MultiRoomListApi([
        {
          'id': 1,
          'name': '끝난방',
          'goal': '끝',
          'status': 'ENDED',
          'startDate': '2025-01-01',
          'endDate': '2025-12-31',
        },
        {
          'id': 2,
          'name': '방B',
          'goal': '목표B',
          'status': 'ACTIVE',
          'startDate': '2026-01-01',
          'endDate': '2026-12-31',
        },
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: roomSession,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('방B'), findsOneWidget);
    expect(find.textContaining('종료되어'), findsOneWidget);
  });

  testWidgets('늦게 도착한 이전 방의 응답이 이미 전환된 최신 방 화면을 덮어쓰지 않는다', (tester) async {
    final room1Completer = Completer<DashboardData>();
    final fakeApi = _FakeHomeApi(
      fetchOverride: (roomId) {
        if (roomId == 1) return room1Completer.future;
        return Future.value(_dashboard(roomName: '방B'));
      },
    );
    final roomSession = RoomSession(
      roomApi: _MultiRoomListApi([
        {
          'id': 1,
          'name': '방A',
          'goal': '목표A',
          'status': 'ACTIVE',
          'startDate': '2026-01-01',
          'endDate': '2026-12-31',
        },
        {
          'id': 2,
          'name': '방B',
          'goal': '목표B',
          'status': 'ACTIVE',
          'startDate': '2026-01-01',
          'endDate': '2026-12-31',
        },
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: roomSession,
        ),
      ),
    );
    await tester.pump();

    // 방1의 fetchDashboard가 completer로 막혀 있어 첫 _load()가 아직 끝나지 않은 상태.
    expect(fakeApi.fetchCallCount, 1);
    expect(find.text('방A'), findsNothing);
    expect(find.text('방B'), findsNothing);

    // 사용자가 방2로 전환 — 두 번째 _load()가 트리거되고 그 fetchDashboard는 즉시 resolve된다.
    await roomSession.switchRoom(2);
    await tester.pumpAndSettle();

    expect(find.text('방B'), findsOneWidget);

    // 이제서야 방1의 오래된 응답이 도착해도 화면은 여전히 방B여야 한다(경쟁 상태 방지).
    room1Completer.complete(_dashboard(roomName: '방A'));
    await tester.pumpAndSettle();

    expect(find.text('방B'), findsOneWidget);
    expect(find.text('방A'), findsNothing);
  });

  // ---- 홈↔투두 실시간 반영 ----

  testWidgets('홈에서 오늘투두를 체크하면 TodoSync에 변경을 알린다', (tester) async {
    final sync = TodoSync();
    var notified = 0;
    sync.addListener(() => notified++);
    final fakeApi = _FakeHomeApi(
      dashboard: _dashboard(
        todayTodos: [TodoBrief(id: 1, title: '투두1', completed: false)],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          todoSync: sync,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final checkbox = find.byKey(const ValueKey('todo-checkbox-1'));
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    // 완료는 2초 뒤에 서버로 나간다(요청 3) — 그 시간을 보내야 실제 커밋된다.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(fakeApi.completeCalls, [true]);
    expect(notified, greaterThanOrEqualTo(1));
  });

  testWidgets('외부 TodoSync 신호가 오면 대시보드를 다시 불러온다', (tester) async {
    final sync = TodoSync();
    final fakeApi = _FakeHomeApi();

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          todoSync: sync,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = fakeApi.fetchCallCount;
    sync.markChanged(); // 투두 탭에서 완료를 바꾼 상황
    await tester.pumpAndSettle();

    expect(fakeApi.fetchCallCount, before + 1); // 대시보드 리로드
  });

  group('멤버 아바타 탭 — 2026-08-04 정정(specs/0005-홈-대시보드.md)', () {
    // '/home'(HomeScreen 실물) + '/todos'(플레이스홀더) 셸과, 셸 밖 '/member/:userId'
    // (플레이스홀더)을 실제 go_router로 구성해 어느 목적지로 갔는지를 직접 확인한다.
    Widget shellApp({required String? currentUserId, HomeApi? api}) {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) => navigationShell,
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/home',
                    builder: (context, state) => HomeScreen(
                      api: api ?? _FakeHomeApi(),
                      authService: _FakeAuthService(
                        currentUserId: currentUserId,
                      ),
                      roomSession: RoomSession(roomApi: _FakeRoomApi()),
                    ),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/todos',
                    builder: (context, state) => const Text('TODOS_TAB'),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/member/:userId',
            builder: (context, state) =>
                Text('MEMBER_TODOS_${state.pathParameters['userId']}'),
          ),
        ],
      );
      return MaterialApp.router(routerConfig: router);
    }

    testWidgets('본인 아바타를 탭하면 멤버 투두가 아니라 투두 탭으로 전환된다', (tester) async {
      // _dashboard()의 유일한 멤버는 userId: 'uid-a' — 로그인 유저와 동일하게 맞춘다.
      await tester.pumpWidget(shellApp(currentUserId: 'uid-a'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('철수(나)'));
      await tester.pumpAndSettle();

      expect(find.text('TODOS_TAB'), findsOneWidget);
      expect(find.text('MEMBER_TODOS_uid-a'), findsNothing);
    });

    testWidgets('다른 멤버 아바타를 탭하면 그대로 멤버 투두 화면으로 이동한다', (tester) async {
      await tester.pumpWidget(shellApp(currentUserId: 'uid-someone-else'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('철수'));
      await tester.pumpAndSettle();

      expect(find.text('MEMBER_TODOS_uid-a'), findsOneWidget);
      expect(find.text('TODOS_TAB'), findsNothing);
    });

    // ---- 오늘 투두 행: 제목을 눌러도 완료 토글 (2026-08-05 요청 1) ----

    testWidgets('투두 제목을 탭하면 투두 탭으로 가지 않고 완료 토글된다', (tester) async {
      final fakeApi = _FakeHomeApi(
        dashboard: _dashboard(
          todayTodos: [TodoBrief(id: 1, title: '제목탭대상', completed: false)],
        ),
      );
      await tester.pumpWidget(shellApp(currentUserId: 'uid-a', api: fakeApi));
      await tester.pumpAndSettle();

      final title = find.text('제목탭대상');
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      await tester.tap(title);
      await tester.pumpAndSettle();

      expect(find.text('TODOS_TAB'), findsNothing, reason: '제목 탭은 이동이 아니다');
      // 2026-08-09: 체크는 2초 지연(취소 가능) 후 반영 — 2초 뒤 서버로 나가고 목록에서 빠진다.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('제목탭대상'), findsNothing);
      expect(fakeApi.completeCalls, [true]);
    });

    testWidgets('제목 오른쪽 빈 공간을 눌러도 완료 토글된다', (tester) async {
      final fakeApi = _FakeHomeApi(
        dashboard: _dashboard(
          todayTodos: [TodoBrief(id: 1, title: '짧음', completed: false)],
        ),
      );
      await tester.pumpWidget(shellApp(currentUserId: 'uid-a', api: fakeApi));
      await tester.pumpAndSettle();

      // 행 오른쪽 끝(제목 글자 밖) — 넓힌 히트박스가 여기까지 닿아야 한다.
      final rowFinder = find.byKey(const ValueKey('todo-row-1'));
      await tester.ensureVisible(rowFinder);
      await tester.pumpAndSettle();
      final row = tester.getRect(rowFinder);
      await tester.tapAt(Offset(row.right - 8, row.center.dy));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(fakeApi.completeCalls, [true]);
      expect(find.text('TODOS_TAB'), findsNothing);
    });

    testWidgets('"더보기"를 눌렀을 때만 투두 탭으로 간다', (tester) async {
      await tester.pumpWidget(shellApp(currentUserId: 'uid-a'));
      await tester.pumpAndSettle();

      // '더보기'는 모아보기 섹션에도 있다 — '내 투두' 헤더 안의 것으로 정확히 집는다.
      final more = find.descendant(
        of: find
            .ancestor(of: find.text('내 투두'), matching: find.byType(Row))
            .first,
        matching: find.text('더보기'),
      );
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();

      expect(find.text('TODOS_TAB'), findsOneWidget);
    });
  });
}
