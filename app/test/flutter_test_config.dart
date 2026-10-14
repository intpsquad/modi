// 골든 비교에서 **래스터라이즈 잡음만** 통과시킨다.
//
// 이 파일은 `flutter test` 가 `test/` 아래 모든 테스트에 자동으로 끼워 넣는 훅이다.
// 러너가 만드는 부트스트랩이 `goldenFileComparator = LocalFileComparator(...)` 를
// 먼저 꽂고 그 다음에 `testExecutable` 을 부르기 때문에, 여기서 기본 comparator 를
// 감쌀 수 있다(flutter_tools/lib/src/test/flutter_platform.dart).
//
// ## 왜 필요한가 (2026-10-14, 이슈 #120)
//
// `test/features/settings/settings_flow_golden_test.dart` 가 **macOS 로컬에서만**
// 0.0205%(404px) 차이로 실패했다. 팀이 전부 Mac 이라 `flutter test` 가 늘 빨갰고,
// 그러면 진짜 회귀를 봐도 무시하게 된다.
//
// 흔히 짐작하는 "Linux CI 골든 vs macOS 로컬" 구도가 **아니다**:
//
//   - 그 테스트에는 이미 `skip: !io.Platform.isMacOS` 가 붙어 있고 CI `app` 잡은
//     `ubuntu-latest` 다. 즉 **CI 는 이 골든을 아예 돌린 적이 없다.**
//   - 커밋된 골든은 다른 팀원의 Mac 에서 생성됐다(2026-09-13, e0328fc).
//     어긋난 건 Mac ↔ Linux 가 아니라 **Mac ↔ Mac** 이다.
//   - 폰트 차이도 아니다. 404px 은 5번째 화면의 「공유」·「재발급」
//     `OutlinedButton` **둥근 모서리 4곳에만** 몰려 있었고(bbox 326×48), 직선
//     테두리·글자·아이콘은 완전히 일치했다. 그 두 버튼이 캔버스에서 대비가 가장
//     높은 곡선 스트로크라(`design/theme.dart` 의 `BorderSide(foreground)`),
//     곡선 커버리지의 미세한 차이가 거기서만 픽셀로 드러난다.
//   - 같은 머신에서 3회 렌더가 바이트 단위로 동일했다. 플레이크가 아니라
//     머신 간 결정적 차이다.
//
// 골든은 재생성하지 않는다 — 재생성하면 실패가 다른 팀원 머신으로 옮겨갈 뿐이다.
//
// ## 왜 "차이 비율 N% 이하면 통과" 가 아닌가
//
// Flutter 문서가 예시로 드는 방식은 `diffPercent` 하나로 자르는 것이다. 그런데
// 이 골든에서 실측해 보면 **분리가 안 된다.** 버튼 라벨을 「공유」→「공유하기」로
// 바꾼 *진짜* 회귀가 0.0607%(1,199px)였다 — 잡음(0.0205%)의 고작 3배다.
// 그 사이에 선을 그으면 잡음을 먹이려다 회귀까지 먹는다.
//
// 대신 같은 두 경우를 여러 지표로 재서 실제로 갈리는 축을 골랐다:
//
// | 지표                  | 잡음 | 회귀(라벨 변경) |
// |-----------------------|------|-----------------|
// | 차이 픽셀 비율        | 0.0205% | 0.0607%  ← 3배, 못 쓴다 |
// | **채널 델타 > 128**   | **0px** | **347px** ← 완전히 갈린다 |
// | 차이 픽셀 수          | 404  | 1,199           |
//
// 안티에일리어싱은 가장자리의 *커버리지*만 흔든다(실측 최대 델타 92). 글리프나
// 아이콘이 생기고 사라지는 변화는 흰색↔검정을 오가므로 델타가 255 근처로 뛴다.
// 그래서 아래 두 관문을 **둘 다** 통과해야 잡음으로 인정한다.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// ① 한 픽셀이라도 채널 델타가 이 값을 넘으면 잡음이 아니다.
///
/// 구조가 바뀌면(글자·아이콘이 생기거나 사라지면) 흰색↔검정이 뒤집혀 델타가 255에
/// 가까워진다. 실측 잡음의 최댓값은 92였다. 이 관문 덕분에 **면적이 작은** 회귀도
/// 잡힌다 — 24px 아이콘 교체(≈576px)는 비율로는 0.03% 밖에 안 되지만 여기서 걸린다.
const int _maxChannelDelta = 128;

