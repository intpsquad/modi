/// 🔴 **iOS 알림 배선을 AppDelegate 가 직접 깨운다**(2026-09-14, 이슈 #66).
///
/// 왜 필요한지·언제 지우는지는 `docs/fcm-setup.md` 한 곳에 적혀 있다. 여기서는 요약만 둔다:
/// `firebase_messaging` 15.2.10 이 iOS 알림 배선 전체를
/// `UIApplicationDidFinishLaunchingNotification` 관찰자 하나에 몰아 넣는데, 이 앱은 UIScene
/// 을 채택해 플러그인 등록이 그 알림 **뒤에** 일어나므로 그 관찰자가 영영 안 불린다.
/// 그래서 `AppDelegate` 가 그 알림을 직접 쏜다.
///
/// 네이티브라 동작은 단위 테스트로 못 본다(실기기 TestFlight 로만 검증된다). 이 테스트는
/// **그 코드가 조용히 사라지는 것**을 막는다 — 웹 약관을 앱 본문과 대조하는
/// `legal_web_sync_test.dart`, 초대 경로를 Caddy 설정과 대조하는 `invite_share_test.dart` 와
/// 같은 방식의 드리프트 가드다.
///
/// 🔴 **주석을 걷어내고 본다.** 그냥 문자열을 찾으면 호출을 주석 처리하는 것만으로 초록이
/// 된다 — `invite_share_test.dart` 가 2026-08-31 에 정확히 그 실수를 했다. 같은 실수를
/// 되풀이하지 않으려고 주석 제거 + 함수 본문 한정 + `#if` 배제까지 본다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// `flutter test` 는 `app/` 에서 돈다.
  final appDelegate = File('ios/Runner/AppDelegate.swift');

  /// 주석을 걷어낸 소스. `//` 한 줄 주석만 걷으면 된다 — 이 파일에 블록 주석은 없다.
  String sourceWithoutComments() => appDelegate.readAsStringSync().replaceAll(
    RegExp(r'^\s*//.*$', multiLine: true),
    '',
  );

  /// `didInitializeImplicitFlutterEngine` 함수 본문만 잘라 낸다. 중괄호 깊이를 세어
  /// 자른다 — 호출을 파일 아무 데나(예: 아무도 안 부르는 함수) 옮겨 두는 우회를 막는다.
  String engineInitBody() {
    final source = sourceWithoutComments();
    final start = source.indexOf('func didInitializeImplicitFlutterEngine');
    expect(start, greaterThanOrEqualTo(0), reason: '엔진 초기화 콜백을 찾지 못했다');

    var depth = 0;
    var opened = false;
    for (var i = source.indexOf('{', start); i < source.length; i++) {
      if (source[i] == '{') {
        depth++;
        opened = true;
      } else if (source[i] == '}') {
        depth--;
        if (opened && depth == 0) return source.substring(start, i);
      }
    }
    fail('엔진 초기화 콜백의 본문 끝을 찾지 못했다');
  }

  group('iOS 알림 배선', () {
    test('AppDelegate 가 앱 실행 알림을 직접 쏜다', () {
      expect(
        appDelegate.existsSync(),
        isTrue,
        reason: '${appDelegate.path} 가 없다',
      );

      expect(
        engineInitBody(),
        contains('UIApplication.didFinishLaunchingNotification'),
        reason:
            'AppDelegate 가 앱 실행 알림을 다시 쏘지 않는다. UIScene 앱에서는 '
            'firebase_messaging 의 알림 배선(APNs 등록·스위즐러·알림 델리게이트)이 통째로 '
            '실행되지 않아서, 푸시가 하나도 오지 않고 알림을 눌러도 아무 일이 없다. '
            '자세한 내용은 docs/fcm-setup.md.',
      );
    });

    /// 관찰자는 플러그인 등록에서 생긴다 — 그 전에 쏘면 아무도 안 듣는다.
    test('알림은 플러그인 등록 뒤에 쏜다', () {
      final body = engineInitBody();
      final register = body.indexOf('GeneratedPluginRegistrant.register');
      final post = body.indexOf('UIApplication.didFinishLaunchingNotification');

      expect(register, greaterThanOrEqualTo(0), reason: '플러그인 등록부를 찾지 못했다');
      expect(
        post,
        greaterThan(register),
        reason:
            '알림을 플러그인 등록보다 먼저 쏜다. 그러면 그 알림을 들을 관찰자가 아직 없어서 '
            '아무 효과가 없다.',
      );
    });

    /// 알림으로 앱이 켜진 경우를 살리려면 `launchOptions` 를 실어 보내야 한다.
    /// 안 실으면 `getInitialMessage()` 가 항상 비어, 종료 상태에서 알림을 눌러 들어와도
    /// 해당 화면으로 이동하지 않는다.
    test('앱 실행 정보를 알림에 실어 보낸다', () {
      expect(
        engineInitBody(),
        contains('launchOptions'),
        reason: 'launchOptions 를 안 실으면 알림을 눌러 앱을 켰을 때 그 화면으로 못 간다.',
      );
    });

    /// 🔴 컴파일에서 빠지는 우회를 막는다. `#if DEBUG` 같은 것으로 감싸 두면 위 검사들은
    /// 전부 통과하는데 배포 빌드에는 그 코드가 없다 — 지금 고치는 것과 똑같은 증상이 된다.
    test('조건부 컴파일로 빠져나가지 않는다', () {
      expect(
        engineInitBody(),
        isNot(contains('#if')),
        reason:
            '엔진 초기화 콜백 안에 조건부 컴파일이 있다. 알림 배선이 빌드에 따라 빠지면 '
            '배포 빌드에서만 푸시가 죽는다 — 테스트로는 안 잡히는 실패 모드다.',
      );
    });
  });
}
