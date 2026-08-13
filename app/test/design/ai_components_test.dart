import 'dart:math' as math;

import 'package:app/design/ai_hint_banner.dart';
import 'package:app/design/ai_sparkle_button.dart';
import 'package:app/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 배너용 — 가로로 늘어나는 컴포넌트라 폭을 정해 감싼다(제약이 tight).
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  );

  /// 버튼용 — 실제 사용처(`Positioned`)처럼 **느슨한 제약**을 준다. tight 로 감싸면
  /// 위젯이 스스로 정한 크기와 무관하게 부모 폭으로 늘어나 크기 검증이 무의미해진다.
  Widget hostLoose(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  group('AiSparkleButton', () {
    testWidgets('60px 원에 아이콘 하나만 있고 텍스트는 없다', (tester) async {
      await tester.pumpWidget(hostLoose(AiSparkleButton(onTap: () {})));

      expect(tester.getSize(find.byType(AiSparkleButton)), const Size(60, 60));
      expect(find.byType(Text), findsNothing, reason: '라벨 없이 아이콘만');

      final image = tester.widget<Image>(find.byType(Image));
      expect(
        (image.image as AssetImage).assetName,
        'assets/icons/icon_ai_sparkle.png',
      );
      expect(tester.getSize(find.byType(Image)), const Size(28, 28));
    });

    testWidgets('흰 원 + 그림자이고, 탭하면 콜백이 온다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(hostLoose(AiSparkleButton(onTap: () => taps++)));

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(AiSparkleButton),
          matching: find.byType(Material),
        ),
      );
      expect(material.color, AppColors.surface);
      expect(material.shape, isA<CircleBorder>());

      final decorated = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(AiSparkleButton),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = decorated.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.boxShadow, AppElevation.float);

      await tester.tap(find.byType(AiSparkleButton));
      expect(taps, 1);
    });

    testWidgets('텍스트가 없으므로 스크린리더 이름을 따로 준다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(hostLoose(AiSparkleButton(onTap: () {})));

      expect(find.bySemanticsLabel('AI로 생성하기'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('아이콘·크기를 바꿔 다른 AI 액션에도 쓸 수 있다', (tester) async {
      await tester.pumpWidget(
        hostLoose(
          AiSparkleButton(
            onTap: () {},
            iconAsset: 'assets/icons/icon_ai_loading.png',
            semanticLabel: 'AI 요약',
            size: 48,
            iconSize: 20,
          ),
        ),
      );

      expect(tester.getSize(find.byType(AiSparkleButton)), const Size(48, 48));
      expect(tester.getSize(find.byType(Image)), const Size(20, 20));
      expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        'assets/icons/icon_ai_loading.png',
      );
    });
  });

  group('AiHintBanner', () {
    testWidgets('지정한 규격(높이 40 · radius 16 · 아이콘 20 · 문구 13px)으로 그린다', (
      tester,
    ) async {
      await tester.pumpWidget(host(const AiHintBanner(text: '안내 문구')));

      expect(tester.getSize(find.byType(AiHintBanner)).height, 40);
      expect(tester.getSize(find.byType(Image)), const Size(20, 20));
      expect(tester.widget<Text>(find.text('안내 문구')).style?.fontSize, 13);

      // 바깥(그라데이션) 박스의 라운드.
      final outer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AiHintBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = outer.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(AppRadius.control));
    });

    testWidgets('테두리는 AI 그라데이션 두 색을 45°로 쓰고, 안쪽은 흰 배경이다', (tester) async {
      await tester.pumpWidget(host(const AiHintBanner(text: '안내 문구')));

      final border =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(AiHintBanner),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      final gradient = border.gradient as LinearGradient;
      expect(gradient.colors, [
        AppColors.aiGradientStart,
        AppColors.aiGradientEnd,
      ]);
      expect(
        (gradient.transform as GradientRotation).radians,
        closeTo(-math.pi / 4, 1e-9),
        reason: '45° (왼쪽 아래 → 오른쪽 위)',
      );

      // 안쪽 흰 면은 Material 이다(Scaffold 밖에서도 잉크가 동작하도록).
      final inner = tester.widget<Material>(
        find.descendant(
          of: find.byType(AiHintBanner),
          matching: find.byType(Material),
        ),
      );
      expect(inner.color, AppColors.surface);
      // 테두리 2px → 안쪽 라운드는 그만큼 작다(16-2).
      expect(inner.borderRadius, BorderRadius.circular(AppRadius.control - 2));
    });

    testWidgets('테두리는 2px 이고, 민트색 글로우가 오프셋 0으로 사방에 깔린다', (tester) async {
      await tester.pumpWidget(host(const AiHintBanner(text: '안내 문구')));

      final outer = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AiHintBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      // 테두리 두께 = 그라데이션 박스의 안쪽 패딩.
      expect(outer.padding, const EdgeInsets.all(2));

      final shadows = (outer.decoration as BoxDecoration).boxShadow!;
      expect(shadows, hasLength(1));
      final glow = shadows.single;
      expect(glow.offset, Offset.zero, reason: 'x·y 0 — 사방으로 고르게');
      expect(
        Color(glow.color.toARGB32() | 0xFF000000),
        AppColors.aiGradientStart,
        reason: '핑크가 아니라 민트(ai-gradient-start)',
      );
      expect(glow.color.a, lessThan(0.5), reason: '약하게');
      expect(glow.blurRadius, greaterThan(0));
    });

    testWidgets('문구가 길면 남는 폭을 다 쓰고 말줄임으로 자른다', (tester) async {
      await tester.pumpWidget(
        host(
          const AiHintBanner(
            text: '아주 긴 문구가 들어와도 배너 높이는 40으로 유지되고 한 줄로 잘려야 한다 그래야 레이아웃이 안 깨진다',
          ),
        ),
      );

      expect(tester.getSize(find.byType(AiHintBanner)).height, 40);
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('문구·아이콘을 바꿔 다른 곳에서도 쓸 수 있다', (tester) async {
      await tester.pumpWidget(
        host(
          const AiHintBanner(
            text: '다른 화면 문구',
            iconAsset: 'assets/icons/icon_ai_loading.png',
          ),
        ),
      );

      expect(find.text('다른 화면 문구'), findsOneWidget);
      expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        'assets/icons/icon_ai_loading.png',
      );
    });

    testWidgets('onTap 을 주면 누를 수 있고, 없으면 표시 전용이다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(AiHintBanner(text: '누를 수 있음', onTap: () => taps++)),
      );
      await tester.tap(find.byType(AiHintBanner));
      expect(taps, 1);

      await tester.pumpWidget(host(const AiHintBanner(text: '표시 전용')));
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
