import 'package:app/features/home/home_api.dart';
import 'package:app/features/home/home_hero.dart';
import 'package:app/features/room/default_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RoomInfo room({DateTime? endDate, String? coverImage}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return RoomInfo(
      id: 1,
      name: '테스트방',
      goal: '목표',
      startDate: today,
      endDate: endDate ?? today.add(const Duration(days: 14)),
      status: 'ACTIVE',
      coverImageUrl: coverImage,
    );
  }

  Widget host(HomeHero hero) => MaterialApp(
    home: Scaffold(body: SizedBox(height: 300, width: 400, child: hero)),
  );

  HomeHero hero({
    required RoomInfo r,
    double? progress,
    int? todoDone,
    int? todoTotal,
    bool menuOpen = false,
    int unreadNotificationCount = 0,
  }) => HomeHero(
    room: r,
    progress: progress,
    todoDone: todoDone,
    todoTotal: todoTotal,
    menuOpen: menuOpen,
    onRoomTap: () {},
    onNotificationsTap: () {},
    unreadNotificationCount: unreadNotificationCount,
  );

  testWidgets('D-day와 종료일, 방이름이 히어로에 표시된다', (tester) async {
    await tester.pumpWidget(host(hero(r: room())));
    await tester.pumpAndSettle();

    expect(find.text('테스트방'), findsOneWidget);
    expect(find.text('D-14'), findsOneWidget);
  });

  testWidgets('종료일이 "YYYY.MM.DD 종료" 형태로 표시된다', (tester) async {
    // 2026-08-07 요청: '디데이' 접두 라벨 폐기, 점 포맷 날짜 뒤에 '종료'.
    await tester.pumpWidget(host(hero(r: room())));
    await tester.pumpAndSettle();

    final label = find.byKey(const ValueKey('hero-dday-label'));
    expect(label, findsOneWidget);
    final text = tester.widget<Text>(label).data!;
    expect(text, endsWith(' 종료'));
    expect(text, contains('.'), reason: '점 포맷 날짜');
    expect(text, isNot(contains('디데이')));
  });

  testWidgets('방 전환 시트가 열려 있으면 토글이 180도 돌아간다', (tester) async {
    // 2026-08-05 요청: 바텀시트 올라가면 180도 회전, 닫힐 때 복구.
    await tester.pumpWidget(host(hero(r: room(), menuOpen: false)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
      0.0,
    );

    await tester.pumpWidget(host(hero(r: room(), menuOpen: true)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
      0.5,
      reason: '0.5회전 = 180도',
    );

    // 닫히면 원래대로.
    await tester.pumpWidget(host(hero(r: room(), menuOpen: false)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns,
      0.0,
    );
  });

  testWidgets('종료일 당일이면 D-DAY로 표시된다', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await tester.pumpWidget(host(hero(r: room(endDate: today))));
    await tester.pumpAndSettle();

    expect(find.text('D-DAY'), findsOneWidget);
  });

  testWidgets('진행률이 없으면 진행률 바와 개수를 숨긴다', (tester) async {
    await tester.pumpWidget(host(hero(r: room())));
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('완료'), findsNothing);
  });

  testWidgets('진행률이 있으면 진행률 바와 완료/전체 개수를 보여준다', (tester) async {
    await tester.pumpWidget(
      host(hero(r: room(), progress: 0.6, todoDone: 24, todoTotal: 40)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('함께 달성한 투두'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
  });

  testWidgets('안읽은 알림이 없으면 벨 배지가 안 보인다', (tester) async {
    await tester.pumpWidget(host(hero(r: room(), unreadNotificationCount: 0)));
    await tester.pumpAndSettle();

    expect(find.text('0'), findsNothing);
  });

  testWidgets('안읽은 알림이 있으면 벨에 개수 배지가 보인다', (tester) async {
    await tester.pumpWidget(host(hero(r: room(), unreadNotificationCount: 3)));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('안읽은 알림이 9개를 넘으면 "9+"로 캡한다', (tester) async {
    await tester.pumpWidget(host(hero(r: room(), unreadNotificationCount: 42)));
    await tester.pumpAndSettle();

    expect(find.text('9+'), findsOneWidget);
    expect(find.text('42'), findsNothing);
  });

  testWidgets('커버 이미지가 없으면 방 id 기준 기본 배경(에셋)을 그린다', (tester) async {
    // 2026-08-05 요청 4: 그라데이션만 두지 않고 기본 배경 5종 중 하나를 깐다.
    // 네트워크 이미지는 여전히 없어야 한다(주소가 없으므로).
    await tester.pumpWidget(host(hero(r: room(coverImage: null))));
    await tester.pumpAndSettle();

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(1));
    expect(
      (images.single.image as AssetImage).assetName,
      defaultCoverAsset(1), // room(id: 1)
    );
  });
}
