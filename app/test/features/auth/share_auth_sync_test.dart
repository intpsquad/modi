import 'package:app/features/auth/share_auth_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.nomara.modi/share_auth');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('iOS에서 공유 확장 세션을 명시적으로 제거한다', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (received) async {
          call = received;
          return null;
        });

    await ShareAuthSync.clearSharedSession();

    expect(call?.method, 'clearSession');
  });
}
