import 'package:app/features/settings/my_activity_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('characterAssetPath', () {
    test('알려진 캐릭터 id를 로컬 에셋 경로로 매핑한다', () {
      expect(
        characterAssetPath('PROCRASTINATOR'),
        'assets/images/characters/procrastinator.png',
      );
      expect(characterAssetPath('THE_J'), 'assets/images/characters/the_j.png');
      expect(
        characterAssetPath('WARMING_UP'),
        'assets/images/characters/warming_up.png',
      );
    });

    test('SPRINTER는 전용 아트(sprinter.png)로 매핑한다', () {
      expect(
        characterAssetPath('SPRINTER'),
        'assets/images/characters/sprinter.png',
      );
    });

    test('null·미지정 id는 warming_up으로 폴백한다', () {
      expect(
        characterAssetPath(null),
        'assets/images/characters/warming_up.png',
      );
      expect(
        characterAssetPath('NOPE'),
        'assets/images/characters/warming_up.png',
      );
    });
  });

  group('MyActivityCard', () {
    Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('summary가 있으면 캐릭터 이미지·이름·카피·지표 칩을 그린다', (tester) async {
      await tester.pumpWidget(
        wrap(
          const MyActivityCard(
            nickname: '예원',
            summary: MyActivitySummary(
              characterId: 'PROCRASTINATOR',
              characterName: '미루기 장인',
              characterQuote: '내일의 나를 믿는 타입',
              characterDetail: '몰아서 끝내고 있어요',
              deadlineKeptPercent: 78,
              bestStreakDays: 19,
              sharedCount: 12,
              completedCount: 128,
            ),
          ),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        'assets/images/characters/procrastinator.png',
      );

      expect(find.text('미루기 장인'), findsOneWidget);
      expect(find.text('"내일의 나를 믿는 타입"'), findsOneWidget);
      expect(find.textContaining('마감 준수'), findsOneWidget);
      expect(find.textContaining('완료 항목'), findsOneWidget);
    });

    testWidgets('summary가 없으면 정체불명 placeholder를 그린다', (tester) async {
      await tester.pumpWidget(wrap(const MyActivityCard(nickname: '예원')));
      await tester.pump();

      expect(find.text('정체불명'), findsOneWidget);
      // placeholder는 아이콘만 쓰고 캐릭터 이미지는 없다.
      expect(find.byType(Image), findsNothing);
    });
  });
}
