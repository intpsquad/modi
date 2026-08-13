import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/room/room_session.dart';
import 'package:app/features/settings/settings_screens.dart';
import 'package:app/routing/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _WithdrawalSettingsApi extends SettingsApi {
  _WithdrawalSettingsApi({this.error});

  final Object? error;
  final List<String> receivedTokens = [];

  @override
  Future<UserProfile> fetchProfile(String idToken) async =>
      const UserProfile(userId: 'me', nickname: '민네임');

  @override
  Future<List<SettingsMember>> fetchMembers(String idToken, int roomId) async =>
      const [];

  @override
  Future<void> withdraw(String idToken) async {
    receivedTokens.add(idToken);
    if (error != null) throw error!;
  }
}

class _WithdrawalAuthService extends AuthService {
  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

final _room = RoomSummary(
  id: 7,
  name: '여름 알고리즘 스터디',
  goal: '코딩테스트 통과하기',
  status: 'ACTIVE',
  startDate: DateTime(2026, 7, 28),
  endDate: DateTime(2026, 8, 10),
);

Future<void> _pumpSettings(
  WidgetTester tester, {
  required SettingsApi api,
  required AuthService authService,
  required RoomSession roomSession,
  required AppSession session,
  TextScaler? textScaler,
}) async {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (context, state) => SettingsScreen(
          currentRoom: _room,
          api: api,
          authService: authService,
          tokenLoader: () async => 'id-token',
          roomSession: roomSession,
          session: session,
        ),
      ),
      GoRoute(
        path: '/onboarding/intro',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('온보딩 소개 화면'))),
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: textScaler == null
          ? null
          : (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openWithdrawalDialog(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('회원 탈퇴'), 320);
  // 활동 카드 추가로 페이지가 길어져 부분 노출만으론 탭 중심이 화면 밖일 수 있다.
  await tester.ensureVisible(find.text('회원 탈퇴'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('회원 탈퇴'));
  await tester.pumpAndSettle();
}

void main() {
  late RoomSession roomSession;
  late AppSession session;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'onboarding_intro_completed': true,
      'last_viewed_room_id': 7,
    });
    roomSession = RoomSession();
    roomSession.rooms = [_room];
    roomSession.currentRoomId = _room.id;
    session = AppSession();
    session.setIntroStatus(completed: true);
  });

  tearDown(() => session.dispose());

  testWidgets('회원 탈퇴는 되돌릴 수 없는 영향과 방 자동 나가기를 경고한다', (tester) async {
    await _pumpSettings(
      tester,
      api: _WithdrawalSettingsApi(),
      authService: _WithdrawalAuthService(),
      roomSession: roomSession,
      session: session,
    );

    await _openWithdrawalDialog(tester);

    expect(find.text('정말 회원탈퇴하시겠습니까?'), findsOneWidget);
    expect(find.textContaining('전부 삭제'), findsOneWidget);
    expect(find.textContaining('되돌릴 수 없어요'), findsOneWidget);
  });

  testWidgets('320px·큰 글자에서도 탈퇴 경고와 확정 버튼이 잘린 곳 없이 보인다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpSettings(
      tester,
      api: _WithdrawalSettingsApi(),
      authService: _WithdrawalAuthService(),
      roomSession: roomSession,
      session: session,
      textScaler: const TextScaler.linear(1.3),
    );

    await _openWithdrawalDialog(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('전부 삭제'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('confirm-withdrawal-button')),
      findsOneWidget,
    );
  });

  testWidgets('취소하면 회원 탈퇴 API를 호출하지 않는다', (tester) async {
    final api = _WithdrawalSettingsApi();
    await _pumpSettings(
      tester,
      api: api,
      authService: _WithdrawalAuthService(),
      roomSession: roomSession,
      session: session,
    );

    await _openWithdrawalDialog(tester);
    await tester.tap(find.byKey(const ValueKey('cancel-withdrawal-button')));
    await tester.pumpAndSettle();

    expect(api.receivedTokens, isEmpty);
  });

  testWidgets('확정하면 계정을 삭제하고 로컬 세션을 지운 뒤 온보딩으로 이동한다', (tester) async {
    final api = _WithdrawalSettingsApi();
    final authService = _WithdrawalAuthService();
    await _pumpSettings(
      tester,
      api: api,
      authService: authService,
      roomSession: roomSession,
      session: session,
    );

    await _openWithdrawalDialog(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-withdrawal-button')));
    await tester.pumpAndSettle();

    expect(api.receivedTokens, ['id-token']);
    expect(authService.signOutCalls, 1);
    expect(roomSession.rooms, isEmpty);
    expect(roomSession.currentRoomId, isNull);
    expect(session.introCompleted, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_intro_completed'), isNull);
    expect(prefs.getInt('last_viewed_room_id'), isNull);
    expect(find.text('온보딩 소개 화면'), findsOneWidget);
  });

  testWidgets('서버 탈퇴 실패 시 로컬 세션을 유지하고 오류를 알린다', (tester) async {
    final api = _WithdrawalSettingsApi(error: StateError('server error'));
    final authService = _WithdrawalAuthService();
    await _pumpSettings(
      tester,
      api: api,
      authService: authService,
      roomSession: roomSession,
      session: session,
    );

    await _openWithdrawalDialog(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-withdrawal-button')));
    await tester.pumpAndSettle();

    expect(api.receivedTokens, ['id-token']);
    expect(authService.signOutCalls, 0);
    expect(roomSession.currentRoomId, _room.id);
    expect(session.introCompleted, isTrue);
    expect(find.text('회원 탈퇴를 완료하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);

    final withdrawalTile = find.ancestor(
      of: find.text('회원 탈퇴'),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(withdrawalTile).onTap, isNotNull);
  });
}
