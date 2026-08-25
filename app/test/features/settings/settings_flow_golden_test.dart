import 'dart:io' as io;

import 'package:app/design/theme.dart';
import 'package:app/design/tokens.dart';
import 'package:app/features/room/room_session.dart';
import 'package:app/features/settings/settings_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _screenWidth = 390.0;
const _screenHeight = 844.0;

void main() {
  // The baseline uses macOS text/Skia rendering; Linux CI otherwise reports
  // false-positive pixel diffs for the unchanged layout.
  testWidgets('상세 설정 6개 화면이 기준 레이아웃으로 렌더링된다', (tester) async {
    await _loadPretendard();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(_screenWidth * 6, _screenHeight);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final api = _GoldenSettingsApi();
    final room = RoomSummary(
      id: 7,
      name: '여름 알고리즘 스터디',
      goal: '코딩테스트 통과하기',
      goalDetail: '매주 문제 15개 이상 풀고, 금요일마다 오답을 함께 리뷰한다.',
      status: 'ACTIVE',
      startDate: DateTime(2026, 7, 28),
      endDate: DateTime(2026, 8, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: const ValueKey('settings-flow-canvas'),
          child: Row(
            children: [
              _screen(
                SettingsScreen(
                  currentRoom: room,
                  api: api,
                  tokenLoader: () async => 'token',
                ),
              ),
              _screen(
                ProfileSettingsScreen(
                  api: api,
                  tokenLoader: () async => 'token',
                ),
              ),
              _screen(
                NotificationSettingsScreen(
                  api: api,
                  tokenLoader: () async => 'token',
                ),
              ),
              _screen(
                RoomSettingsScreen(
                  room: room,
                  api: api,
                  tokenLoader: () async => 'token',
                ),
              ),
              _screen(
                MembersSettingsScreen(
                  room: room,
                  api: api,
                  tokenLoader: () async => 'token',
                  currentUserId: 'me',
                ),
              ),
              _screen(
                PastRoomsScreen(api: api, tokenLoader: () async => 'token'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('settings-flow-canvas')),
      matchesGoldenFile('goldens/settings_flow.png'),
    );
  }, skip: !io.Platform.isMacOS);

  testWidgets('320px·큰 글자에서도 설정 핵심 화면에 오버플로가 없다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final api = _GoldenSettingsApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.3),
          ),
          child: MembersSettingsScreen(
            room: _room(),
            api: api,
            tokenLoader: () async => 'token',
            currentUserId: 'me',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('개인 진행률 90%'), findsOneWidget);
  });
}

Future<void> _loadPretendard() async {
  final loader = FontLoader(AppTypography.fontFamily)
    ..addFont(rootBundle.load('fonts/Pretendard-Regular.otf'))
    ..addFont(rootBundle.load('fonts/Pretendard-Medium.otf'))
    ..addFont(rootBundle.load('fonts/Pretendard-SemiBold.otf'))
    ..addFont(rootBundle.load('fonts/Pretendard-Bold.otf'));
  await loader.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

Widget _screen(Widget child) => SizedBox(
  width: _screenWidth,
  height: _screenHeight,
  child: Navigator(
    pages: [
      const MaterialPage<void>(child: SizedBox.shrink()),
      MaterialPage<void>(child: child),
    ],
    onDidRemovePage: (_) {},
  ),
);

RoomSummary _room() => RoomSummary(
  id: 7,
  name: '여름 알고리즘 스터디',
  goal: '코딩테스트 통과하기',
  goalDetail: '매주 문제를 풀고 함께 리뷰한다.',
  status: 'ACTIVE',
  startDate: DateTime(2026, 7, 28),
  endDate: DateTime(2026, 8, 10),
);

class _GoldenSettingsApi extends SettingsApi {
  @override
  Future<UserProfile> fetchProfile(String idToken) async =>
      const UserProfile(userId: 'minname01', nickname: '민네임');

  @override
  Future<NotificationSettings> fetchNotificationSettings(
    String idToken,
  ) async => const NotificationSettings(allEnabled: true, pokeEnabled: true);

  @override
  Future<NotificationSettings> updateNotificationSettings(
    String idToken,
    NotificationSettings settings,
  ) async => settings;

  @override
  Future<List<SettingsMember>> fetchMembers(String idToken, int roomId) async =>
      const [
        SettingsMember(
          userId: 'me',
          nickname: '민네임',
          assignedTotal: 10,
          assignedDone: 9,
        ),
        SettingsMember(
          userId: 'member-2',
          nickname: '조딘엄',
          assignedTotal: 4,
          assignedDone: 3,
        ),
        SettingsMember(
          userId: 'member-3',
          nickname: '서너멍',
          assignedTotal: 5,
          assignedDone: 3,
        ),
        SettingsMember(
          userId: 'member-4',
          nickname: '하닝원',
          assignedTotal: 5,
          assignedDone: 2,
        ),
        SettingsMember(
          userId: 'member-5',
          nickname: '윤나엄',
          assignedTotal: 6,
          assignedDone: 1,
        ),
      ];

  @override
  Future<String> fetchInviteCode(String idToken, int roomId) async =>
      'K7QP-2M9X';

  @override
  Future<List<PastRoom>> fetchPastRooms(String idToken) async => [
    PastRoom(
      id: 1,
      name: '봄학기 CS 스터디',
      startDate: DateTime(2026, 5, 20),
      endDate: DateTime(2026, 6, 25),
      completionRate: 0.87,
    ),
    PastRoom(
      id: 2,
      name: '겨울 알고리즘 캠프',
      startDate: DateTime(2026, 1, 8),
      endDate: DateTime(2026, 2, 20),
      completionRate: 0.74,
    ),
    PastRoom(
      id: 3,
      name: '토익 단기 스터디',
      startDate: DateTime(2025, 12, 10),
      endDate: DateTime(2025, 12, 30),
      completionRate: 0.52,
    ),
  ];
}
