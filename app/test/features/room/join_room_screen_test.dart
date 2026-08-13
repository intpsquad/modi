import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/room/join_room_screen.dart';
import 'package:app/features/room/room_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRoomApi extends RoomApi {
  _FakeRoomApi({this.preview, this.previewError});

  bool previewCalled = false;
  bool joinCalled = false;
  final InvitePreview? preview;
  final Object? previewError;

  @override
  Future<InvitePreview> previewInvite(String idToken, String code) async {
    previewCalled = true;
    if (previewError != null) throw previewError!;
    return preview ??
        InvitePreview(roomId: 1, name: '방', goal: '목표', status: 'ACTIVE');
  }

  @override
  Future<void> joinRoom(String idToken, String code) async {
    joinCalled = true;
  }
}

class _FakeAuthService extends AuthService {
  @override
  Future<String> getIdToken() async => 'fake-token';
}

Finder _joinButton() => find.widgetWithText(ElevatedButton, '참여하기');

// 6칸 코드 입력은 투명 TextField 하나로 받는다.
Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField), code);
  await tester.pump();
}

void main() {
  testWidgets('카카오 초대 링크로 전달된 코드는 참여 화면에 미리 채운다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: JoinRoomScreen(
          initialInviteCode: 'modi42',
          api: _FakeRoomApi(),
          authService: _FakeAuthService(),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'MODI42');
    expect(tester.widget<ElevatedButton>(_joinButton()).onPressed, isNotNull);
  });

  testWidgets('붙여넣기 버튼은 클립보드 코드를 정규화해 채운다', (tester) async {
    // 클립보드 목업 — 공백·하이픈 섞인 코드.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': ' xk7q-2m '};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: JoinRoomScreen(
          api: _FakeRoomApi(),
          authService: _FakeAuthService(),
        ),
      ),
    );

    await tester.tap(find.text('붙여넣기'));
    await tester.pumpAndSettle();

    // 영숫자만·대문자·6자로 정규화되어 채워지고 참여하기가 활성된다.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'XK7Q2M');
    expect(tester.widget<ElevatedButton>(_joinButton()).onPressed, isNotNull);
  });

  testWidgets('소문자를 입력하면 각 칸이 대문자로 표시된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: JoinRoomScreen(
          api: _FakeRoomApi(),
          authService: _FakeAuthService(),
        ),
      ),
    );

    await _enterCode(tester, 'abcdef');

    // 컨트롤러는 대문자로 정규화되고, 6칸에 A~F가 각각 하나씩 렌더된다.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'ABCDEF');
    for (final ch in ['A', 'B', 'C', 'D', 'E', 'F']) {
      expect(find.text(ch), findsOneWidget);
    }
  });

  testWidgets('영문·숫자가 아닌 문자는 입력되지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: JoinRoomScreen(
          api: _FakeRoomApi(),
          authService: _FakeAuthService(),
        ),
      ),
    );

    await _enterCode(tester, 'a1!@b2');

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'A1B2');
  });

  testWidgets('6자 미만이면 참여하기 버튼이 비활성이고 API가 호출되지 않는다', (tester) async {
    final fakeApi = _FakeRoomApi();
    await tester.pumpWidget(
      MaterialApp(
        home: JoinRoomScreen(api: fakeApi, authService: _FakeAuthService()),
      ),
    );

    await _enterCode(tester, 'ABC');

    final button = tester.widget<ElevatedButton>(_joinButton());
    expect(button.onPressed, isNull);
    expect(fakeApi.previewCalled, isFalse);
  });

  testWidgets('6자를 입력하면 버튼이 활성화되고, 탭하면 확인 모달에 방 이름이 뜬다', (tester) async {
    final fakeApi = _FakeRoomApi(
      preview: InvitePreview(
        roomId: 7,
        name: '여름 알고리즘 스터디',
        goal: '목표',
        status: 'ACTIVE',
        memberCount: 5,
        startDate: DateTime(2026, 7, 28),
        endDate: DateTime(2026, 9, 5),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: JoinRoomScreen(api: fakeApi, authService: _FakeAuthService()),
      ),
    );

    await _enterCode(tester, 'MODI42');
    expect(tester.widget<ElevatedButton>(_joinButton()).onPressed, isNotNull);

    await tester.tap(_joinButton());
    // 로딩 스피너가 계속 돌아 pumpAndSettle은 타임아웃되므로 고정 pump로 모달을 띄운다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(fakeApi.previewCalled, isTrue);
    expect(find.text('여름 알고리즘 스터디에 참여하시겠습니까?'), findsOneWidget);
    // 멤버 수·기간이 있으면 메타가 노출된다.
    expect(find.text('멤버 5명 · 2026.07.28 – 2026.09.05'), findsOneWidget);
  });

  testWidgets('멤버 수·기간이 없으면 모달 메타가 목표(goal)로 폴백된다', (tester) async {
    final fakeApi = _FakeRoomApi(
      preview: InvitePreview(
        roomId: 7,
        name: '방',
        goal: '이번 달 목표 달성',
        status: 'ACTIVE',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: JoinRoomScreen(api: fakeApi, authService: _FakeAuthService()),
      ),
    );

    await _enterCode(tester, 'MODI42');
    await tester.tap(_joinButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('이번 달 목표 달성'), findsOneWidget);
  });

  testWidgets('무효/만료 코드면 "코드를 찾을 수 없어요" 팝업이 뜨고 참여 API는 호출되지 않는다', (
    tester,
  ) async {
    final fakeApi = _FakeRoomApi(previewError: InviteNotFoundException());
    await tester.pumpWidget(
      MaterialApp(
        home: JoinRoomScreen(api: fakeApi, authService: _FakeAuthService()),
      ),
    );

    await _enterCode(tester, 'MODI42');
    await tester.tap(_joinButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('코드를 찾을 수 없어요'), findsOneWidget);
    expect(fakeApi.joinCalled, isFalse);
    // 참여 확인 모달은 뜨지 않는다.
    expect(find.textContaining('참여하시겠습니까?'), findsNothing);
  });

  testWidgets('종료된 방이면 "종료된 방이에요" 팝업이 뜬다', (tester) async {
    final fakeApi = _FakeRoomApi(previewError: RoomEndedException());
    await tester.pumpWidget(
      MaterialApp(
        home: JoinRoomScreen(api: fakeApi, authService: _FakeAuthService()),
      ),
    );

    await _enterCode(tester, 'MODI42');
    await tester.tap(_joinButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('종료된 방이에요'), findsOneWidget);
  });
}
