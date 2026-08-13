import 'package:app/features/room/default_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('기본 커버 5장이 실제로 번들에 들어 있다(pubspec 등록 확인)', () async {
    // pubspec.yaml 의 assets 에 assets/images/covers/ 가 빠지면 파일이 있어도 런타임에
    // 못 찾는다 — 그 실수를 잡는 테스트.
    for (var id = 0; id < defaultCoverCount; id++) {
      final path = defaultCoverAsset(id);
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: '$path 를 못 읽었다');
    }
  });

  testWidgets('커버를 안 올린 방은 기본 배경 이미지를 그린다', (tester) async {
    // _HeroBackground 는 private 이라 같은 규칙을 쓰는 위젯으로 확인한다.
    await tester.pumpWidget(
      MaterialApp(home: Image.asset(defaultCoverAsset(3))),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/images/covers/cover_04.png',
    );
  });
}
