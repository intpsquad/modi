import 'package:app/features/room/default_cover.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaultCoverAsset', () {
    test('방 id 로 5장 중 하나를 고르고, 같은 방은 항상 같은 배경이다', () {
      expect(defaultCoverAsset(1), 'assets/images/covers/cover_02.png');
      expect(defaultCoverAsset(1), defaultCoverAsset(1)); // 호출해도 안 바뀐다
      expect(defaultCoverAsset(5), defaultCoverAsset(10)); // 5마다 순환
    });

    test('경계값도 파일 범위(01~05) 안이다', () {
      for (final id in [0, 1, 4, 5, 6, 99, 1000, -3]) {
        expect(
          defaultCoverAsset(id),
          matches(RegExp(r'^assets/images/covers/cover_0[1-5]\.png$')),
          reason: 'roomId=$id',
        );
      }
    });

    test('연속한 방들은 서로 다른 배경을 받는다', () {
      final assets = {
        for (var id = 1; id <= defaultCoverCount; id++) defaultCoverAsset(id),
      };
      expect(assets.length, defaultCoverCount, reason: '5개가 골고루 쓰인다');
    });
  });
}
