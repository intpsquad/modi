import 'package:app/features/room/invite_share.dart';
import 'package:app/features/room/invite_share_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ({
    List<String> copied,
    List<String> shared,
    List<String> launched,
    List<InviteShareData> kakaoInvites,
  })
  spies() => (
    copied: <String>[],
    shared: <String>[],
    launched: <String>[],
    kakaoInvites: <InviteShareData>[],
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<String> copied,
    required List<String> shared,
    required List<String> launched,
    required List<InviteShareData> kakaoInvites,
    bool launchSucceeds = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InviteShareScreen(
          roomId: 1,
          roomName: '여름 알고리즘 스터디',
          coverImage: 'https://storage.test/room-cover.jpg',
          inviteCode: 'ABC123',
          copy: (text) async => copied.add(text),
          shareInvite: (text, {sharePositionOrigin}) async => shared.add(text),
          shareKakao: (invite) async => kakaoInvites.add(invite),
          launchApp: (url) async {
            launched.add(url);
            return launchSucceeds;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('"코드 복사"를 탭하면 초대 코드가 클립보드에 복사된다', (tester) async {
    final s = spies();
    await pumpScreen(
      tester,
      copied: s.copied,
      shared: s.shared,
      launched: s.launched,
      kakaoInvites: s.kakaoInvites,
    );

    await tester.tap(find.text('코드 복사'));
    await tester.pump();

    expect(s.copied, ['ABC123']);
    expect(find.text('코드를 복사했어요'), findsOneWidget);
  });

  testWidgets('"더보기"를 탭하면 OS 공유 시트로 초대 문구가 전달된다', (tester) async {
    final s = spies();
    final origins = <Rect?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: InviteShareScreen(
          roomId: 1,
          roomName: '여름 알고리즘 스터디',
          coverImage: 'https://storage.test/room-cover.jpg',
          inviteCode: 'ABC123',
          copy: (text) async => s.copied.add(text),
          shareInvite: (text, {sharePositionOrigin}) async {
            s.shared.add(text);
            origins.add(sharePositionOrigin);
          },
          shareKakao: (invite) async => s.kakaoInvites.add(invite),
          launchApp: (url) async {
            s.launched.add(url);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('더보기'));
    await tester.tap(find.text('더보기'));
    await tester.pump();

    expect(s.shared, hasLength(1));
    expect(s.shared.single, contains('ABC123'));
    // iOS 네이티브(share_plus)는 앵커 rect가 비어 있으면(CGRectZero) 시트를 띄우지 않고
    // 에러를 돌려준다(iPhone도 해당) — 항상 비어 있지 않은 rect를 넘겨야 한다.
    expect(origins, hasLength(1));
    expect(origins.single, isNotNull);
    expect(origins.single!.isEmpty, isFalse);
  });

  testWidgets('"카카오톡"을 탭하면 SDK 템플릿에 방 초대 데이터를 전달한다', (tester) async {
    final s = spies();
    await pumpScreen(
      tester,
      copied: s.copied,
      shared: s.shared,
      launched: s.launched,
      kakaoInvites: s.kakaoInvites,
    );

    await tester.ensureVisible(find.text('카카오톡'));
    await tester.tap(find.text('카카오톡'));
    await tester.pump();

    expect(s.kakaoInvites, hasLength(1));
    expect(s.kakaoInvites.single.code, 'ABC123');
    expect(s.kakaoInvites.single.roomName, '여름 알고리즘 스터디');
    expect(
      s.kakaoInvites.single.coverImage,
      'https://storage.test/room-cover.jpg',
    );
    expect(s.copied, isEmpty);
    expect(s.launched, isEmpty);
  });

  testWidgets('"인스타"를 탭하면 코드 복사 후 확인 팝업 → "이동" 시 인스타그램을 연다', (tester) async {
    final s = spies();
    await pumpScreen(
      tester,
      copied: s.copied,
      shared: s.shared,
      launched: s.launched,
      kakaoInvites: s.kakaoInvites,
    );

    await tester.ensureVisible(find.text('인스타'));
    await tester.tap(find.text('인스타'));
    await tester.pumpAndSettle();

    // 팝업 뜨기 전 코드는 이미 복사됐고, 인스타는 아직 안 열린다.
    expect(s.copied, ['ABC123']);
    expect(s.launched, isEmpty);

    await tester.tap(find.text('이동'));
    await tester.pumpAndSettle();

    expect(s.launched, ['instagram://']);
    expect(s.shared, isEmpty);
  });

  testWidgets('인스타 확인 팝업에서 "취소"하면 인스타그램을 열지 않는다(코드는 복사됨)', (tester) async {
    final s = spies();
    await pumpScreen(
      tester,
      copied: s.copied,
      shared: s.shared,
      launched: s.launched,
      kakaoInvites: s.kakaoInvites,
    );

    await tester.ensureVisible(find.text('인스타'));
    await tester.tap(find.text('인스타'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(s.copied, ['ABC123']);
    expect(s.launched, isEmpty);
  });

  testWidgets('인스타그램을 열지 못해도 코드는 남기고 안내한다', (tester) async {
    final s = spies();
    await pumpScreen(
      tester,
      copied: s.copied,
      shared: s.shared,
      launched: s.launched,
      kakaoInvites: s.kakaoInvites,
      launchSucceeds: false,
    );

    await tester.ensureVisible(find.text('인스타'));
    await tester.tap(find.text('인스타'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이동'));
    await tester.pumpAndSettle();

    expect(s.copied, ['ABC123']);
    expect(s.launched, ['instagram://']);
    expect(s.shared, isEmpty);
    expect(find.textContaining('인스타그램을 열지 못했어요'), findsOneWidget);
  });

  test('카카오 템플릿은 썸네일·방 제목·참여하기 딥링크를 구성한다', () {
    final template = buildKakaoInviteTemplate(
      InviteShareData(
        roomId: 7,
        code: 'K7QP2X',
        roomName: '여름 알고리즘 스터디',
        coverImage: 'https://storage.test/room-cover.jpg',
      ),
      imageUrl: Uri.parse('https://k.kakaocdn.net/room-cover.jpg'),
      webUrl: Uri.parse(
        'https://api.maramodi.cloud/room/join?inviteCode=K7QP2X',
      ),
    );

    expect(template.content.title, contains('여름 알고리즘 스터디'));
    expect(
      template.content.imageUrl,
      Uri.parse('https://k.kakaocdn.net/room-cover.jpg'),
    );
    expect(template.buttons, hasLength(1));
    expect(template.buttons!.single.title, '참여하기');
    expect(template.buttons!.single.link.androidExecutionParams, {
      'route': 'room/join',
      'inviteCode': 'K7QP2X',
    });
    expect(template.buttons!.single.link.iosExecutionParams, {
      'route': 'room/join',
      'inviteCode': 'K7QP2X',
    });
  });

  test('카카오 실행 URL의 초대 코드를 방 참여 경로로 정규화한다', () {
    final location = inviteJoinLocation(
      Uri.parse('kakaoappkey://kakaolink?route=room/join&inviteCode=k7qp2x'),
    );

    expect(location, '/room/join?inviteCode=K7QP2X');
    expect(
      inviteJoinLocation(Uri.parse('kakaoappkey://kakaolink?route=room/join')),
      isNull,
    );
  });

  group('buildInviteMessage', () {
    test('방 이름이 있으면 문구에 포함된다', () {
      final msg = buildInviteMessage(code: 'ABC123', roomName: '부산 여행');
      expect(msg, contains('ABC123'));
      expect(msg, contains('부산 여행'));
    });

    test('방 이름이 없거나 비면 일반 문구를 쓴다', () {
      expect(buildInviteMessage(code: 'ABC123'), contains('우리 방'));
      expect(
        buildInviteMessage(code: 'ABC123', roomName: '   '),
        contains('우리 방'),
      );
    });
  });
}
