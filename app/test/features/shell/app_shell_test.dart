import 'package:app/features/room/room_session.dart';
import 'package:app/features/room/room_switch_hint.dart';
import 'package:app/features/shell/app_shell.dart';
import 'package:app/features/shell/tab_activation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// specs/0008-방-전환.md — 하단 네비 홈 버튼 롱프레스 트리거 + 최초 사용자 코치마크.

const _bubbleText = '홈을 꾹 누르면 방을 바꿀 수 있어요';
const _sheetTitle = '방 전환';

/// 코치마크가 뜨지 않는 prefs 상태(트리거 자체만 검증할 때 쓴다).
/// 오버레이가 떠 있으면 네비바를 덮어버려 롱프레스가 오버레이로 가로채인다.
const _prefsHintExhausted = {
  RoomSwitchHintPrefs.introShownKey: true,
  RoomSwitchHintPrefs.multiShownKey: true,
};

RoomSummary _room({required int id, required String status}) => RoomSummary(
  id: id,
  name: '방$id',
  goal: '목표-$id',
  status: status,
  startDate: DateTime(2026, 1, 1),
  endDate: DateTime(2026, 12, 31),
);

RoomSession _session(int activeRoomCount) {
  final session = RoomSession();
  session.rooms = [
    for (var i = 1; i <= activeRoomCount; i++) _room(id: i, status: 'ACTIVE'),
  ];
  session.currentRoomId = activeRoomCount > 0 ? 1 : null;
  return session;
}

const _branchPaths = ['/home', '/todos', '/schedule', '/archive', '/mypage'];

Widget _shellApp(RoomSession session, {String initialLocation = '/home'}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell, roomSession: session),
        branches: [
          for (final path in _branchPaths)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: path,
                  builder: (context, state) => Center(child: Text('본문 $path')),
                ),
              ],
            ),
        ],
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

/// 코치마크는 무한 반복 펄스라 pumpAndSettle이 타임아웃된다 — 고정 시간만 진행시킨다.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<bool?> _readBool(String key) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(key);
}

