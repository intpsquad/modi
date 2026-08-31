import 'dart:io';

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

  group('inviteShareOrigin', () {
    testWidgets('렌더 박스 크기가 0이면(hasSize=true) 화면 전체 rect로 대신한다', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          // Center는 자식에게 느슨한(0..화면) 제약을 주므로, 그 안의 SizedBox(0,0)은
          // 화면 루트의 tight 제약 때문에 강제로 되돌려지지 않고 실제로 0×0이 된다
          // (SizedBox.shrink()를 화면 루트에 바로 두면 enforce()가 화면 크기로 되돌린다).
          home: Center(
            child: SizedBox(
              width: 0,
              height: 0,
              child: Builder(
                builder: (context) {
                  capturedContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      final box = capturedContext.findRenderObject() as RenderBox;
      expect(box.hasSize, isTrue);
      expect(box.size, Size.zero, reason: '이 테스트가 재현하려는 조건 자체가 0×0이어야 한다');

      final origin = inviteShareOrigin(capturedContext);

      // box.hasSize는 레이아웃이 됐는지만 보장하고 크기가 0이 아님은 보장하지 않는다 —
      // 이 커밋이 막으려는 iOS의 "빈 rect" 실패와 같은 종류라 화면 전체로 대신해야 한다.
      expect(origin, isNotNull);
      expect(origin!.isEmpty, isFalse);
    });
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

  /// 초대 카드가 가리키는 주소는 **앱이 만들고 서버(Caddy)가 연다.** 두 벌이 어긋나면
  /// 카드를 눌러도 아무 페이지가 없는데, 앱 코드만 봐서는 알아챌 방법이 없다 —
  /// 실제로 그렇게 카드가 죽어 있었다(2026-08-31 #74: `/room/join` 이 404 였다).
  ///
  /// 웹 약관 페이지를 앱 본문과 대조하는 `legal_web_sync_test.dart` 와 같은 이유·같은
  /// 방식으로 여기서 잡는다. `flutter test` 는 `app/` 에서 도니 저장소 루트는 `../` 다.
  group('초대 웹 페이지', () {
    File repoFile(String path) => File('../$path');

    /// 🔴 **느슨하게 비교하지 말 것.** 처음엔 `contains('path /room/join')` 하나였는데,
    /// 세 가지 뮤테이션이 전부 초록이었다(2026-08-31 리뷰가 실제로 돌려 증명):
    ///  ① 경로를 `/room/join2` 로 → 부분 문자열이라 그대로 걸린다
    ///  ② `route` 본문을 통째로 삭제 → 핸들러 없는 고아 matcher 는 Caddy 문법 오류가 아니다
    ///  ③ 본문만 따로 `contains('rewrite * /join.html')` 로 봐도 → **maramodi.cloud 블록에
    ///     같은 줄이 있어** api 쪽을 지워도 통과한다
    /// 셋 다 #74(카드를 눌러도 페이지가 없음)를 그대로 재현한다. 그래서 **matcher 줄과 바로
    /// 뒤따르는 route 블록을 한 덩어리로** 본다.
    test('앱이 만드는 초대 주소의 경로를 Caddy 가 열어 준다', () {
      final path = buildInviteWebUrl('K7QP2X').path;
      final caddyfile = repoFile('deploy/Caddyfile');
      expect(caddyfile.existsSync(), isTrue, reason: '${caddyfile.path} 가 없다');
      final escaped = RegExp.escape(path);

      expect(
        caddyfile.readAsStringSync(),
        matches(
          RegExp(
            // 끝 슬래시 변형(`/room/join/`)을 함께 적는 것은 허용하되, `/room/join2` 처럼
            // 이어 붙인 다른 경로는 걸러야 하므로 줄 끝까지 고정한다.
            '@join\\s+path\\s+$escaped(\\s+$escaped/)?\\s*\\n'
            // 그 matcher 를 실제로 쓰는 route 블록이 붙어 있고, 그 안에서 초대 페이지로 간다.
            // `[^}]` 라 블록을 벗어나 다른 블록의 같은 줄을 주워오지 못한다.
            r'\s*route\s+@join\s*\{[^}]*?rewrite\s+\*\s+/join\.html',
          ),
        ),
        reason:
            'buildInviteWebUrl 이 만드는 경로($path)를 deploy/Caddyfile 의 초대 페이지 라우트가 '
            '열어 주지 않는다. 카톡 초대 카드를 눌러도 페이지가 없다.',
      );
    });

    /// 🔴 **주석을 걷어내고 본다.** 처음엔 파일 전체에서 `inviteCode` 를 찾았는데,
    /// 실제 코드에서 `params.get('inviteCode')` 를 지워도 **머리말 주석에 그 단어가 있어**
    /// 초록이었다(2026-08-31 리뷰). 그 상태면 카톡이 보낸 모든 링크가 "코드가 없어요" 가 된다.
    test('초대 페이지가 앱이 보내는 이름으로 코드를 읽는다', () {
      final page = repoFile('deploy/site/join.html');
      expect(
        page.existsSync(),
        isTrue,
        reason: '${page.path} 가 없다. 카톡 초대 카드가 여는 페이지다.',
      );

      final withoutComments = page
          .readAsStringSync()
          .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
          .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

      expect(
        withoutComments,
        contains("params.get('inviteCode')"),
        reason: '앱은 초대 코드를 ?inviteCode= 로 넘긴다 — 페이지가 그 이름을 읽어야 한다.',
      );
    });
  });
}