/// ② 델타가 작더라도 차이 픽셀이 이 비율을 넘으면 잡음이 아니다.
///
/// 색 토큰을 아주 조금 바꾸는 식의 "넓고 옅은" 변화를 잡는 뒷받침이다.
/// 실측 잡음이 0.0205% 라 약 2.4배 여유다(0.05% ≈ 987px).
const double _maxDiffRatio = 0.0005;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final LocalFileComparator base = goldenFileComparator as LocalFileComparator;
  goldenFileComparator = _RasterNoiseTolerantComparator(base.basedir);
  await testMain();
}

class _RasterNoiseTolerantComparator extends LocalFileComparator {
  // LocalFileComparator 는 "테스트 파일" URI 를 받아 그 디렉터리를 basedir 로 쓴다.
  // 우리가 가진 건 이미 계산된 basedir 뿐이라, 그 아래 아무 파일 이름이나 붙여
  // 같은 디렉터리가 다시 나오게 한다.
  _RasterNoiseTolerantComparator(Uri basedir)
    : super(Uri.parse('${basedir}flutter_test_config.dart'));

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final _PixelDiff? diff = await _measure(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (diff != null && diff.isClean) {
      return true;
    }
    if (diff != null && diff.isRasterNoise) {
      // 조용히 넘기지 않는다. 실측치가 천장으로 드리프트하는 걸 눈에 보이게 둔다.
      debugPrint('골든 "$golden": ${diff.describe()} — 래스터라이즈 잡음으로 보고 통과시켰다.');
      return true;
    }

    // 잡음이 아니면 기본 동작 그대로 — failures/ 에 비교 이미지 4종을 남기고 던진다.
    // (크기가 다르거나 디코드에 실패해 측정을 못 한 경우도 여기로 보낸다.)
    return super.compare(imageBytes, golden);
  }

  /// 두 PNG 를 디코드해 픽셀을 맞대 본다. 크기가 다르면 `null`.
  Future<_PixelDiff?> _measure(List<int> test, List<int> master) async {
    final ui.Image testImage = await _decode(test);
    final ui.Image masterImage = await _decode(master);
    try {
      if (testImage.width != masterImage.width ||
          testImage.height != masterImage.height) {
        return null;
      }
      final ByteData? testRgba = await testImage.toByteData();
      final ByteData? masterRgba = await masterImage.toByteData();
      if (testRgba == null || masterRgba == null) {
        return null;
      }

      final int totalPixels = testImage.width * testImage.height;
      var differing = 0;
      var maxDelta = 0;
      var overDelta = 0;
      for (var offset = 0; offset < totalPixels * 4; offset += 4) {
        if (testRgba.getUint32(offset) == masterRgba.getUint32(offset)) {
          continue;
        }
        differing++;
        var delta = 0;
        for (var channel = 0; channel < 4; channel++) {
          final int d =
              (testRgba.getUint8(offset + channel) -
                      masterRgba.getUint8(offset + channel))
                  .abs();
          if (d > delta) {
            delta = d;
          }
        }
        if (delta > maxDelta) {
          maxDelta = delta;
        }
        if (delta > _maxChannelDelta) {
          overDelta++;
        }
      }
      return _PixelDiff(
        differing: differing,
        totalPixels: totalPixels,
        maxDelta: maxDelta,
        overDelta: overDelta,
      );
    } finally {
      testImage.dispose();
      masterImage.dispose();
    }
  }

  static Future<ui.Image> _decode(List<int> bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(
      Uint8List.fromList(bytes),
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }
}

class _PixelDiff {
  const _PixelDiff({
    required this.differing,
    required this.totalPixels,
    required this.maxDelta,
    required this.overDelta,
  });

  /// 값이 다른 픽셀 수.
  final int differing;
  final int totalPixels;

  /// 그중 가장 큰 채널 델타.
  final int maxDelta;

  /// 채널 델타가 [_maxChannelDelta] 를 넘는 픽셀 수.
  final int overDelta;

  bool get isClean => differing == 0;

  double get ratio => differing / totalPixels;

  bool get isRasterNoise =>
      overDelta == 0 && ratio <= _maxDiffRatio && !isClean;

  String describe() =>
      '${(ratio * 100).toStringAsFixed(4)}% (${differing}px, 최대 델타 $maxDelta)';
}