void main() {
  group('하단 네비 홈 버튼 롱프레스 트리거', () {
    setUp(() => SharedPreferences.setMockInitialValues(_prefsHintExhausted));

    testWidgets('홈 버튼을 길게 누르면 방 전환 시트가 열리고 "사용해봤음"으로 기록된다', (tester) async {
      await tester.pumpWidget(_shellApp(_session(1)));
      await tester.pumpAndSettle();

      // 아이콘이 PNG 에셋으로 바뀌어 find.byIcon을 못 쓴다 — 라벨로 홈 칸을 롱프레스한다.
      await tester.longPress(find.text('홈'));
      await tester.pumpAndSettle();

      expect(find.text(_sheetTitle), findsOneWidget);
      expect(await _readBool(RoomSwitchHintPrefs.usedKey), isTrue);
    });

    testWidgets('다른 탭에서 홈 버튼을 길게 눌러도 탭은 이동하지 않고 시트만 열린다', (tester) async {
      await tester.pumpWidget(
        _shellApp(_session(2), initialLocation: '/todos'),
      );
      await tester.pumpAndSettle();
      expect(find.text('본문 /todos'), findsOneWidget);

      await tester.longPress(find.text('홈'));
      await tester.pumpAndSettle();

      expect(find.text(_sheetTitle), findsOneWidget);
      // 투두 탭에 그대로 머문다 — 롱프레스는 "방 전환" 전용 제스처다.
      expect(find.text('본문 /todos'), findsOneWidget);
      expect(find.text('본문 /home'), findsNothing);
    });

    testWidgets('홈이 아닌 탭 버튼을 길게 누르면 아무 일도 일어나지 않는다', (tester) async {
      await tester.pumpWidget(_shellApp(_session(2)));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('투두'));
      await tester.pumpAndSettle();

      expect(find.text(_sheetTitle), findsNothing);
      expect(find.text('본문 /home'), findsOneWidget);
      expect(await _readBool(RoomSwitchHintPrefs.usedKey), isNull);
    });
  });

  group('코치마크 노출 규칙', () {
    testWidgets('최초 진입이면 진행중 방이 1개뿐이어도 코치마크가 뜬다', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_shellApp(_session(1)));
      await _pumpFrames(tester);

      expect(find.text(_bubbleText), findsOneWidget);
    });

    testWidgets('intro 코치마크는 바깥 탭으로 안 닫히고 다음 버튼으로만 진행·종료한다', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_shellApp(_session(1)));
      await _pumpFrames(tester);
      expect(find.text(_bubbleText), findsOneWidget);
      expect(find.text('다음'), findsOneWidget);

      // 화면 상단(구멍 밖) 탭 → 이제는 닫히지 않는다(버튼으로만 진행).
      await tester.tapAt(const Offset(400, 100));
      await _pumpFrames(tester);
      expect(find.text(_bubbleText), findsOneWidget);
      expect(await _readBool(RoomSwitchHintPrefs.introShownKey), isNull);

      // '다음' → 이 셸엔 멤버 아바타 앵커가 없어(홈 본문이 목업) 아바타 스텝을 건너뛰고 종료된다.
      await tester.tap(find.text('다음'));
      await tester.pump();
      expect(find.text(_bubbleText), findsNothing);
      expect(await _readBool(RoomSwitchHintPrefs.introShownKey), isTrue);

      // 다시 진입해도 1단계는 재노출되지 않는다(방이 1개라 2단계 조건도 미충족).
      await tester.pumpWidget(_shellApp(_session(1)));
      await _pumpFrames(tester);
      expect(find.text(_bubbleText), findsNothing);
    });

    testWidgets('진행중 방이 2개 이상이 되면 한 번 더 뜨고, 그 뒤로는 뜨지 않는다', (tester) async {
      SharedPreferences.setMockInitialValues({
        RoomSwitchHintPrefs.introShownKey: true,
      });

      await tester.pumpWidget(_shellApp(_session(2)));
      await _pumpFrames(tester);
      expect(find.text(_bubbleText), findsOneWidget);

      await tester.tapAt(const Offset(400, 100));
      await tester.pumpAndSettle();
      expect(await _readBool(RoomSwitchHintPrefs.multiShownKey), isTrue);

      await tester.pumpWidget(_shellApp(_session(2)));
      await _pumpFrames(tester);
      expect(find.text(_bubbleText), findsNothing);
    });

    testWidgets('이미 롱프레스로 방을 전환해본 사용자에게는 어느 단계도 뜨지 않는다', (tester) async {
      SharedPreferences.setMockInitialValues({
        RoomSwitchHintPrefs.usedKey: true,
      });

      await tester.pumpWidget(_shellApp(_session(2)));
      await _pumpFrames(tester);

      expect(find.text(_bubbleText), findsNothing);
    });

    testWidgets('코치마크의 구멍을 길게 누르면 그대로 방 전환 시트가 열린다', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(_shellApp(_session(2)));
      await _pumpFrames(tester);
      expect(find.text(_bubbleText), findsOneWidget);

      // 스포트라이트 구멍은 홈 버튼을 감싸므로 홈 칸 위치를 길게 누르면 구멍에 닿는다.
      await tester.longPressAt(tester.getCenter(find.text('홈')));
      await tester.pumpAndSettle();

      expect(find.text(_bubbleText), findsNothing);
      expect(find.text(_sheetTitle), findsOneWidget);
      expect(await _readBool(RoomSwitchHintPrefs.usedKey), isTrue);
    });
  });

  group('하단 네비 탭 라벨', () {
    setUp(() => SharedPreferences.setMockInitialValues(_prefsHintExhausted));

    testWidgets('탭은 5개이고 맨 오른쪽이 마이페이지다', (tester) async {
      // 2026-08-06 요청: "네비게이션 바 맨 오른쪽에 마이페이지 탭 하나 추가".
      await tester.pumpWidget(_shellApp(_session(1)));
      await _pumpFrames(tester);

      final destinations = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .toList();
      expect(destinations.length, 5);
      expect(destinations.map((d) => d.label).toList(), [
        '홈',
        '투두',
        '일정',
        '모아보기',
        '마이',
      ], reason: '순서가 곧 "맨 오른쪽" 요구다');
    });

    testWidgets('마이 탭 아이콘은 SVG이고 실제로 번들돼 있다', (tester) async {
      // pubspec에 에셋이 빠지면 analyze도 테스트도 통과하고 **런타임에만** 깨진다 —
      // 위젯 트리의 경로와 rootBundle 실물 로드를 함께 본다.
      await tester.pumpWidget(_shellApp(_session(1)));
      await _pumpFrames(tester);

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SvgPicture &&
              w.bytesLoader is SvgAssetLoader &&
              (w.bytesLoader as SvgAssetLoader).assetName ==
                  'assets/icons/nav_my.svg',
        ),
        findsWidgets,
      );
      expect(
        await rootBundle.loadString('assets/icons/nav_my.svg'),
        isNotEmpty,
        reason: 'nav_my.svg 이 번들에 없다(pubspec assets 확인)',
      );
    });

    testWidgets('마이페이지 탭을 누르면 그 브랜치로 이동한다', (tester) async {
      await tester.pumpWidget(_shellApp(_session(1)));
      await _pumpFrames(tester);
      expect(find.text('본문 /home'), findsOneWidget);

      await tester.tap(find.text('마이'));
      await tester.pumpAndSettle();

      expect(find.text('본문 /mypage'), findsOneWidget);
      expect(find.text('본문 /home'), findsNothing);
    });

    testWidgets('탭을 누를 때마다(전환·재탭) 그 탭 인덱스로 재탭 신호가 온다(맨위 스크롤용)', (tester) async {
      // 2026-08-10: 탭 이동 시 하위페이지 pop + 맨 위로 스크롤 — 셸은 매 탭마다 reselect 신호를
      // 쏘고, 스크롤은 각 탭 화면이 한다. (이전엔 재탭에서만 울렸는데 전환에서도 스크롤이 필요해졌다.)
      await tester.pumpWidget(_shellApp(_session(1)));
      await _pumpFrames(tester);

      var fired = 0;
      appTabActivation.reselect.addListener(() => fired++);
      addTearDown(() => appTabActivation.reselect.notify(-1));

      // 다른 탭으로의 "전환"도 그 탭 인덱스로 신호를 쏜다.
      await tester.tap(find.text('투두'));
      await tester.pumpAndSettle();
      expect(fired, 1);
      expect(appTabActivation.reselect.index, AppShell.todosIndex);

      // 같은 탭을 다시 눌러도 또 신호가 온다.
      await tester.tap(find.text('투두'));
      await tester.pumpAndSettle();
      expect(fired, 2);
      expect(appTabActivation.reselect.index, AppShell.todosIndex);
    });

    testWidgets('4번째 탭은 아카이브 SVG 아이콘 + "모아보기"이고 "아카이브"는 없다', (tester) async {
      await tester.pumpWidget(_shellApp(_session(1)));
      await _pumpFrames(tester);

      expect(find.text('모아보기'), findsOneWidget);
      expect(find.text('아카이브'), findsNothing);
      // 4번째 탭 아이콘이 SVG 에셋(아카이브)으로 렌더된다.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SvgPicture &&
              w.bytesLoader is SvgAssetLoader &&
              (w.bytesLoader as SvgAssetLoader).assetName ==
                  'assets/icons/nav_archive.svg',
        ),
        findsWidgets,
      );
    });
  });
}
