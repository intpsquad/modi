import 'dart:typed_data';

import 'package:app/features/room/invite_share.dart';
import 'package:app/features/room/room_api.dart';
import 'package:app/features/room/room_session.dart';
import 'package:app/features/settings/my_activity_card.dart';
import 'package:app/features/settings/settings_screens.dart';
import 'package:app/features/shell/app_shell.dart';
import 'package:app/features/shell/tab_activation.dart';
import 'package:app/routing/app_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _tapSettingsTile(WidgetTester tester, String title) async {
  final tile = find.ancestor(
    of: find.text(title),
    matching: find.byType(ListTile),
  );
  await tester.scrollUntilVisible(tile, 300);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
}

void main() {
  testWidgets('S-40 설정은 피그마 섹션 순서와 주요 메뉴를 노출한다', (tester) async {
    final room = RoomSummary(
      id: 7,
      name: '여름 알고리즘 스터디',
      goal: '코딩테스트 통과하기',
      status: 'ACTIVE',
      startDate: DateTime(2026, 7, 28),
      endDate: DateTime(2026, 8, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          currentRoom: room,
          api: _FakeSettingsApi(),
          tokenLoader: () async => 'token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('계정'), findsOneWidget);
    // 프로필은 상단 헤더 행으로 이전(닉네임 + 'MODI와 함께한 지 …' 캡션, 탭→편집).
    expect(find.text('민네임'), findsOneWidget);
    expect(find.text('로그인 계정 정보'), findsOneWidget);
    expect(find.text('알림 설정'), findsOneWidget);
    expect(find.text('방 관리'), findsOneWidget);
    expect(find.text('현재 방 설정'), findsOneWidget);
    expect(find.text('멤버 · 초대'), findsOneWidget);
    expect(find.text('종료된 방'), findsOneWidget);
    expect(find.text('정보 · 지원'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('로그아웃'), 300);
    expect(find.text('로그아웃'), findsOneWidget);
    expect(find.text('회원 탈퇴'), findsOneWidget);
  });

  testWidgets('위에서 아래로 당기면 프로필 등 정보를 다시 불러온다', (tester) async {
    final api = _FakeSettingsApi();

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(api: api, tokenLoader: () async => 'token'),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.fetchProfileCallCount, 1, reason: '처음 화면을 열 때 한 번 불러온다');

    await tester.fling(
      find.byType(SingleChildScrollView),
      const Offset(0, 300),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(api.fetchProfileCallCount, 2, reason: '당겨서 새로고침하면 한 번 더 불러온다');
  });

  testWidgets('마이 탭 재탭 신호를 받으면 맨 위로 스크롤한다(홈과 같은 패턴, 2026-08-09 QA)', (
    tester,
  ) async {
    final tabActivation = TabActivation();
    addTearDown(tabActivation.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: _FakeSettingsApi(),
          tokenLoader: () async => 'token',
          tabActivation: tabActivation,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 아래로 스크롤해 맨 위가 아닌 상태를 만든다.
    await tester.fling(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
      1000,
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    expect(controller.offset, greaterThan(0));

    // 다른 탭의 재탭은 영향이 없다.
    tabActivation.reselect.notify(AppShell.homeIndex);
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));

    // 마이 탭 재탭 신호가 오면 맨 위로 스크롤한다.
    tabActivation.reselect.notify(AppShell.mypageIndex);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('로그인 수단이 없으면 연결됨 placeholder를 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: _FakeSettingsApi(),
          tokenLoader: () async => 'token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('연결됨'), findsOneWidget);
    expect(find.text('카카오 로그인'), findsNothing);
  });

  testWidgets('카카오로 로그인했으면 카카오 로그인 배지를 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: _KakaoSettingsApi(),
          tokenLoader: () async => 'token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('카카오 로그인'), findsOneWidget);
    expect(find.text('연결됨'), findsNothing);
  });

  testWidgets('문의하기는 지정된 지원 메일 작성 화면을 연다', (tester) async {
    Uri? launchedUri;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: _FakeSettingsApi(),
          tokenLoader: () async => 'token',
          contactEmailLauncher: (uri) async {
            launchedUri = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapSettingsTile(tester, '문의하기');
    await tester.pumpAndSettle();

    expect(launchedUri, Uri(scheme: 'mailto', path: 'modi.app.team@gmail.com'));
  });

  testWidgets('메일 앱을 열 수 없으면 지원 메일 주소를 안내한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: _FakeSettingsApi(),
          tokenLoader: () async => 'token',
          contactEmailLauncher: (_) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _tapSettingsTile(tester, '문의하기');
    await tester.pumpAndSettle();

    expect(find.textContaining('메일 앱을 열 수 없어요'), findsOneWidget);
    expect(find.textContaining('modi.app.team@gmail.com'), findsOneWidget);
  });

  testWidgets('마지막 멤버의 방 나가기 확인창은 방 삭제를 함께 경고한다', (tester) async {
    final room = RoomSummary(
      id: 7,
      name: '여름 알고리즘 스터디',
      goal: '코딩테스트 통과하기',
      status: 'ACTIVE',
      startDate: DateTime(2026, 7, 28),
      endDate: DateTime(2026, 8, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          currentRoom: room,
          api: _LastMemberSettingsApi(),
          tokenLoader: () async => 'token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('방 나가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('방 나가기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('마지막 멤버가 나가면 방 기록이 전부 삭제됩니다.'), findsOneWidget);
    await tester.tap(find.text('취소'));
  });

  testWidgets('방을 나가면 현재 방이 다음 방으로 갱신되어 연속으로 나갈 수 있다', (tester) async {
    final roomA = RoomSummary(
      id: 7,
      name: '여름 알고리즘 스터디',
      goal: '코딩테스트 통과하기',
      status: 'ACTIVE',
      startDate: DateTime(2026, 7, 28),
      endDate: DateTime(2026, 8, 10),
    );
    final roomB = RoomSummary(
      id: 8,
      name: '겨울 독서 모임',
      goal: '한 달에 책 한 권',
      status: 'ACTIVE',
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 9, 1),
    );

    SharedPreferences.setMockInitialValues({'last_viewed_room_id': roomA.id});
    final roomApi = _LeaveRoomFakeRoomApi(remaining: [roomA, roomB]);
    final roomSession = RoomSession(roomApi: roomApi)
      ..rooms = [roomA, roomB]
      ..currentRoomId = roomA.id;
    final session = AppSession(authProvider: _NoOpAuthSessionProvider());
    final api = _LeaveRoomSettingsApi(roomApi);
    addTearDown(session.dispose);

    // 실제 앱(app_router.dart)처럼 StatefulShellRoute로 두 브랜치를 구성한다 — 마이 탭을
    // 떠나도 SettingsScreen의 State가 dispose되지 않고 유지되는 걸 재현해야, 나간 방을
    // 로컬 상태가 계속 들고 있는 실제 회귀 시나리오를 검증할 수 있다.
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => navigationShell,
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, state) =>
                      const Scaffold(body: Center(child: Text('홈 화면'))),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => SettingsScreen(
                    api: api,
                    tokenLoader: () async => 'token',
                    roomSession: roomSession,
                    session: session,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // 첫 번째 방 나가기: A → B로 넘어간다.
    await tester.ensureVisible(find.text('방 나가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('방 나가기'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('방 나가기')),
    );
    await tester.pumpAndSettle();

    expect(api.leftRoomIds, [roomA.id]);
    expect(find.text('홈 화면'), findsOneWidget);

    router.go('/settings');
    await tester.pumpAndSettle();

    // 마이페이지로 돌아오면 "현재 방 설정"이 이미 B로 갱신돼 있어야 한다.
    expect(find.text(roomB.name), findsOneWidget);

    // 두 번째 방 나가기: stale한 A가 아니라 B의 id로 나가져야 한다.
    await tester.ensureVisible(find.text('방 나가기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('방 나가기'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Dialog), matching: find.text('방 나가기')),
    );
    await tester.pumpAndSettle();

    expect(api.leftRoomIds, [roomA.id, roomB.id]);
  });

  testWidgets('전체 알림을 끄면 개별이 모두 꺼지되, 개별 스위치는 계속 조작할 수 있다', (tester) async {
    final api = _FakeSettingsApi();

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationSettingsScreen(
          api: api,
          tokenLoader: () async => 'token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 통일된 명사형 문구가 보인다.
    expect(find.text('전체 알림'), findsOneWidget);
    for (final title in [
      '콕 찌르기',
      '일정 전날',
      '일정 당일',
      '새 멤버 참여',
      '멤버 방 나가기',
      '담당 투두 추가',
      '자료 분석 결과',
    ]) {
      await tester.scrollUntilVisible(find.text(title), 300);
      expect(find.text(title), findsOneWidget);
    }

    // 목록 맨 위로 되돌려 "전체 알림" 스위치를 만난다.
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();

    // 전체 알림 끄기 → 개별 7종이 한 번에 꺼지고, 파생값 allEnabled도 false로 저장된다.
    await tester.tap(find.byKey(const ValueKey('all-notifications-switch')));
    await tester.pumpAndSettle();
    expect(api.saved?.allEnabled, isFalse);
    expect(api.saved?.pokeEnabled, isFalse);
    expect(api.saved?.scheduleDayBeforeEnabled, isFalse);
    expect(api.saved?.archiveAnalysisDoneEnabled, isFalse);

    // 전체가 꺼져도 개별 스위치는 비활성이 아니다(마스터 차단 폐지).
    final poke = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('poke-notifications-switch')),
    );
    expect(poke.onChanged, isNotNull);

    // 전체가 꺼진 상태에서 개별 하나만 다시 켤 수 있다(선택 수신).
    await tester.tap(find.byKey(const ValueKey('poke-notifications-switch')));
    await tester.pumpAndSettle();
    expect(api.saved?.pokeEnabled, isTrue);
    // 나머지는 여전히 꺼져 있으니 전체(파생)는 계속 false.
    expect(api.saved?.allEnabled, isFalse);
  });

  testWidgets('프로필 수정은 사진·닉네임·변경 불가 아이디를 한 화면에서 편집한다', (tester) async {
    final api = _FakeSettingsApi();

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSettingsScreen(api: api, tokenLoader: () async => 'token'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('프로필 수정'), findsOneWidget);
    expect(find.text('프로필 사진은 멤버 아바타로도 쓰여요'), findsOneWidget);
    expect(find.text('아이디는 변경할 수 없어요'), findsOneWidget);
    expect(find.text('minname01'), findsOneWidget);

    final nicknameField = tester.widget<TextField>(
      find.byKey(const ValueKey('profile-nickname-field')),
    );
    expect(nicknameField.maxLength, 10);
  });

  testWidgets('프로필 사진을 올린 뒤 저장하면 공개 URL을 프로필에 반영한다', (tester) async {
    final api = _FakeSettingsApi();

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSettingsScreen(
          api: api,
          tokenLoader: () async => 'token',
          photoPicker: (_) async => XFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            name: 'profile.jpg',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-photo-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(api.uploadedPhotoBytes, [1, 2, 3]);
    expect(api.savedProfileImage, 'https://storage.test/profile/me');
  });

  testWidgets('현재 방 설정은 기존 방 값을 프리필하고 자동 종료를 안내한다', (tester) async {
    final room = RoomSummary(
      id: 7,
      name: '여름 알고리즘 스터디',
      goal: '코딩테스트 통과하기',
      status: 'ACTIVE',
      startDate: DateTime(2026, 7, 28),
      endDate: DateTime(2026, 8, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RoomSettingsScreen(room: room, tokenLoader: () async => 'token'),
      ),
    );

    expect(find.text('여름 알고리즘 스터디'), findsOneWidget);
    expect(find.text('대표 이미지 (선택)'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(find.text('기한이 지나면 방이 자동으로 종료 상태로 전환돼요'), findsOneWidget);
  });

  testWidgets('방 멤버 관리는 현재 사용자와 개인 진행률을 구분해 보여준다', (tester) async {
    final api = _FakeSettingsApi();
    final room = RoomSummary(
      id: 7,
      name: '여름 알고리즘 스터디',
      goal: '코딩테스트 통과하기',
      status: 'ACTIVE',
      startDate: DateTime(2026, 7, 28),
      endDate: DateTime(2026, 8, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MembersSettingsScreen(
          room: room,
          api: api,
          tokenLoader: () async => 'token',
          currentUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('민네임 (나)'), findsOneWidget);
    expect(find.text('개인 진행률 90%'), findsOneWidget);
    expect(find.text('K7QP-2M9X'), findsOneWidget);
    final progress = tester.widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('member-progress-me')),
    );
    expect(progress.value, 0.9);
  });

  testWidgets('멤버 관리에서 공유 > 카카오톡을 탭하면 템플릿 초대 데이터를 전달한다', (tester) async {
    final api = _FakeSettingsApi();
    final room = RoomSummary(
      id: 7,
      name: '여름 알고리즘 스터디',
      goal: '코딩테스트 통과하기',
      status: 'ACTIVE',
      startDate: DateTime(2026, 7, 28),
      endDate: DateTime(2026, 8, 10),
    );
    InviteShareData? kakaoInvite;

    await tester.pumpWidget(
      MaterialApp(
        home: MembersSettingsScreen(
          room: room,
          api: api,
          tokenLoader: () async => 'token',
          currentUserId: 'me',
          shareKakao: (invite) async => kakaoInvite = invite,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('공유'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카카오톡'));
    await tester.pumpAndSettle();

    expect(kakaoInvite, isNotNull);
    expect(kakaoInvite?.code, 'K7QP-2M9X');
    expect(kakaoInvite?.roomName, '여름 알고리즘 스터디');
  });

  testWidgets('멤버 관리에서 공유 > 더보기는 OS 공유 시트를 연다', (tester) async {
    final api = _FakeSettingsApi();
    final room = RoomSummary(
      id: 7,
      name: '여름 알고리즘 스터디',
      goal: '코딩테스트 통과하기',
      status: 'ACTIVE',
      startDate: DateTime(2026, 7, 28),
      endDate: DateTime(2026, 8, 10),
    );
    String? shared;

    await tester.pumpWidget(
      MaterialApp(
        home: MembersSettingsScreen(
          room: room,
          api: api,
          tokenLoader: () async => 'token',
          currentUserId: 'me',
          shareInvite: (text, {sharePositionOrigin}) async => shared = text,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('공유'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('더보기'));
    await tester.pumpAndSettle();

    expect(shared, contains('K7QP-2M9X'));
    expect(shared, contains('여름 알고리즘 스터디'));
  });

  testWidgets('초대 공유 채널 선택 시트는 360px 화면 폭에서도 모두 보인다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final room = RoomSummary(
      id: 7,
      name: '여름 알고리즘 스터디',
      goal: '코딩테스트 통과하기',
      status: 'ACTIVE',
      startDate: DateTime(2026, 7, 28),
      endDate: DateTime(2026, 8, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MembersSettingsScreen(
          room: room,
          api: _FakeSettingsApi(),
          tokenLoader: () async => 'token',
          currentUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('공유'));
    await tester.pumpAndSettle();

    expect(find.text('초대 코드 공유'), findsOneWidget);
    expect(find.text('카카오톡'), findsOneWidget);
    expect(find.text('인스타그램'), findsOneWidget);
    expect(find.text('더보기'), findsOneWidget);
  });

  testWidgets('가입일(createdAt)이 오면 "MODI와 함께한 지 N일차" 문구를 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: _JoinDateSettingsApi(),
          tokenLoader: () async => 'token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 오늘 가입 → "1일차". 폴백 문구는 뜨지 않는다.
    expect(find.textContaining('함께한 지'), findsOneWidget);
    expect(find.textContaining('일차'), findsOneWidget);
    expect(find.textContaining('함께하는 중'), findsNothing);
  });

  testWidgets('가입일이 없으면 "MODI와 함께하는 중!" 폴백을 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          api: _FakeSettingsApi(),
          tokenLoader: () async => 'token',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('함께하는 중'), findsOneWidget);
  });
}

class _FakeSettingsApi extends SettingsApi {
  NotificationSettings? saved;
  List<int>? uploadedPhotoBytes;
  String? savedProfileImage;
  int fetchProfileCallCount = 0;

  @override
  Future<UserProfile> fetchProfile(String idToken) async {
    fetchProfileCallCount++;
    return const UserProfile(userId: 'minname01', nickname: '민네임');
  }

  // 활동 카드는 이 테스트들의 관심사가 아니라 네트워크를 타지 않게 미제공 처리한다.
  @override
  Future<MyActivitySummary> fetchCharacter(String idToken) =>
      throw UnimplementedError();

  @override
  Future<String> uploadProfilePhoto(
    String idToken, {
    required List<int> bytes,
  }) async {
    uploadedPhotoBytes = bytes;
    return 'https://storage.test/profile/me';
  }

  @override
  Future<UserProfile> updateProfile(
    String idToken, {
    required String nickname,
    String? profileImage,
  }) async {
    savedProfileImage = profileImage;
    return UserProfile(
      userId: 'minname01',
      nickname: nickname,
      profileImage: profileImage,
    );
  }

  @override
  Future<List<SettingsMember>> fetchMembers(String idToken, int roomId) async {
    return const [
      SettingsMember(
        userId: 'me',
        nickname: '민네임',
        assignedTotal: 10,
        assignedDone: 9,
      ),
      SettingsMember(
        userId: 'friend',
        nickname: '조딘엄',
        assignedTotal: 4,
        assignedDone: 3,
      ),
    ];
  }

  @override
  Future<String> fetchInviteCode(String idToken, int roomId) async {
    return 'K7QP-2M9X';
  }

  @override
  Future<NotificationSettings> fetchNotificationSettings(String idToken) async {
    return const NotificationSettings(allEnabled: true, pokeEnabled: true);
  }

  @override
  Future<NotificationSettings> updateNotificationSettings(
    String idToken,
    NotificationSettings settings,
  ) async {
    saved = settings;
    return settings;
  }
}

class _KakaoSettingsApi extends _FakeSettingsApi {
  @override
  Future<UserProfile> fetchProfile(String idToken) async {
    return const UserProfile(
      userId: 'minname01',
      nickname: '민네임',
      loginProvider: 'kakao',
    );
  }
}

class _JoinDateSettingsApi extends _FakeSettingsApi {
  @override
  Future<UserProfile> fetchProfile(String idToken) async {
    return UserProfile(
      userId: 'minname01',
      nickname: '민네임',
      createdAt: DateTime.now(),
    );
  }
}

class _LastMemberSettingsApi extends _FakeSettingsApi {
  @override
  Future<List<SettingsMember>> fetchMembers(String idToken, int roomId) async {
    return const [
      SettingsMember(
        userId: 'me',
        nickname: '민네임',
        assignedTotal: 10,
        assignedDone: 9,
      ),
    ];
  }
}

/// 방을 나갈 때마다 그 방을 목록에서 지워 다음 [RoomSession.loadRooms] 호출이
/// 실제 서버처럼 남은 방만 반환하게 하는 fake.
class _LeaveRoomFakeRoomApi extends RoomApi {
  _LeaveRoomFakeRoomApi({required List<RoomSummary> remaining})
    : _remaining = List.of(remaining);

  final List<RoomSummary> _remaining;

  void remove(int roomId) {
    _remaining.removeWhere((room) => room.id == roomId);
  }

  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async {
    return _remaining
        .map(
          (room) => {
            'id': room.id,
            'name': room.name,
            'goal': room.goal,
            'status': room.status,
            'startDate': room.startDate.toIso8601String(),
            'endDate': room.endDate.toIso8601String(),
          },
        )
        .toList();
  }
}

class _LeaveRoomSettingsApi extends _FakeSettingsApi {
  _LeaveRoomSettingsApi(this._roomApi);

  final _LeaveRoomFakeRoomApi _roomApi;
  final List<int> leftRoomIds = [];

  @override
  Future<void> leaveRoom(String idToken, int roomId) async {
    leftRoomIds.add(roomId);
    _roomApi.remove(roomId);
  }
}

/// 로그인 사용자가 없는 상태를 흉내내 [AppSession.refreshMembership]이 실제 Firebase나
/// 네트워크를 타지 않고 조용히 끝나게 한다 — 이 테스트의 관심사는 방 나가기 흐름이지
/// 멤버십 재확인이 아니다.
class _NoOpAuthSessionProvider implements AuthSessionProvider {
  @override
  AuthUserSnapshot? get currentUser => null;

  @override
  Stream<AuthUserSnapshot?> get authStateChanges => const Stream.empty();

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;

  @override
  Future<void> signOut() async {}
}
