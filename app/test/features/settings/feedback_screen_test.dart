import 'dart:typed_data';

import 'package:app/features/settings/feedback_screen.dart';
import 'package:app/features/settings/settings_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    _FakeFeedbackApi api, {
    ContactEmailLauncher? launcher,
    String? pickedImageName,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackScreen(
          api: api,
          tokenLoader: () async => 'token',
          environmentLoader: () async => const FeedbackEnvironment(
            appVersion: '1.2.0(7)',
            deviceInfo: 'ios 18.2',
          ),
          contactEmailLauncher: launcher,
          photoPicker: pickedImageName == null
              ? null
              : (_) async => XFile.fromData(
                  Uint8List.fromList(const [1, 2, 3, 4]),
                  name: pickedImageName,
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('내용이 비면 보내기가 비활성, 입력하면 활성된다', (tester) async {
    await pump(tester, _FakeFeedbackApi());

    ElevatedButton button() => tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('feedback-submit-button')),
    );
    expect(button().onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('feedback-content-field')),
      '삭제가 안 돼요',
    );
    await tester.pump();

    expect(button().onPressed, isNotNull);
  });

  testWidgets('공백만 입력하면 여전히 보낼 수 없다', (tester) async {
    await pump(tester, _FakeFeedbackApi());

    await tester.enterText(
      find.byKey(const ValueKey('feedback-content-field')),
      '   ',
    );
    await tester.pump();

    final button = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('feedback-submit-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('계정 이메일이 있으면 회신 주소로 프리필된다', (tester) async {
    await pump(tester, _FakeFeedbackApi(email: 'me@example.com'));

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('feedback-email-field')),
    );
    expect(field.controller?.text, 'me@example.com');
  });

  testWidgets('계정 이메일이 없으면 빈 칸으로 두고 답변 불가를 안내한다', (tester) async {
    // 소셜 로그인은 제공사가 이메일을 안 줄 수 있다.
    await pump(tester, _FakeFeedbackApi(email: null));

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('feedback-email-field')),
    );
    expect(field.controller?.text, isEmpty);
    expect(find.textContaining('가입 계정에 이메일이 없어요'), findsOneWidget);
  });

  testWidgets('무엇이 함께 전송되는지 값까지 화면에 밝힌다', (tester) async {
    // 고지 없이 수집하지 않는다.
    await pump(tester, _FakeFeedbackApi());

    expect(find.textContaining('1.2.0(7)'), findsOneWidget);
    expect(find.textContaining('ios 18.2'), findsOneWidget);
  });

  testWidgets('유형·내용·앱버전·기기정보가 그대로 전송된다', (tester) async {
    final api = _FakeFeedbackApi(email: 'me@example.com');
    await pump(tester, api);

    await tester.tap(find.text('제안'));
    await tester.enterText(
      find.byKey(const ValueKey('feedback-content-field')),
      '이런 기능 어때요',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feedback-submit-button')));
    await tester.pumpAndSettle();

    expect(api.lastType, 'SUGGESTION');
    expect(api.lastContent, '이런 기능 어때요');
    expect(api.lastReplyEmail, 'me@example.com');
    expect(api.lastAppVersion, '1.2.0(7)');
    expect(api.lastDeviceInfo, 'ios 18.2');
    expect(api.lastImageBytes, isNull);
  });

  testWidgets('전송에 성공하면 알리고 화면을 닫는다', (tester) async {
    final api = _FakeFeedbackApi();
    await pump(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('feedback-content-field')),
      '문의합니다',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feedback-submit-button')));
    await tester.pump();

    expect(find.text('문의를 보냈어요'), findsOneWidget);
  });

  testWidgets('첨부한 스크린샷 바이트가 함께 전송된다', (tester) async {
    final api = _FakeFeedbackApi();
    await pump(tester, api, pickedImageName: 'shot.png');

    await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('앨범에서 선택'));
    await tester.pumpAndSettle();

    expect(find.text('스크린샷 1장'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('feedback-content-field')),
      '이렇게 나와요',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feedback-submit-button')));
    await tester.pumpAndSettle();

    expect(api.lastImageBytes, const [1, 2, 3, 4]);
  });

  testWidgets('첨부를 삭제하면 이미지 없이 전송된다', (tester) async {
    final api = _FakeFeedbackApi();
    await pump(tester, api, pickedImageName: 'shot.png');

    await tester.tap(find.byKey(const ValueKey('feedback-add-screenshot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('앨범에서 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-remove-screenshot')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('feedback-content-field')),
      '내용',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feedback-submit-button')));
    await tester.pumpAndSettle();

    expect(api.lastImageBytes, isNull);
  });

  testWidgets('전송에 실패하면 mailto 폴백을 제시한다', (tester) async {
    // 🔴 #70의 핵심 — 폼이 막혀도 문의할 길이 남아야 한다.
    Uri? launched;
    await pump(
      tester,
      _FakeFeedbackApi(failing: true),
      launcher: (uri) async {
        launched = uri;
        return true;
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey('feedback-content-field')),
      '보내지지 않는 문의',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feedback-submit-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('보내지 못했어요'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('feedback-mail-fallback')));
    await tester.pumpAndSettle();

    expect(launched?.scheme, 'mailto');
    expect(launched?.path, supportEmailAddress);
  });

  testWidgets('메일 앱도 못 열면 주소를 직접 안내한다', (tester) async {
    await pump(
      tester,
      _FakeFeedbackApi(failing: true),
      launcher: (_) async => false,
    );

    await tester.enterText(
      find.byKey(const ValueKey('feedback-content-field')),
      '내용',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feedback-submit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-mail-fallback')));
    await tester.pump();

    expect(find.textContaining(supportEmailAddress), findsOneWidget);
  });

  testWidgets('메일 앱 실행이 예외를 던져도 주소를 직접 안내한다', (tester) async {
    // launchUrl 은 처리할 앱이 없을 때 false 를 돌려주기도 하지만 예외를 던지기도 한다
    // (iOS 시뮬레이터에 메일 앱이 없을 때 실측, #76). 위 테스트는 false 만 덮고 있어서,
    // 예외 경로에서는 안내조차 못 띄운 채 아무 일도 일어나지 않았다.
    await pump(
      tester,
      _FakeFeedbackApi(failing: true),
      launcher: (_) async => throw Exception('no mail app'),
    );

    await tester.enterText(
      find.byKey(const ValueKey('feedback-content-field')),
      '내용',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feedback-submit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('feedback-mail-fallback')));
    await tester.pump();

    expect(find.textContaining(supportEmailAddress), findsOneWidget);
  });
}

class _FakeFeedbackApi extends SettingsApi {
  _FakeFeedbackApi({this.email = 'me@example.com', this.failing = false});

  final String? email;
  final bool failing;

  String? lastType;
  String? lastContent;
  String? lastReplyEmail;
  String? lastAppVersion;
  String? lastDeviceInfo;
  List<int>? lastImageBytes;

  @override
  Future<UserProfile> fetchProfile(String idToken) async =>
      UserProfile(userId: 'uid-1', nickname: '예원', email: email);

  @override
  Future<void> submitFeedback(
    String idToken, {
    required String type,
    required String content,
    String? replyEmail,
    String? appVersion,
    String? deviceInfo,
    List<int>? imageBytes,
  }) async {
    if (failing) throw StateError('boom');
    lastType = type;
    lastContent = content;
    lastReplyEmail = replyEmail;
    lastAppVersion = appVersion;
    lastDeviceInfo = deviceInfo;
    lastImageBytes = imageBytes;
  }
}
