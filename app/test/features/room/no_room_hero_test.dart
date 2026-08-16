import 'package:app/features/room/no_room_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// S-03(온보딩 게이트)과 S-06(홈 방없음)이 공유하는 히어로 — specs/0004-방-생성-참여.md.
///
/// 두 화면의 통합 동작은 각각 room_setup_screen_test.dart / home_screen_test.dart 가 본다.
/// 여기서는 **공유 부분만** 고정한다 — 그래야 한쪽을 고치다 다른 쪽이 조용히 바뀌는 걸 잡는다.
void main() {
  Future<void> pump(WidgetTester tester, String title) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NoRoomHero(title: title)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('타이틀은 호출자가 넘긴 것을 그대로 쓴다', (tester) async {
    await pump(tester, '현재 진행 중인 방이 없어요!');

    expect(find.text('현재 진행 중인 방이 없어요!'), findsOneWidget);
  });

  testWidgets('원형 그래픽·서브 문구·CTA 2종이 스펙대로 렌더된다', (tester) async {
    await pump(tester, '아무 타이틀');

    expect(find.byIcon(Icons.card_giftcard), findsOneWidget);
    expect(find.text('팀과 함께할 방을 만들거나, 초대코드로 참여하세요'), findsOneWidget);

    // Primary 는 풀폭 ElevatedButton, Secondary 는 고스트 TextButton (design.md).
    // 예전 홈의 임시 화면은 OutlinedButton "코드 입력" 이었다 — 그리로 되돌아가지 않게 막는다.
    expect(find.widgetWithText(ElevatedButton, '방 만들기'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '초대코드로 참여하기'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('CTA 2개뿐이다 — 지난 방 보기 같은 세 번째 링크를 두지 않는다', (tester) async {
    await pump(tester, '아무 타이틀');

    // full_spec.md:255 "CTA 2개". 사용자 확정 2026-08-16.
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
  });
}
