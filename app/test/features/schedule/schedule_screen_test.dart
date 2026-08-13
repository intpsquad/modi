import 'package:app/design/tokens.dart';
import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/room/room_api.dart';
import 'package:app/features/room/room_session.dart';
import 'package:app/features/schedule/schedule_api.dart';
import 'package:app/features/schedule/schedule_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRoomApi extends RoomApi {
  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async {
    return [
      {
        'id': 1,
        'name': '테스트방',
        'goal': '목표',
        'status': 'ACTIVE',
        'startDate': '2026-01-01',
        'endDate': '2026-12-31',
      },
    ];
  }
}

class _NoActiveRoomApi extends RoomApi {
  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async => [];
}

class _FakeAuthService extends AuthService {
  @override
  Future<String> getIdToken() async => 'fake-token';
}

class _FakeScheduleApi extends ScheduleApi {
  _FakeScheduleApi({List<ScheduleItem>? schedules, this.throwOnFetch = false})
    : schedules = schedules ?? [];

  List<ScheduleItem> schedules;
  bool throwOnFetch;
  int fetchCallCount = 0;
  final List<String> createTitles = [];
  final List<int> deleteCalls = [];

  @override
  Future<List<ScheduleItem>> fetchSchedules(
    String idToken,
    int roomId, {
    required DateTime start,
    required DateTime end,
  }) async {
    fetchCallCount++;
    if (throwOnFetch) throw StateError('network');
    // 서버와 동일한 구간 겹침 기준(findOverlappingByRoomId)으로 필터링한다.
    return schedules
        .where(
          (s) => !s.date.isAfter(end) && !(s.endDate ?? s.date).isBefore(start),
        )
        .toList();
  }

  final List<String?> createPlaces = [];
  final List<DateTime?> createEndDates = [];
  final List<String?> createEndTimes = [];

  @override
  Future<ScheduleItem> createSchedule(
    String idToken,
    int roomId, {
    required String title,
    required DateTime date,
    String? time,
    DateTime? endDate,
    String? endTime,
    String? detail,
    String? place,
  }) async {
    createTitles.add(title);
    createPlaces.add(place);
    createEndDates.add(endDate);
    createEndTimes.add(endTime);
    final created = ScheduleItem(
      id: schedules.length + 100,
      title: title,
      date: date,
      time: time,
      endDate: endDate,
      endTime: endTime,
      detail: detail,
      place: place,
    );
    schedules = [...schedules, created];
    return created;
  }

  @override
  Future<ScheduleItem> updateSchedule(
    String idToken,
    int roomId,
    int scheduleId, {
    required String title,
    required DateTime date,
    String? time,
    DateTime? endDate,
    String? endTime,
    String? detail,
    String? place,
  }) async {
    final updated = ScheduleItem(
      id: scheduleId,
      title: title,
      date: date,
      time: time,
      endDate: endDate,
      endTime: endTime,
      detail: detail,
      place: place,
    );
    schedules = [
      for (final s in schedules)
        if (s.id == scheduleId) updated else s,
    ];
    return updated;
  }

