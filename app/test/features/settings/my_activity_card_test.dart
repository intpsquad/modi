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

  // `GET /me/character`(마이페이지)가 #68로 사라지면서 계약 파싱 테스트를 여기로 옮겼다.
  // 같은 스키마를 멤버 화면의 `GET /rooms/{id}/members/{userId}/character`가 그대로 쓴다.
  group('MyActivitySummary.fromJson', () {
    test('캐릭터 응답 계약을 카드 표시 단위로 파싱한다', () {
      final summary = MyActivitySummary.fromJson(const {
        'characterId': 'PROCRASTINATOR',
        'name': '미루기 장인',
        'copy': '내일의 나를 믿는 타입',
        'why': '몰아서 끝내고 있어요',
        'evolveTo': 'SPRINTER',
        'evolveProgress': 0.55,
        'evolveHint': '3일 연속 완료하면 진화해요',
        'confidence': 'LOW',
        'activityStats': {
          'completed': 128,
          'streak': 19,
          'deadlineKeptRate': 0.78,
          'helpGiven': 23,
          'shared': 12,
          'dueDateCompletedCount': 5,
        },
      });

      expect(summary.characterId, 'PROCRASTINATOR');
      expect(summary.characterName, '미루기 장인');
      expect(summary.characterQuote, '내일의 나를 믿는 타입');
      expect(summary.deadlineKeptPercent, 78); // 0.78 → %
      expect(summary.bestStreakDays, 19);
      expect(summary.sharedCount, 12);
      expect(summary.completedCount, 128);
    });

    test('마감일 있는 완료 투두가 없으면 마감 준수율은 0%가 아니라 표시 안 함(null)이다', () {
      final summary = MyActivitySummary.fromJson(const {
        'characterId': 'WARMING_UP',
        'name': '정체불명',
        'copy': '곧 정체가 드러나요',
        'why': '투두를 더 완료하면 캐릭터가 드러나요',
        'confidence': 'LOW',
        'activityStats': {
          'completed': 3,
          'streak': 0,
          'deadlineKeptRate': 0.0,
          'helpGiven': 0,
          'shared': 0,
          'dueDateCompletedCount': 0,
        },
      });

      expect(summary.deadlineKeptPercent, isNull);
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