  @override
  Future<void> deleteSchedule(
    String idToken,
    int roomId,
    int scheduleId,
  ) async {
    deleteCalls.add(scheduleId);
    schedules = schedules.where((s) => s.id != scheduleId).toList();
  }
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// today와 같은 달 안에서 확실히 다른 날짜(1일 또는 2일)를 고른다.
DateTime _otherDayInSameMonth() {
  final today = _today();
  final day = today.day == 1 ? 2 : 1;
  return DateTime(today.year, today.month, day);
}

/// 3일짜리 다중일 구간을 잡아도 같은 달을 벗어나지 않고, 오늘(기본 선택일·
/// 하단 카드 리스트)과도 겹치지 않는 시작일 — 그리드 점 개수만 순수하게
/// 비교할 수 있도록 한다.
DateTime _safeRangeStart() {
  final today = _today();
  final day = today.day <= 20 ? today.day + 5 : 1;
  return DateTime(today.year, today.month, day);
}

// 반환 타입을 raw `ValueKey`로 두면 다운워드 추론 탓에 `ValueKey<dynamic>`이
// 만들어져 실제 위젯의 `ValueKey<String>`과 runtimeType이 달라 `==`가 항상
// false가 된다(find.byKey가 조용히 0개를 찾는다) — 반드시 `<String>`을 명시.
ValueKey<String> _cellKey(DateTime day) => ValueKey<String>(
  'schedule-cell-${day.year}-'
  '${day.month.toString().padLeft(2, '0')}-'
  '${day.day.toString().padLeft(2, '0')}',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('이번 달 그리드가 보이고 오늘 날짜 셀이 렌더된다', (tester) async {
    final fakeApi = _FakeScheduleApi();

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final today = _today();
    expect(
      find.byKey(
        ValueKey(
          'schedule-cell-${today.year}-'
          '${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('오늘 일정'), findsOneWidget);
  });

  testWidgets('오늘 일정이 있으면 하단 리스트에 보인다', (tester) async {
    final today = _today();
    final fakeApi = _FakeScheduleApi(
      schedules: [ScheduleItem(id: 1, title: '오늘 회의', date: today)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘 회의'), findsOneWidget);
  });

  testWidgets('날짜를 탭하면 하단 리스트가 그 날짜로 갱신된다', (tester) async {
    final today = _today();
    final otherDay = _otherDayInSameMonth();
    final fakeApi = _FakeScheduleApi(
      schedules: [
        ScheduleItem(id: 1, title: '오늘 회의', date: today),
        ScheduleItem(id: 2, title: '다른날 회의', date: otherDay),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘 회의'), findsOneWidget);
    expect(find.text('다른날 회의'), findsNothing);

    final cellKey = ValueKey(
      'schedule-cell-${otherDay.year}-'
      '${otherDay.month.toString().padLeft(2, '0')}-'
      '${otherDay.day.toString().padLeft(2, '0')}',
    );
    await tester.tap(find.byKey(cellKey));
    await tester.pumpAndSettle();

    expect(find.text('다른날 회의'), findsOneWidget);
    expect(find.text('오늘 회의'), findsNothing);
  });

  testWidgets('선택한 날짜에 일정이 없으면 빈 상태와 CTA가 보인다', (tester) async {
    final fakeApi = _FakeScheduleApi();

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 추가 버튼은 우상단(+)에만 — 빈 상태는 안내 문구만(2026-08-06).
    expect(find.text('일정이 없어요'), findsOneWidget);
    expect(find.text('일정 추가하기'), findsNothing);
    expect(find.byTooltip('일정 추가'), findsOneWidget);
  });

  testWidgets('생성 시트로 제목만 입력해 일정을 추가한다', (tester) async {
    final fakeApi = _FakeScheduleApi();

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 생성 시트는 우상단 + 버튼으로 연다(빈 상태에는 버튼이 없다, 2026-08-06).
    await tester.tap(find.byTooltip('일정 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '새 일정');
    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(fakeApi.createTitles, ['새 일정']);
    expect(find.text('새 일정'), findsOneWidget);
  });

  testWidgets('일정 카드를 탭해 수정하면 목록에 반영된다', (tester) async {
    final today = _today();
    final fakeApi = _FakeScheduleApi(
      schedules: [ScheduleItem(id: 1, title: '원래 제목', date: today)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('schedule-card-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '바뀐 제목');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('바뀐 제목'), findsOneWidget);
    expect(find.text('원래 제목'), findsNothing);
  });

  testWidgets('수정 시트에서 삭제하면 확인 모달 후에만 삭제된다', (tester) async {
    final today = _today();
    final fakeApi = _FakeScheduleApi(
      schedules: [ScheduleItem(id: 1, title: '삭제될 일정', date: today)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('schedule-card-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('일정 삭제'));
    await tester.pumpAndSettle();

    expect(fakeApi.deleteCalls, isEmpty);
    expect(find.text('이 일정을 삭제할까요?'), findsOneWidget);

    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(fakeApi.deleteCalls, [1]);
    expect(find.text('삭제될 일정'), findsNothing);
  });

  testWidgets('로드 실패 시 에러 안내와 재시도 버튼이 보이고, 재시도하면 다시 호출한다', (tester) async {
    final fakeApi = _FakeScheduleApi(throwOnFetch: true);

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('일정을 불러오지 못했어요'), findsOneWidget);
    expect(fakeApi.fetchCallCount, 1);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(fakeApi.fetchCallCount, 2);
  });

  testWidgets('진행 중인 방이 없으면 안내가 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: _FakeScheduleApi(),
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _NoActiveRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('진행 중인 방이 없어요'), findsOneWidget);
  });

  testWidgets('월 이동 화살표를 탭하면 다음 달을 다시 조회한다', (tester) async {
    final fakeApi = _FakeScheduleApi();

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final callsBefore = fakeApi.fetchCallCount;
    final today = _today();
    final nextMonth = DateTime(today.year, today.month + 1, 1);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(fakeApi.fetchCallCount, callsBefore + 1);
    expect(find.text('${nextMonth.year}년 ${nextMonth.month}월'), findsOneWidget);
  });

  testWidgets('다음 달로 이동하면 선택일이 그 달로 옮겨진다(하단 헤더 날짜 반영)', (tester) async {
    final fakeApi = _FakeScheduleApi();

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nextMonth = DateTime(_today().year, _today().month + 1, 1);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    // 오늘이 다음 달에 없으므로 선택일이 다음 달 1일로 옮겨진다. 하단 헤더 제목
    // ('9월 1일 일정')과 우측 날짜 라벨('9월 1일 (요일)') 둘 다 새 날짜를 반영한다.
    expect(find.text('${nextMonth.month}월 1일 일정'), findsOneWidget);
    expect(find.textContaining('${nextMonth.month}월 1일 ('), findsOneWidget);
  });

  testWidgets('요일 헤더가 일요일 시작으로 렌더된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: _FakeScheduleApi(),
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 일요일 시작: '일'/'토' 요일 라벨이 각각 하나씩 렌더된다.
    expect(find.text('일'), findsOneWidget);
    expect(find.text('토'), findsOneWidget);
  });

  testWidgets('일정 카드에 시간·장소가 함께 표시된다', (tester) async {
    final today = _today();
    final fakeApi = _FakeScheduleApi(
      schedules: [
        ScheduleItem(
          id: 1,
          title: '스터디',
          date: today,
          time: '10:00:00',
          place: '중앙도서관',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('스터디'), findsOneWidget);
    expect(find.text('오전 10:00 · 중앙도서관'), findsOneWidget);
  });

  testWidgets('생성 시트에서 장소를 입력하면 API에 전달된다', (tester) async {
    final fakeApi = _FakeScheduleApi();

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 생성 시트는 우상단 + 버튼으로 연다(빈 상태에는 버튼이 없다, 2026-08-06).
    await tester.tap(find.byTooltip('일정 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '장소 있는 일정');

    // 장소 행(미지정) 탭 → 다이얼로그에 입력 → 확인.
    await tester.tap(find.text('미지정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '스터디카페');
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(fakeApi.createTitles, ['장소 있는 일정']);
    expect(fakeApi.createPlaces, ['스터디카페']);
  });

  testWidgets('다중일 일정이 구간의 모든 날짜 셀에 점으로 표시되고, 중간 날짜를 탭하면 리스트에 보인다', (
    tester,
  ) async {
    final start = _safeRangeStart();
    final middle = DateTime(start.year, start.month, start.day + 1);
    final end = DateTime(start.year, start.month, start.day + 2);

    await tester.pumpWidget(
      MaterialApp(
        // 두 번째 pumpWidget에서 새 State가 만들어지도록(안 그러면 기존
        // State가 재사용돼 새 api로 다시 로드하지 않는다) 서로 다른 키를 쓴다.
        key: const ValueKey('without-schedule'),
        home: ScheduleScreen(
          api: _FakeScheduleApi(),
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final withoutSchedule = tester.widgetList(find.byType(DecoratedBox)).length;

    final fakeApi = _FakeScheduleApi(
      schedules: [ScheduleItem(id: 1, title: '워크숍', date: start, endDate: end)],
    );
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('with-schedule'),
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final withSchedule = tester.widgetList(find.byType(DecoratedBox)).length;

    // 3일 구간이므로 이벤트 점(DecoratedBox) 3개가 늘어난다 — 시작일에만
    // 찍히면 1개만 늘어나므로 이 값이 다중일 렌더링의 증거가 된다.
    expect(withSchedule, withoutSchedule + 3);

    await tester.tap(find.byKey(_cellKey(middle)));
    await tester.pumpAndSettle();

    expect(find.text('워크숍'), findsOneWidget);
  });

  testWidgets('다중일 일정 카드에 날짜 범위와 종료시간 범위가 함께 표시된다', (tester) async {
    final today = _today();
    final endDate = DateTime(today.year, today.month, today.day + 2);
    final fakeApi = _FakeScheduleApi(
      schedules: [
        ScheduleItem(
          id: 1,
          title: '워크숍',
          date: today,
          time: '10:00:00',
          endDate: endDate,
          endTime: '12:00:00',
          place: '중앙도서관',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        '${today.month}월 ${today.day}일 - ${endDate.month}월 ${endDate.day}일 · '
        '오전 10:00 - 오후 12:00 · 중앙도서관',
      ),
      findsOneWidget,
    );
  });

  testWidgets('생성 시트를 열면 시작 시간이 없어 종료 행이 보이지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: _FakeScheduleApi(),
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 생성 시트는 우상단 + 버튼으로 연다(빈 상태에는 버튼이 없다, 2026-08-06).
    await tester.tap(find.byTooltip('일정 추가'));
    await tester.pumpAndSettle();

    expect(find.text('종료'), findsNothing);
  });

  testWidgets('시작 시간이 있는 일정을 수정하면 종료 행이 보인다', (tester) async {
    final today = _today();
    final fakeApi = _FakeScheduleApi(
      schedules: [
        ScheduleItem(id: 1, title: '회의', date: today, time: '10:00:00'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('schedule-card-1')));
    await tester.pumpAndSettle();

    expect(find.text('종료'), findsOneWidget);
    expect(find.text('미설정'), findsOneWidget);
  });

  testWidgets('같은 날 종료 시간이 시작 시간보다 늦지 않으면 인라인 에러가 뜨고 저장되지 않는다', (tester) async {
    final today = _today();
    final fakeApi = _FakeScheduleApi(
      schedules: [
        ScheduleItem(
          id: 1,
          title: '회의',
          date: today,
          time: '10:00:00',
          endTime: '09:00:00',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('schedule-card-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('종료 시간은 시작 시간보다 늦어야 해요'), findsOneWidget);
    // 검증에서 막혔으므로 시트가 닫히지 않고 그대로 남아 있다.
    expect(find.textContaining('일정 수정'), findsOneWidget);
  });

  group('일정 카드 치수 (2026-08-07 Figma)', () {
    /// 제목 + 부제가 모두 있는 카드 — Figma 시안과 같은 구성이라야 58이 나온다.
    ScheduleItem cardSchedule(int id, DateTime date) => ScheduleItem(
      id: id,
      title: '스터디 정기 모임',
      date: date,
      time: '10:00:00',
      place: '중앙도서관',
    );

    Future<void> pumpCards(WidgetTester tester, int count) async {
      final today = _today();
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            api: _FakeScheduleApi(
              schedules: [
                for (var i = 1; i <= count; i++) cardSchedule(i, today),
              ],
            ),
            authService: _FakeAuthService(),
            roomSession: RoomSession(roomApi: _FakeRoomApi()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder barOf(String cardKey) => find.descendant(
      of: find.byKey(ValueKey(cardKey)),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 3,
      ),
    );

    testWidgets('카드 높이가 58이다 — 패딩 10 + 콘텐츠 38 + 패딩 10', (tester) async {
      await pumpCards(tester, 1);
      // 설정값이 아니라 파생값이다: 세로 패딩·제목/부제 타이포·둘 사이 간격 중
      // 하나라도 어긋나면 여기서 걸린다.
      expect(
        tester.getSize(find.byKey(const ValueKey('schedule-card-1'))).height,
        closeTo(58, 1),
      );
    });

    testWidgets('좌측 컬러 바가 3 × 34다', (tester) async {
      await pumpCards(tester, 1);
      expect(tester.getSize(barOf('schedule-card-1')), const Size(3, 34));
    });

    testWidgets('바가 카드 좌측에서 12, 세로 중앙에 놓인다', (tester) async {
      await pumpCards(tester, 1);
      final card = tester.getRect(
        find.byKey(const ValueKey('schedule-card-1')),
      );
      final bar = tester.getRect(barOf('schedule-card-1'));

      // 12는 테두리 1을 뺀 가로 패딩 11 + 테두리 1이다. 가로 보정을 되돌리면 13이 된다
      // — 세로만 검증하면 이 축이 통째로 무방비다(2026-08-07 reviewer 뮤테이션).
      expect(bar.left - card.left, closeTo(12, 0.01));
      // 세로 중앙: 위아래 여백이 같다.
      expect(bar.top - card.top, closeTo(card.bottom - bar.bottom, 0.01));
    });

    testWidgets('바와 텍스트 사이 간격이 10이다', (tester) async {
      await pumpCards(tester, 1);
      final bar = tester.getRect(barOf('schedule-card-1'));
      final title = tester.getRect(find.text('스터디 정기 모임'));
      expect(title.left - bar.right, closeTo(10, 0.01));
    });

    testWidgets('카드 사이 간격이 8이다', (tester) async {
      await pumpCards(tester, 2);
      final first = tester.getRect(
        find.byKey(const ValueKey('schedule-card-1')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('schedule-card-2')),
      );
      expect(second.top - first.bottom, closeTo(8, 0.01));
    });

    testWidgets('마지막 카드 뒤에는 여백이 없다', (tester) async {
      await pumpCards(tester, 2);
      // 카드를 담은 Column의 아래 끝이 마지막 카드의 아래 끝과 같아야 한다.
      // 카드가 스스로 bottom 패딩을 달든 리스트가 트레일링 간격을 달든 여기서 걸린다.
      final column = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const ValueKey('schedule-card-2')),
              matching: find.byType(Column),
            )
            .first,
      );
      final last = tester.getRect(
        find.byKey(const ValueKey('schedule-card-2')),
      );
      expect(column.bottom - last.bottom, closeTo(0, 0.01));
    });
  });

  group('일요일·공휴일 색 (specs/0009-일정-탭.md)', () {
    // 2026-12로 고정한다. 25일(성탄절·금)·20일(일)·24일(목, 평일)·15일(오늘)이
    // 네 가지 색 분기를 한 달 안에서 전부 덮는다.
    const fixedToday = 15;
    DateTime december(int day) => DateTime(2026, 12, day);

    Future<void> pumpDecember(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            api: _FakeScheduleApi(),
            authService: _FakeAuthService(),
            roomSession: RoomSession(roomApi: _FakeRoomApi()),
            today: december(fixedToday),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// 날짜 셀 안의 숫자 Text가 실제로 그려진 색.
    Color cellTextColor(WidgetTester tester, int day) {
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(_cellKey(december(day))),
          matching: find.text('$day'),
        ),
      );
      return text.style!.color!;
    }

    testWidgets('공휴일(성탄절)은 accent-danger로 그린다', (tester) async {
      await pumpDecember(tester);
      expect(cellTextColor(tester, 25), AppColors.accentDanger);
    });

    testWidgets('일요일은 accent-danger로 그린다', (tester) async {
      await pumpDecember(tester);
      // 2026-12-20 · 27은 일요일.
      expect(cellTextColor(tester, 20), AppColors.accentDanger);
      expect(cellTextColor(tester, 27), AppColors.accentDanger);
    });

    testWidgets('토요일과 평일은 색을 바꾸지 않는다', (tester) async {
      await pumpDecember(tester);
      // 2026-12-26은 토요일 — 사용자 확정으로 색을 주지 않는다.
      expect(cellTextColor(tester, 26), AppColors.foreground);
      expect(cellTextColor(tester, 24), AppColors.foreground);
    });

    testWidgets('선택일이 휴일 색보다 우선한다', (tester) async {
      await pumpDecember(tester);
      // 12-15는 오늘이자 기본 선택일 → primary 채운 원 위의 흰 글씨.
      expect(cellTextColor(tester, fixedToday), AppColors.onPrimary);

      // 일요일(12-20)을 선택하면 휴일 빨강이 아니라 선택 상태가 이긴다.
      await tester.tap(find.byKey(_cellKey(december(20))));
      await tester.pumpAndSettle();
      expect(cellTextColor(tester, 20), AppColors.onPrimary);
      // 선택이 옮겨간 뒤 오늘(12-15)은 primary 텍스트로 남는다.
      expect(cellTextColor(tester, fixedToday), AppColors.primary);
    });

    testWidgets('오늘이 휴일이어도 오늘 표식(primary)이 휴일 색을 이긴다', (tester) async {
      // 7일에 하루는 오늘이 일요일이다. 이 조합을 안 만들면 "오늘 > 휴일" 순서를 뒤집어도
      // 테스트가 통과해 버린다(2026-08-07 reviewer가 뮤테이션으로 확인한 구멍).
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            api: _FakeScheduleApi(),
            authService: _FakeAuthService(),
            roomSession: RoomSession(roomApi: _FakeRoomApi()),
            today: december(20), // 2026-12-20 = 일요일
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 선택을 평일로 옮겨 "오늘이지만 선택은 아닌" 상태를 만든다.
      await tester.tap(find.byKey(_cellKey(december(24))));
      await tester.pumpAndSettle();

      expect(cellTextColor(tester, 20), AppColors.primary);
      // 같은 달의 다른 일요일은 그대로 휴일 색이라, 위 결과가 "일요일 색이 통째로
      // 안 먹은 것"이 아니라 오늘 표식이 이긴 것임을 함께 못 박는다.
      expect(cellTextColor(tester, 27), AppColors.accentDanger);
    });

    testWidgets('오늘이 공휴일이어도 오늘 표식이 이긴다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            api: _FakeScheduleApi(),
            authService: _FakeAuthService(),
            roomSession: RoomSession(roomApi: _FakeRoomApi()),
            today: december(25), // 성탄절 = 금요일이라 일요일 판정과 무관하다
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_cellKey(december(24))));
      await tester.pumpAndSettle();

      expect(cellTextColor(tester, 25), AppColors.primary);
    });

    testWidgets('요일 헤더의 일요일 라벨도 accent-danger다', (tester) async {
      await pumpDecember(tester);
      // 헤더의 '일'은 날짜 그리드에 없는 단독 텍스트다(날짜는 전부 숫자).
      final label = tester.widget<Text>(find.text('일').first);
      expect(label.style!.color, AppColors.accentDanger);
    });

    // 공휴일 이름 표시: 색뿐 아니라 목록 상단에 이름을 일정처럼 보여준다.
    testWidgets('오늘이 공휴일이면 일정 목록 맨 위에 공휴일 항목을 보여준다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            api: _FakeScheduleApi(),
            authService: _FakeAuthService(),
            roomSession: RoomSession(roomApi: _FakeRoomApi()),
            today: december(25), // 성탄절
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('성탄절'), findsOneWidget);
      expect(find.text('공휴일'), findsOneWidget);
      // 공휴일 항목이 있으면 빈 상태 문구는 뜨지 않는다.
      expect(find.text('일정이 없어요'), findsNothing);
    });

    testWidgets('평일이면 공휴일 항목이 없고 빈 상태만 보인다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScheduleScreen(
            api: _FakeScheduleApi(),
            authService: _FakeAuthService(),
            roomSession: RoomSession(roomApi: _FakeRoomApi()),
            today: december(24), // 평일(목)
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('공휴일'), findsNothing);
      expect(find.text('일정이 없어요'), findsOneWidget);
    });
  });
}
