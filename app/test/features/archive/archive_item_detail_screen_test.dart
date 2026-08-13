import 'package:app/design/option_menu.dart';
import 'package:app/design/theme.dart';
import 'package:app/design/tokens.dart';
import 'package:app/features/archive/archive_api.dart';
import 'package:app/features/archive/archive_item_detail_screen.dart';
import 'package:app/features/archive/archive_widgets.dart';
import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/room/room_api.dart';
import 'package:app/features/room/room_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRoomApi extends RoomApi {
  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async {
    return [
      {
        'id': 1,
        'name': '테스트방',
        'goal': '목표',
        'status': 'ACTIVE',
        'startDate': '2026-01-01',
        'endDate': '2026-12-31',
      },
    ];
  }
}

class _NoActiveRoomApi extends RoomApi {
  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async => [];
}

class _FakeAuthService extends AuthService {
  @override
  Future<String> getIdToken() async => 'fake-token';

  // 테스트엔 Firebase가 없어 실제 getter(FirebaseAuth.instance)가 던진다 — null로 눌러
  // 댓글 ⋯(내 댓글 판정)이 안 뜨게 한다(현재 댓글 테스트는 ⋯를 검증하지 않는다).
  @override
  String? get currentUserId => null;
}

ArchiveItemDetail _detail({
  int id = 1,
  int folderId = 1,
  String title = '항목',
  String? url,
  String? source,
  String? summary,
  String? bodyText = '본문',
  bool pinned = false,
  List<String> tags = const [],
  int likeCount = 0,
  bool likedByMe = false,
  String crawlStatus = 'DONE',
  String? memo,
  String? folderName,
  ArchiveItemCreator? createdBy,
  String? thumbnail,
  int commentCount = 0,
}) {
  return ArchiveItemDetail(
    id: id,
    folderId: folderId,
    folderName: folderName,
    createdBy: createdBy,
    title: title,
    url: url,
    source: source,
    thumbnail: thumbnail,
    summary: summary,
    bodyText: bodyText,
    pinned: pinned,
    tags: tags,
    likeCount: likeCount,
    likedByMe: likedByMe,
    createdAt: DateTime(2026, 7, 20),
    crawlStatus: crawlStatus,
    memo: memo,
    commentCount: commentCount,
  );
}

class _FakeArchiveApi extends ArchiveApi {
  _FakeArchiveApi({
    ArchiveItemDetail? detail,
    this.folders = const [],
    this.throwOnFetch = false,
    this.throwOnPin = false,
    this.throwOnTags = false,
    this.throwOnSummarize = false,
    this.throwOnMemo = false,
  }) : detail = detail ?? _detail();

  ArchiveItemDetail detail;
  List<ArchiveFolder> folders;
  bool throwOnFetch;
  bool throwOnPin;
  bool throwOnTags;
  bool throwOnSummarize;
  bool throwOnMemo;
  int summarizeCallCount = 0;
  int fetchCallCount = 0;
  final List<bool> pinCalls = [];
  final List<bool> likeCalls = [];
  final List<int> moveCalls = [];
  final List<List<String>> tagsCalls = [];
  final List<String?> memoCalls = [];
  int deleteCallCount = 0;

  /// 댓글 픽스처(오래된순) + 작성 기록.
  List<ArchiveComment> comments = [];
  final List<String> commentCalls = [];
  bool throwOnComment = false;

  @override
  Future<List<ArchiveComment>> fetchComments(
    String idToken,
    int roomId,
    int itemId,
  ) async => comments;

  @override
  Future<ArchiveComment> createComment(
    String idToken,
    int roomId,
    int itemId,
    String body,
  ) async {
    commentCalls.add(body);
    if (throwOnComment) throw StateError('network');
    final created = ArchiveComment(
      id: comments.length + 1,
      author: ArchiveItemCreator(userId: 'me', nickname: '나'),
      body: body,
      createdAt: DateTime(2026, 8, 9),
    );
    comments = [...comments, created];
    return created;
  }

  @override
  Future<ArchiveItemCreator> fetchMyBrief(String idToken) async =>
      ArchiveItemCreator(userId: 'me', nickname: '나');

  @override
  Future<ArchiveItemDetail> updateItemMemo(
    String idToken,
    int roomId,
    int itemId,
    String? memo,
  ) async {
    memoCalls.add(memo);
    if (throwOnMemo) throw StateError('network');
    detail = ArchiveItemDetail(
      id: detail.id,
      folderId: detail.folderId,
      title: detail.title,
      url: detail.url,
      source: detail.source,
      thumbnail: detail.thumbnail,
      summary: detail.summary,
      bodyText: detail.bodyText,
      pinned: detail.pinned,
      tags: detail.tags,
      likeCount: detail.likeCount,
      likedByMe: detail.likedByMe,
      createdAt: detail.createdAt,
      crawlStatus: detail.crawlStatus,
      memo: memo,
    );
    return detail;
  }

  @override
  Future<ArchiveItemDetail> summarizeItem(
    String idToken,
    int roomId,
    int itemId,
  ) async {
    summarizeCallCount++;
    if (throwOnSummarize) throw StateError('summary');
    detail = ArchiveItemDetail(
      id: detail.id,
      folderId: detail.folderId,
      title: detail.title,
      url: detail.url,
      source: detail.source,
      thumbnail: null,
      summary: '방금 만든 요약',
      bodyText: detail.bodyText,
      pinned: detail.pinned,
      tags: detail.tags,
      likeCount: detail.likeCount,
      likedByMe: detail.likedByMe,
      createdAt: detail.createdAt,
      crawlStatus: detail.crawlStatus,
      memo: detail.memo,
    );
    return detail;
  }

  @override
  Future<ArchiveItemDetail> fetchItemDetail(
    String idToken,
    int roomId,
    int itemId,
  ) async {
    fetchCallCount++;
    if (throwOnFetch) throw StateError('network');
    return detail;
  }

  @override
  Future<List<ArchiveFolder>> fetchFolders(String idToken, int roomId) async {
    return folders;
  }

  @override
  Future<ArchiveItemDetail> setItemPinned(
    String idToken,
    int roomId,
    int itemId,
    bool pinned,
  ) async {
    pinCalls.add(pinned);
    if (throwOnPin) throw StateError('network');
    detail = ArchiveItemDetail(
      id: detail.id,
      folderId: detail.folderId,
      title: detail.title,
      url: detail.url,
      source: detail.source,
      thumbnail: detail.thumbnail,
      summary: detail.summary,
      bodyText: detail.bodyText,
      pinned: pinned,
      tags: detail.tags,
      likeCount: detail.likeCount,
      likedByMe: detail.likedByMe,
      createdAt: detail.createdAt,
      crawlStatus: detail.crawlStatus,
    );
    return detail;
  }

  @override
  Future<ArchiveItemDetail> setItemLiked(
    String idToken,
    int roomId,
    int itemId,
    bool liked,
  ) async {
    likeCalls.add(liked);
    detail = detail.copyWith(
      likedByMe: liked,
      likeCount: detail.likeCount + (liked ? 1 : -1),
    );
    return detail;
  }

  @override
  Future<ArchiveItemDetail> moveItemToFolder(
    String idToken,
    int roomId,
    int itemId,
    int folderId,
  ) async {
    moveCalls.add(folderId);
    detail = ArchiveItemDetail(
      id: detail.id,
      folderId: folderId,
      title: detail.title,
      url: detail.url,
      source: detail.source,
      thumbnail: detail.thumbnail,
      summary: detail.summary,
      bodyText: detail.bodyText,
      pinned: detail.pinned,
      tags: detail.tags,
      likeCount: detail.likeCount,
      likedByMe: detail.likedByMe,
      createdAt: detail.createdAt,
      crawlStatus: detail.crawlStatus,
    );
    return detail;
  }

  @override
  Future<ArchiveItemDetail> updateItemTags(
    String idToken,
    int roomId,
    int itemId,
    List<String> tags,
  ) async {
    tagsCalls.add(tags);
    if (throwOnTags) throw StateError('network');
    detail = ArchiveItemDetail(
      id: detail.id,
      folderId: detail.folderId,
      title: detail.title,
      url: detail.url,
      source: detail.source,
      thumbnail: detail.thumbnail,
      summary: detail.summary,
      bodyText: detail.bodyText,
      pinned: detail.pinned,
      tags: tags,
      likeCount: detail.likeCount,
      likedByMe: detail.likedByMe,
      createdAt: detail.createdAt,
      crawlStatus: detail.crawlStatus,
    );
    return detail;
  }

  @override
  Future<void> deleteItem(String idToken, int roomId, int itemId) async {
    deleteCallCount++;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---- 2026-08-05 재디자인 규격 (specs/0010 S-25-B, design.md §6) ----

  group('레이아웃 규격', () {
    Future<void> pump(WidgetTester tester, ArchiveItemDetail detail) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ArchiveItemDetailScreen(
            itemId: 1,
            api: _FakeArchiveApi(detail: detail),
            authService: _FakeAuthService(),
            roomSession: RoomSession(roomApi: _FakeRoomApi()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('사진은 좌우 여백을 뺀 폭 × 180이고 radius 16이다', (tester) async {
      // 링크 자료라야 사진 컴포넌트가 있다(텍스트 자료는 사진 없음, 2026-08-09).
      await pump(tester, _detail(url: 'https://ex.com'));

      final clip = find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(ClipRRect),
          )
          .first;
      final rect = tester.getRect(clip);
      final screenWidth = tester.getSize(find.byType(MaterialApp)).width;

      expect(rect.height, 180);
      expect(rect.width, screenWidth - 16 * 2, reason: '좌우 패딩 16을 뺀 최대 폭');
      expect(
        (tester.widget<ClipRRect>(clip).borderRadius as BorderRadius).topLeft,
        const Radius.circular(16),
      );
    });

    /// 사진 사각형 — 이 그룹의 여러 테스트가 기준으로 삼는다.
    Rect photoRect(WidgetTester tester) => tester.getRect(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(ClipRRect),
          )
          .first,
    );

    testWidgets('핀 토글은 앱바 ⋯ 버튼 왼쪽에 온다', (tester) async {
      // 2026-08-09 QA: 사진 위에선 핀이 잘 안 보여 앱바 ⋯ 왼쪽으로 옮겼다.
      await pump(tester, _detail(url: 'https://ex.com', pinned: false));

      final pin = tester.getRect(
        find.byKey(const ValueKey('archive-detail-pin-off')),
      );
      final more = tester.getRect(find.byIcon(Icons.more_horiz));
      final appBar = tester.getRect(find.byType(AppBar));

      expect(pin.width, 24, reason: '아이콘 24');
      expect(pin.height, 24);
      // 핀이 ⋯ 왼쪽에 있고, 사진이 아니라 앱바 안에 있다.
      expect(pin.right, lessThan(more.left), reason: '핀은 ⋯ 왼쪽');
      expect(pin.center.dy, lessThan(appBar.bottom), reason: '앱바 안');
      expect(
        pin.center.dy,
        lessThan(photoRect(tester).top),
        reason: '사진 위(앱바)',
      );
    });

    testWidgets('제목은 말줄임 없이 항상 전체 표시된다', (tester) async {
      const longTitle = '아주 긴 자료 제목이라 한 줄을 넘겨도 말줄임 없이 전부 보여주는 링크 상세의 제목 예시입니다';
      await pump(tester, _detail(title: longTitle));

      final titleWidget = tester.widget<Text>(find.text(longTitle));
      expect(titleWidget.maxLines, isNull, reason: '줄 수 제한 없음');
      expect(titleWidget.overflow, isNot(TextOverflow.ellipsis));
    });

    testWidgets('핀 토글이 고정 상태면 채워진 primary_pin으로 바뀐다', (tester) async {
      await pump(tester, _detail(pinned: true));

      expect(
        find.byKey(const ValueKey('archive-detail-pin-on')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('archive-detail-pin-off')),
        findsNothing,
      );
    });

    testWidgets('좋아요·등록자 아바타는 사진이 아니라 하단 반응 바에 온다', (tester) async {
      await pump(
        tester,
        _detail(
          url: 'https://ex.com',
          likeCount: 7,
          createdBy: ArchiveItemCreator(userId: 'u1', nickname: '준호'),
        ),
      );

      // 사진 위에는 더 이상 하트/아바타가 없다 — 핀만 있다.
      final photo = photoRect(tester);
      final bottomBarKey = find.byKey(
        const ValueKey('archive-detail-bottom-bar'),
      );
      final heart = tester.getRect(find.byIcon(Icons.favorite_border));
      expect(
        heart.top,
        greaterThan(photo.bottom),
        reason: '좋아요는 사진 아래(하단 바)에 있다',
      );
      // 하트·카운트가 실제로 하단 바 위젯의 자손인지 직접 확인한다(좌표 비교는 우연히도
      // 맞아떨어질 수 있어서 부족하다).
      expect(
        find.descendant(
          of: bottomBarKey,
          matching: find.byIcon(Icons.favorite_border),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bottomBarKey, matching: find.text('7')),
        findsOneWidget,
      );

      // 닉네임 첫 글자만 쓴다.
      expect(find.text('준호'), findsNothing);
      expect(
        find.descendant(of: bottomBarKey, matching: find.text('준')),
        findsOneWidget,
      );
      final circle = tester.getRect(
        find
            .ancestor(of: find.text('준'), matching: find.byType(Container))
            .first,
      );
      expect(circle.size, const Size(24, 24), reason: '지름 24');
      expect(
        circle.left,
        greaterThan(heart.right),
        reason: '아바타는 좋아요보다 오른쪽(바 우측 끝)',
      );
    });

    testWidgets('등록자가 없으면 아바타 자리를 아예 비운다', (tester) async {
      // 탈퇴했거나 created_by 컬럼(V19) 이전에 등록된 자료. 빈 원을 그리면
      // "누군가 있는데 이름만 없다"로 읽힌다.
      await pump(tester, _detail(createdBy: null));

      // 🔴 시맨틱 라벨로 잰다. 이 화면은 CircleAvatar 를 안 쓰고 Container + BoxDecoration 이라
      // `find.byType(CircleAvatar)` 같은 단언은 구현이 어떻든 항상 통과하는 공허한 단언이다
      // (2026-08-08 reviewer 지적). 라벨은 _AuthorAvatar 가 그려질 때만 존재한다.
      expect(find.bySemanticsLabel(RegExp('^등록자')), findsNothing);
    });

    testWidgets('썸네일이 없으면 회색 면 + 이미지 아이콘이다 — 빨강 그라데이션이 아니다', (tester) async {
      await pump(tester, _detail(url: 'https://ex.com', thumbnail: null));

      final box = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(ClipRRect),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(box.color, AppColors.surfaceSoft);
      final icon = tester.widget<Icon>(find.byIcon(Icons.image_outlined));
      expect(icon.size, 40);
      expect(icon.color, AppColors.mutedSoft);
    });

    testWidgets('하단 바 좋아요는 흰 배경 위라 muted다', (tester) async {
      await pump(tester, _detail(thumbnail: null, likeCount: 3));

      expect(
        tester.widget<Icon>(find.byIcon(Icons.favorite_border)).color,
        AppColors.muted,
      );
      final count = tester.widget<Text>(find.text('3'));
      expect(count.style!.color, AppColors.muted);
      // `badge`(11). caption(13)으로 되돌리면 여기서 걸린다.
      expect(count.style!.fontSize, 11);
    });

    testWidgets('프로필 사진을 못 불러와도 이니셜이 남는다', (tester) async {
      // NetworkImage 는 위젯 테스트에서 항상 실패한다 — 실제로 상시 재현되는 경로다.
      // 이니셜을 배경 DecorationImage 아래가 아니라 **항상 깔아** 두지 않으면 빈 회색 원이 남고,
      // 그건 "등록자가 없어서 자리를 비운 것"과 화면상 구분되지 않는다.
      await pump(
        tester,
        _detail(
          createdBy: ArchiveItemCreator(
            userId: 'u1',
            nickname: '준호',
            profileImage: 'https://example.com/p.png',
          ),
        ),
      );

      expect(find.text('준'), findsOneWidget);
    });

    testWidgets('앱바에는 제목이 없다 — 뒤로가기·⋯ 버튼만 있다', (tester) async {
      // 2026-08-08 재확정: 같은 날 두 번 뒤집혔다 — 처음엔 폴더 이름, 그다음 자료 제목이었다가
      // 최종적으로 앱바 제목 자체를 없앴다(큰 제목은 본문에만 남는다).
      await pump(tester, _detail(folderName: '여행 링크 모음', title: '자료 제목'));

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('자료 제목')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('여행 링크 모음'),
        ),
        findsNothing,
      );
      // 뒤로가기·⋯ 버튼은 그대로 있다.
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    });

    testWidgets('제목은 전체 표시, 메모는 2줄에서 말줄임한다', (tester) async {
      // 2026-08-09 재확정: 제목은 말줄임 없이 전부 보여준다(기존 1줄 말줄임 폐기).
      await pump(tester, _detail(title: '제목입니다', memo: '메모입니다'));

      final title = tester.widget<Text>(find.text('제목입니다'));
      final memo = tester.widget<Text>(find.text('메모입니다'));

      expect(title.maxLines, isNull);
      expect(title.overflow, isNot(TextOverflow.ellipsis));
      expect(
        memo.maxLines,
        2,
        reason: 'Figma 높이 40 = body-small 14 × 1.43 × 2',
      );
      expect(memo.overflow, TextOverflow.ellipsis);
    });

    testWidgets('본문(요약)은 foreground-soft로 그린다', (tester) async {
      await pump(tester, _detail(summary: '요약된 본문'));

      final body = tester.widget<Text>(find.text('요약된 본문'));
      expect(body.style!.color, AppColors.foregroundSoft);
      expect(body.style!.fontSize, 16, reason: 'body 16/150');
    });

    testWidgets('본문(요약)은 문장마다 따로 그리고 사이를 6으로 벌린다', (tester) async {
      // 4~6문장이 한 덩어리로 붙어 나와 읽기 어렵다는 QA(2026-08-08). 서버 저장값은 그대로고
      // 화면에서만 나눈다 — 프롬프트로 받는 방법은 모델이 7~8/15건만 지켰다(EXPERIMENTS #33).
      //
      // 🔴 `\n` 하나로는 부족했다. 문장이 여러 줄로 감기면 행간(24)과 구분되지 않아서,
      // 문장마다 별도 Text + 6px 로 문장 경계만 30이 되게 한다(사용자 확정 6).
      await pump(
        tester,
        _detail(summary: '첫 문장이다. 둘째 문장이다. 셋째 문장이다. 넷째 문장이다.'),
      );

      for (final sentence in ['첫 문장이다.', '둘째 문장이다.', '셋째 문장이다.', '넷째 문장이다.']) {
        expect(
          find.text(sentence),
          findsOneWidget,
          reason: '$sentence 이 제 줄을 가져야 한다',
        );
      }
      expect(
        tester.getTopLeft(find.text('둘째 문장이다.')).dy -
            tester.getBottomLeft(find.text('첫 문장이다.')).dy,
        6,
        reason: '문장 사이 간격은 _kSentenceGap = 6',
      );
    });

    testWidgets('🔴 약어가 든 요약은 문장이 찢어지지 않는다', (tester) async {
      // `드.디.어.` 는 운영 데이터에 실제로 있는 정처기 콘텐츠 이름이고 그 마침표 뒤에 공백이 온다
      // (ai/evals/data/summaries/010_jeongcheogi_lion.txt). 여기서 끊으면 한 문장이 두 줄이 된다.
      await pump(
        tester,
        _detail(summary: '이에 따라 드.디.어. 정보처리기사 요약노트가 나온다. 배포 시점이 안내된다.'),
      );

      expect(find.text('이에 따라 드.디.어. 정보처리기사 요약노트가 나온다.'), findsOneWidget);
      expect(find.text('배포 시점이 안내된다.'), findsOneWidget);
      expect(find.text('이에 따라 드.디.어.'), findsNothing, reason: '약어에서 끊기면 안 된다');
    });

    testWidgets('컴포넌트 사이 간격은 12다', (tester) async {
      await pump(
        tester,
        _detail(
          title: '제목입니다',
          memo: '메모입니다',
          url: 'https://docs.example.com/a',
        ),
      );

      final photo = tester.getRect(
        find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      // 앱바에도 같은 문자열이 뜨므로(위 그룹의 앱바 테스트 참고) 본문(스크롤 영역)으로 한정한다.
      final title = tester.getRect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text('제목입니다'),
        ),
      );
      final memo = tester.getRect(find.text('메모입니다'));
      // 구분선이 이제 둘이다(메모 아래 · 하단 반응 바 위) — 첫 번째만 이 테스트가 재는 대상이다.
      final divider = tester.getRect(find.byType(Divider).first);
      final link = tester.getRect(find.text('docs.example'));

      expect(title.top - photo.bottom, 12, reason: '사진 → 제목');
      expect(memo.top - title.bottom, 12, reason: '제목 → 메모');
      expect(divider.top - memo.bottom, 12, reason: '메모 → 구분선');
      expect(link.top - divider.bottom, 12, reason: '구분선 → 링크줄');
    });

    testWidgets('메모가 없으면 그 자리의 간격도 생기지 않는다', (tester) async {
      await pump(tester, _detail(title: '제목입니다', memo: null));

      final title = tester.getRect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text('제목입니다'),
        ),
      );
      final divider = tester.getRect(find.byType(Divider).first);

      expect(divider.top - title.bottom, 12, reason: '제목 → 구분선이 곧바로 12');
    });

    testWidgets('링크 줄에 등록 날짜를 싣지 않는다', (tester) async {
      // 2026-08-08 확정: 예전엔 `docs.example  |  2026.07.20`이었다. 날짜는 이 화면에서
      // 아무 동작도 없는 값이라 시안에서 빠졌다.
      await pump(tester, _detail(url: 'https://docs.example.com/a'));

      expect(find.text('docs.example'), findsOneWidget);
      expect(find.text('  |  '), findsNothing, reason: '구분자도 함께 사라진다');
      // 화면 어디에도 날짜 형식 문자열이 없다 — `_detail`의 createdAt은 2026-07-20이다.
      expect(find.textContaining('2026.'), findsNothing);
      expect(find.textContaining('2026-07'), findsNothing);
    });

    testWidgets('링크 아이콘과 도메인 사이 간격은 6이다', (tester) async {
      await pump(tester, _detail(url: 'https://docs.example.com/a'));

      // 링크 줄 안으로 한정한다 — `find.byType(Image).first`로 재면 픽스처에 썸네일이 생기는 순간
      // 조용히 다른 위젯을 잰다(2026-08-08 reviewer 지적).
      final label = find.text('docs.example');
      final row = find.ancestor(of: label, matching: find.byType(Row)).first;
      final icon = tester.getRect(
        find.descendant(of: row, matching: find.byType(Image)),
      );
      expect(tester.getRect(label).left - icon.right, 6);
    });

    testWidgets('링크가 없는 자료는 링크 줄과 그 간격이 통째로 사라진다', (tester) async {
      // 날짜가 빠지면서 URL 없는 텍스트 자료는 이 줄에 보여줄 것이 없어졌다.
      // 줄만 지우고 간격 12를 남기면 구분선 아래가 허전하게 벌어진다.
      await pump(tester, _detail(url: null, tags: ['태그']));

      // 구분선이 둘이다(메모 아래 · 하단 바 위) — 첫 번째가 태그 바로 위 것이다.
      final divider = tester.getRect(find.byType(Divider).first);
      // 칩 안쪽 텍스트가 아니라 칩 자체를 잰다 — 칩은 높이 20이고 badge(11×1.2=13.2) 글자가
      // 세로 가운데라, 텍스트로 재면 3.4가 더해져 15.4가 나온다.
      final tag = tester.getRect(find.byType(ArchiveTagChip));
      expect(tag.top - divider.bottom, 12, reason: '구분선 → 태그가 곧바로 12');
    });

    testWidgets('링크는 짧게 줄여 한 줄로 보여주고 원문은 노출하지 않는다', (tester) async {
      await pump(
        tester,
        _detail(url: 'https://docs.example.com/guide/main/index.do#none'),
      );

      expect(find.text('docs.example'), findsOneWidget);
      expect(
        find.text('https://docs.example.com/guide/main/index.do#none'),
        findsNothing,
      );
      final text = tester.widget<Text>(find.text('docs.example'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('링크 라벨이 눌리는 요소로 보이게 primary 밑줄 + 외부링크 아이콘이 붙는다', (
      tester,
    ) async {
      // 2026-08-08 지적: 기존 muted 무채색 텍스트는 탭 가능해 보이지 않았다.
      await pump(tester, _detail(url: 'https://docs.example.com/a'));

      final text = tester.widget<Text>(find.text('docs.example'));
      expect(text.style!.color, AppColors.primary);
      expect(text.style!.decoration, TextDecoration.underline);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.open_in_new)).color,
        AppColors.primary,
      );
    });

    testWidgets('태그 칩은 높이 20이고 4씩 띄운다', (tester) async {
      await pump(tester, _detail(tags: ['가', '나']));

      final first = tester.getRect(find.byType(ArchiveTagChip).at(0));
      final second = tester.getRect(find.byType(ArchiveTagChip).at(1));

      expect(first.height, 20);
      expect(second.height, 20);
      expect(second.left - first.right, 4);
    });

    testWidgets('태그 줄 마지막에 20px 추가 버튼이 있다', (tester) async {
      await pump(tester, _detail(tags: ['가']));

      final add = find.byKey(const ValueKey('archive-item-tag-add'));
      expect(add, findsOneWidget);
      final rect = tester.getRect(add);
      expect(rect.width, 20);
      expect(rect.height, 20);
      expect(
        rect.left,
        greaterThan(tester.getRect(find.byType(ArchiveTagChip)).right),
        reason: '칩들 뒤에 온다',
      );
    });

    testWidgets('⋯ 를 누르면 바텀시트가 아니라 옵션창이 버튼 아래에 뜬다', (tester) async {
      // 2026-08-05 요청: "우측위에 점세개 누르면 바텀시트말고 공통컴포넌트-옵션창".
      await pump(tester, _detail(pinned: false));

      final trigger = tester.getRect(find.byIcon(Icons.more_horiz));
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      expect(find.byType(OptionMenuCard<String>), findsOneWidget);
      expect(find.byType(ListTile), findsNothing, reason: '바텀시트 목록은 폐기');
      expect(find.text('폴더 이동'), findsOneWidget);
      expect(find.text('핀 고정'), findsOneWidget);
      expect(find.text('삭제'), findsOneWidget);

      final card = tester.getRect(find.byType(OptionMenuCard<String>));
      expect(
        card.top,
        greaterThanOrEqualTo(trigger.bottom - 1),
        reason: '버튼 아래',
      );
    });

    testWidgets('핀이 걸려 있으면 옵션창에 "핀 해제"로 나온다', (tester) async {
      await pump(tester, _detail(pinned: true));

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      expect(find.text('핀 해제'), findsOneWidget);
      expect(find.text('핀 고정'), findsNothing);
    });

    testWidgets('컬랩싱 히어로 대신 평범한 앱바를 쓴다', (tester) async {
      await pump(tester, _detail());

      expect(find.byType(SliverAppBar), findsNothing, reason: '컬랩싱 히어로 폐기');
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    });

    testWidgets('하위 페이지로 열면 뒤로가기가 chevron이다', (tester) async {
      // 앱바 기본 뒤로가기는 pop할 대상이 있을 때만 그려진다 — 실제처럼 push해서 확인한다.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ArchiveItemDetailScreen(
                    itemId: 1,
                    api: _FakeArchiveApi(detail: _detail()),
                    authService: _FakeAuthService(),
                    roomSession: RoomSession(roomApi: _FakeRoomApi()),
                  ),
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });

  testWidgets('제목·태그·좋아요 수·핀 상태가 렌더된다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      detail: _detail(title: '유용한 글', tags: ['여행'], likeCount: 2, pinned: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('유용한 글'), findsAtLeastNWidgets(1));
    expect(find.text('#여행'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const ValueKey('archive-detail-pin-on')), findsOneWidget);
  });

  testWidgets(
    'S-25-D: crawlStatus가 PENDING이면 배지와 안내 문구가 보이고 bodyText가 null이어도 죽지 않는다',
    (tester) async {
      final fakeApi = _FakeArchiveApi(
        detail: _detail(
          title: '분석 중인 링크',
          bodyText: null,
          crawlStatus: 'PENDING',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ArchiveItemDetailScreen(
            itemId: 1,
            api: fakeApi,
            authService: _FakeAuthService(),
            roomSession: RoomSession(roomApi: _FakeRoomApi()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('분석 중'), findsOneWidget);
      expect(find.text('자료를 분석하고 있어요. 잠시 후 다시 확인해 주세요.'), findsOneWidget);
      // 기다리라는 안내와 실패 안내가 함께 뜨면 안 된다(아래 FAILED 테스트의 반대 방향).
      expect(find.text('링크 내용을 가져오지 못했어요. 링크만 저장돼 있어요.'), findsNothing);
    },
  );

  testWidgets('S-25-D: crawlStatus가 FAILED이면 분석 실패 배지가 보인다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      detail: _detail(title: '분석 실패한 링크', crawlStatus: 'FAILED'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('분석 실패'), findsOneWidget);
  });

  testWidgets('S-25-D: crawlStatus가 FAILED이고 bodyText가 null이면 기다리라고 하지 않는다', (
    tester,
  ) async {
    // 실제로 겪은 버그: agoda 같은 SPA 링크는 본문이 0자라 FAILED로 끝나는데,
    // 본문 자리 폴백이 상태를 보지 않아 "분석 실패" 배지와 "잠시 후 다시 확인해 주세요"가
    // 한 화면에 같이 떴다. 영원히 바뀌지 않는 상태인데 기다리라고 안내한 셈이다.
    // 위 FAILED 테스트가 bodyText 기본값('본문')을 써서 이 조합을 한 번도 밟지 않았다.
    final fakeApi = _FakeArchiveApi(
      detail: _detail(
        title: '분석 실패한 링크',
        bodyText: null,
        crawlStatus: 'FAILED',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('분석 실패'), findsOneWidget);
    expect(find.text('링크 내용을 가져오지 못했어요. 링크만 저장돼 있어요.'), findsOneWidget);
    expect(find.text('자료를 분석하고 있어요. 잠시 후 다시 확인해 주세요.'), findsNothing);
  });

  testWidgets('S-25-D: DONE인데 bodyText가 null이면 어떤 안내 문구도 만들지 않는다', (
    tester,
  ) async {
    // 실제로는 생기지 않는 조합이지만(텍스트 등록은 본문 필수, 크롤 DONE은 빈 본문이면 예외),
    // 폴백이 상태를 보지 않으면 여기서도 거짓말을 하게 된다. 요약이 없을 때 영역 자체를
    // 만들지 않는 규칙(specs/0010의 "S-25-B AI 요약 표시" 항목)과 같은 방향으로 비워 둔다.
    final fakeApi = _FakeArchiveApi(
      detail: _detail(title: '본문 없는 자료', bodyText: null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('자료를 분석하고 있어요. 잠시 후 다시 확인해 주세요.'), findsNothing);
    expect(find.text('링크 내용을 가져오지 못했어요. 링크만 저장돼 있어요.'), findsNothing);
  });

  group('AI 요약', () {
    const summary = '강릉 당일치기 맛집 투어 코스다. 사근진해변과 경포호를 포함한다.';
    const bodyText = '오늘은 강릉에 다녀왔다. 밥 3번, 카페 3곳, 디저트 6곳.';

    /// 화면에서는 **문장마다 별도 `Text`** 로 나뉜다(2026-08-08, QA 가독성).
    /// 저장값(`summary`)은 그대로이고 렌더링에서만 나뉜다.
    const firstSentence = '강릉 당일치기 맛집 투어 코스다.';
    const secondSentence = '사근진해변과 경포호를 포함한다.';

    Future<void> pump(WidgetTester tester, ArchiveItemDetail detail) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ArchiveItemDetailScreen(
            itemId: 1,
            api: _FakeArchiveApi(detail: detail),
            authService: _FakeAuthService(),
            roomSession: RoomSession(roomApi: _FakeRoomApi()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('AI 배너가 뜨고 그 아래 요약문이 본문으로 나온다', (tester) async {
      // 2026-08-05 재디자인: 회색 'AI 요약' 카드 → AiHintBanner + 요약문(body 16).
      await pump(tester, _detail(summary: summary, bodyText: bodyText));

      expect(find.text('MODI가 읽기 좋게 본문을 요약했어요'), findsOneWidget);
      expect(find.text(firstSentence), findsOneWidget);
      expect(find.text(secondSentence), findsOneWidget);
      expect(find.text('AI 요약'), findsNothing, reason: '회색 카드 라벨은 폐기됐다');

      final bannerY = tester.getTopLeft(find.text('MODI가 읽기 좋게 본문을 요약했어요')).dy;
      expect(
        bannerY,
        lessThan(tester.getTopLeft(find.text(firstSentence)).dy),
        reason: '배너가 요약문 위에 있어야 한다',
      );
    });

    testWidgets('크롤링 원문(bodyText)은 화면에 싣지 않는다', (tester) async {
      // 2026-08-05 사용자 확정: "요약만 본문으로 (원문 숨김)".
      await pump(tester, _detail(summary: summary, bodyText: bodyText));

      expect(find.text(bodyText), findsNothing);
    });

    testWidgets('요약이 없으면 배너도 없다', (tester) async {
      // V5 이전 등록분·크롤링 전·요약 실패가 모두 이 상태다. "요약 없음" 문구를 띄우지 않는다.
      await pump(tester, _detail(summary: null, bodyText: bodyText));

      expect(find.text('MODI가 읽기 좋게 본문을 요약했어요'), findsNothing);
      expect(find.text('AI 요약'), findsNothing);
    });

    testWidgets('크롤링 전(PENDING)이라도 요약이 있으면 요약만 보여준다', (tester) async {
      // 요약이 있으면 그게 본문 자리를 차지하므로 "분석하고 있어요" 안내는 나오지 않는다 —
      // 보여줄 게 있는데 기다리라고 하면 모순이다.
      await pump(
        tester,
        _detail(summary: summary, bodyText: null, crawlStatus: 'PENDING'),
      );

      expect(find.text(firstSentence), findsOneWidget);
      expect(find.text(secondSentence), findsOneWidget);
      expect(find.text('자료를 분석하고 있어요. 잠시 후 다시 확인해 주세요.'), findsNothing);
    });

    testWidgets('요약이 없고 PENDING이면 분석 중 안내가 본문 자리에 온다', (tester) async {
      await pump(
        tester,
        _detail(summary: null, bodyText: null, crawlStatus: 'PENDING'),
      );

      expect(find.text('자료를 분석하고 있어요. 잠시 후 다시 확인해 주세요.'), findsOneWidget);
    });
  });

  testWidgets('핀 토글은 즉시 반영되고, 실패하면 되돌아간다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      detail: _detail(pinned: false),
      throwOnPin: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 핀 토글은 ··· 메뉴로 이동했다.
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('핀 고정'));
    await tester.pumpAndSettle();

    // 네트워크 호출은 낙관적으로 즉시 나갔지만(반전된 값), 실패했으므로 원래 상태로
    // 복원되고 에러 문구가 보인다. 복원돼 사진 위 핀이 다시 미고정(off) 상태다.
    expect(fakeApi.pinCalls, [true]);
    expect(
      find.byKey(const ValueKey('archive-detail-pin-off')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('archive-detail-pin-on')), findsNothing);
    expect(find.text('핀 고정 변경에 실패했어요'), findsOneWidget);
  });

  testWidgets('메모가 있으면 표시된다', (tester) async {
    final fakeApi = _FakeArchiveApi(detail: _detail(memo: '내 메모 한 줄'));

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('내 메모 한 줄'), findsOneWidget);
  });

  testWidgets('메모가 없으면 옵션창에 "메모 추가"로 나오고, 저장하면 표시된다', (tester) async {
    final fakeApi = _FakeArchiveApi(detail: _detail(memo: null));

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('메모 추가'), findsOneWidget);
    expect(find.text('메모 편집'), findsNothing);

    await tester.tap(find.text('메모 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '새로 적은 메모');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(fakeApi.memoCalls, ['새로 적은 메모']);
    expect(find.text('새로 적은 메모'), findsOneWidget);
  });

  testWidgets('메모가 있으면 옵션창에 "메모 편집"으로 나오고, 다이얼로그에 기존 값이 채워진다', (tester) async {
    final fakeApi = _FakeArchiveApi(detail: _detail(memo: '옛 메모'));

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('메모 편집'), findsOneWidget);
    await tester.tap(find.text('메모 편집'));
    await tester.pumpAndSettle();

    // find.text는 그 아래 화면의 메모 표시(Text)와 다이얼로그 입력창(EditableText) 둘 다 잡으므로
    // 다이얼로그 안으로 좁힌다.
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('옛 메모')),
      findsOneWidget,
    );
  });

  testWidgets('메모 저장 실패 시 에러 안내가 보인다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      detail: _detail(memo: null),
      throwOnMemo: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('메모 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '메모');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    // 2026-08-06 리뷰 반영: 실패해도 다이얼로그가 닫히지 않고 입력값이 남아 있어야
    // 처음부터 다시 타이핑하지 않고 곧바로 재시도할 수 있다.
    expect(find.text('메모 저장에 실패했어요'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('메모'), findsOneWidget);
    expect(fakeApi.memoCalls, ['메모']);
  });

  testWidgets('더보기 메뉴에 "링크 수정"이 없다 — 2026-08-08 제거됨', (tester) async {
    final fakeApi = _FakeArchiveApi(
      detail: _detail(url: 'https://old.example.com'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    expect(find.text('링크 수정'), findsNothing);
    // 나머지 메뉴 항목은 그대로 남아 있다.
    expect(find.text('폴더 이동'), findsOneWidget);
    expect(find.text('삭제'), findsOneWidget);
  });

  testWidgets('좋아요 토글 시 하트와 카운트가 즉시 바뀐다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      detail: _detail(likedByMe: false, likeCount: 3),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(fakeApi.likeCalls, [true]);
  });

  testWidgets('하단 반응 바는 스크롤 영역이 아니라 Scaffold.bottomNavigationBar에 고정된다', (
    tester,
  ) async {
    // 2026-08-08 요청: 본문 길이와 무관하게 화면 하단에 항상 보이게.
    final fakeApi = _FakeArchiveApi(detail: _detail(likeCount: 5));

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.bottomNavigationBar, isNotNull);
    expect(
      find.descendant(
        of: find.byWidget(scaffold.bottomNavigationBar!),
        matching: find.byIcon(Icons.favorite_border),
      ),
      findsOneWidget,
      reason: '좋아요가 bottomNavigationBar 안에 있어야 한다',
    );
    // 본문 스크롤 영역(SingleChildScrollView) 안에는 더 이상 좋아요가 없다.
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byIcon(Icons.favorite_border),
      ),
      findsNothing,
    );
  });

  // ---- 태그: 2026-08-05부터 저장 버튼 없이 **즉시** 반영 ----

  testWidgets('+ 로 태그를 추가하면 즉시 서버에 저장된다', (tester) async {
    final fakeApi = _FakeArchiveApi(detail: _detail(tags: ['기존']));

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('태그 저장'), findsNothing, reason: '저장 버튼은 폐기됐다');

    await tester.tap(find.byKey(const ValueKey('archive-item-tag-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('archive-item-tag-input')),
      '새태그',
    );
    await tester.tap(find.byKey(const ValueKey('archive-item-tag-submit')));
    await tester.pumpAndSettle();

    expect(find.text('#새태그'), findsOneWidget);
    expect(fakeApi.tagsCalls, [
      ['기존', '새태그'],
    ]);
  });

  testWidgets('태그의 x를 탭하면 저장 버튼 없이 바로 저장된다', (tester) async {
    final fakeApi = _FakeArchiveApi(detail: _detail(tags: ['지울태그']));

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('#지울태그'), findsNothing);
    expect(fakeApi.tagsCalls, [[]], reason: '별도 저장 없이 즉시 PATCH');
  });

  testWidgets('태그 저장이 실패하면 목록이 되돌아가고 안내가 뜬다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      detail: _detail(tags: ['살아남을태그']),
      throwOnTags: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('#살아남을태그'), findsOneWidget, reason: '실패했으니 되돌아온다');
    expect(find.text('태그 저장에 실패했어요'), findsOneWidget);
  });

  testWidgets('이미 있는 태그를 넣으면 안내하고 서버를 부르지 않는다', (tester) async {
    final fakeApi = _FakeArchiveApi(detail: _detail(tags: ['중복']));

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('archive-item-tag-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('archive-item-tag-input')),
      '중복',
    );
    await tester.tap(find.byKey(const ValueKey('archive-item-tag-submit')));
    await tester.pumpAndSettle();

    expect(find.text('이미 있는 태그예요'), findsOneWidget);
    expect(fakeApi.tagsCalls, isEmpty);
  });

  testWidgets('폴더 이동 시트에서 폴더를 선택하면 즉시 이동한다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      detail: _detail(folderId: 1),
      folders: [
        ArchiveFolder(id: 1, name: '현재 폴더', itemCount: 1),
        ArchiveFolder(id: 2, name: '다른 폴더', itemCount: 0),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 폴더 이동은 ··· 메뉴로 이동했다.
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('폴더 이동'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다른 폴더'));
    await tester.pumpAndSettle();

    expect(fakeApi.moveCalls, [2]);
  });

  testWidgets('삭제 확인 모달을 거쳐야 삭제 API가 호출된다', (tester) async {
    final fakeApi = _FakeArchiveApi(detail: _detail(title: '삭제될 항목'));

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 삭제는 ··· 메뉴로 이동했다.
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(fakeApi.deleteCallCount, 0);
    expect(find.text('이 자료를 삭제할까요?'), findsOneWidget);

    await tester.tap(find.text('삭제').last);
    await tester.pumpAndSettle();

    expect(fakeApi.deleteCallCount, 1);
  });

  testWidgets('삭제 확인 팝업은 로그아웃·방나가기와 같은 공용 다이얼로그 스타일이다', (tester) async {
    final fakeApi = _FakeArchiveApi(detail: _detail(title: '삭제될 항목'));

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    // showActionConfirmDialog는 기본 AlertDialog가 아니라 [취소|확인] 2버튼의 공용
    // Dialog 셸을 쓴다 — 로그아웃/방나가기 확인창과 같은 위젯 트리.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('취소'), findsOneWidget);
    expect(find.text('삭제하면 되돌릴 수 없어요.'), findsOneWidget);

    // 바깥(취소)으로 닫으면 삭제가 호출되지 않는다.
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(fakeApi.deleteCallCount, 0);
  });

  testWidgets('로드 실패 시 에러 안내와 재시도 버튼이 보이고, 재시도하면 다시 호출한다', (tester) async {
    final fakeApi = _FakeArchiveApi(throwOnFetch: true);

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('자료를 불러오지 못했어요'), findsOneWidget);
    expect(fakeApi.fetchCallCount, 1);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(fakeApi.fetchCallCount, 2);
  });

  testWidgets('진행 중인 방이 없으면 안내가 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: _FakeArchiveApi(),
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _NoActiveRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('진행 중인 방이 없어요'), findsOneWidget);
  });

  // ---------------------------------------------------------------- 링크 열기

  testWidgets('저장된 링크를 탭하면 외부 브라우저로 연다', (tester) async {
    // 🔴 2026-08-05 사용자 신고: primary 색만 입힌 SelectableText 라 **링크처럼 보이는데
    // 아무 일도 안 일어났다.** 어포던스만 있고 동작이 없던 것을 고쳤다.
    final opened = <Uri>[];
    final fakeApi = _FakeArchiveApi(
      detail: _detail(url: 'https://naver.me/52aGF4S5'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          openLink: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('naver'));
    await tester.pumpAndSettle();

    expect(opened, [Uri.parse('https://naver.me/52aGF4S5')]);
  });

  testWidgets('열 앱이 없으면 안내가 뜬다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      detail: _detail(url: 'https://example.com/a'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          openLink: (uri) async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('example'));
    await tester.pumpAndSettle();

    expect(find.text('링크를 열 수 있는 앱이 없어요'), findsOneWidget);
  });

  testWidgets('열다가 실패해도 화면이 죽지 않는다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      detail: _detail(url: 'https://example.com/a'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          openLink: (uri) async => throw StateError('no activity'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('example'));
    await tester.pumpAndSettle();

    expect(find.text('링크를 열지 못했어요'), findsOneWidget);
  });

  testWidgets('http(s)가 아닌 주소는 열지 않는다', (tester) async {
    // 🔴 `url` 은 사용자가 공유한 값에서 온다. 서버가 이미 스킴을 검증하지만, 옛 데이터나 서버
    // 변경으로 다른 스킴이 들어오면 앱이 intent:·javascript: 를 열어주는 통로가 된다.
    final opened = <Uri>[];
    final fakeApi = _FakeArchiveApi(
      detail: _detail(url: 'javascript:alert(1)'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveItemDetailScreen(
          itemId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
          openLink: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('javascript:alert(1)'));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.text('열 수 없는 주소예요'), findsOneWidget);
  });
  // ------------------------------------------- AI 요약 만들기 (2026-08-06)

  testWidgets('요약이 없으면 만들기 버튼이 보인다', (tester) async {
    // 🔴 텍스트로 등록한 자료가 이 상태로 들어온다 — 자동 요약을 하지 않게 바꿨다.
    // 짧은 메모는 본문이 곧 요약이라 기다림만 생겼다(유저 테스트 피드백).
    final api = _FakeArchiveApi(
      detail: _detail(summary: null, bodyText: '적어둔 메모'),
    );

    await _pumpDetail(tester, api);

    expect(find.text('AI 요약 만들기'), findsOneWidget);
  });

  testWidgets('요약이 이미 있으면 버튼을 띄우지 않는다', (tester) async {
    // 서버가 400 으로 거절하는 요청을 버튼으로 유도하면 안 된다.
    final api = _FakeArchiveApi(detail: _detail(summary: '이미 있는 요약'));

    await _pumpDetail(tester, api);

    expect(find.text('AI 요약 만들기'), findsNothing);
  });

  testWidgets('요약할 본문이 없으면 버튼을 띄우지 않는다', (tester) async {
    // 크롤링이 실패한 자료 — 요약할 것이 없는데 버튼을 주면 눌러도 실패만 한다.
    final api = _FakeArchiveApi(
      detail: _detail(summary: null, bodyText: null, crawlStatus: 'FAILED'),
    );

    await _pumpDetail(tester, api);

    expect(find.text('AI 요약 만들기'), findsNothing);
  });

  testWidgets('버튼을 누르면 요약이 만들어져 화면에 보인다', (tester) async {
    final api = _FakeArchiveApi(
      detail: _detail(summary: null, bodyText: '적어둔 메모'),
    );

    await _pumpDetail(tester, api);
    await tester.tap(find.text('AI 요약 만들기'));
    await tester.pumpAndSettle();

    expect(api.summarizeCallCount, 1);
    expect(find.text('방금 만든 요약'), findsOneWidget);
    expect(find.text('AI 요약 만들기'), findsNothing);
  });

  testWidgets('요약에 실패하면 안내가 뜨고 버튼이 남는다', (tester) async {
    // 다시 누를 수 있어야 한다 — 실패는 게이트웨이 순단일 수 있다.
    final api = _FakeArchiveApi(
      detail: _detail(summary: null, bodyText: '적어둔 메모'),
      throwOnSummarize: true,
    );

    await _pumpDetail(tester, api);
    await tester.tap(find.text('AI 요약 만들기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('요약을 만들지 못했어요'), findsOneWidget);
    expect(find.text('AI 요약 만들기'), findsOneWidget);
  });

  group('댓글(2026-08-09)', () {
    testWidgets('하단 반응 바에 좋아요 옆 댓글 아이콘+카운트가 보인다', (tester) async {
      final fakeApi = _FakeArchiveApi(
        detail: _detail(likeCount: 12, commentCount: 7),
      );
      await _pumpDetail(tester, fakeApi);

      final commentButton = find.byKey(
        const ValueKey('archive-detail-comments'),
      );
      expect(commentButton, findsOneWidget);
      expect(
        find.descendant(of: commentButton, matching: find.text('7')),
        findsOneWidget,
      );
      // 좋아요 왼쪽 · 댓글 오른쪽.
      final like = tester.getRect(find.byIcon(Icons.favorite_border));
      final comment = tester.getRect(find.byIcon(Icons.chat_bubble_outline));
      expect(like.right, lessThan(comment.left));
    });

    testWidgets('댓글 버튼을 탭하면 시트가 열리고 목록(작성자·본문)이 보인다', (tester) async {
      final fakeApi = _FakeArchiveApi(detail: _detail(commentCount: 2))
        ..comments = [
          ArchiveComment(
            id: 1,
            author: ArchiveItemCreator(userId: 'u1', nickname: '예팔'),
            body: '첫 번째 댓글',
            createdAt: DateTime(2026, 8, 8),
          ),
          ArchiveComment(
            id: 2,
            author: null, // 탈퇴 작성자
            body: '두 번째 댓글',
            createdAt: DateTime(2026, 8, 9),
          ),
        ];
      await _pumpDetail(tester, fakeApi);

      await tester.tap(find.byKey(const ValueKey('archive-detail-comments')));
      await tester.pumpAndSettle();

      expect(find.text('댓글'), findsOneWidget);
      expect(find.text('예팔'), findsOneWidget);
      expect(find.text('첫 번째 댓글'), findsOneWidget);
      expect(find.text('(알 수 없음)'), findsOneWidget, reason: '탈퇴 작성자 폴백');
      expect(find.text('두 번째 댓글'), findsOneWidget);
    });

    testWidgets('댓글을 입력해 전송하면 목록에 붙고 하단 바 카운트가 갱신된다', (tester) async {
      final fakeApi = _FakeArchiveApi(detail: _detail(commentCount: 0));
      await _pumpDetail(tester, fakeApi);

      await tester.tap(find.byKey(const ValueKey('archive-detail-comments')));
      await tester.pumpAndSettle();
      expect(find.text('첫 댓글을 남겨보세요'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('archive-comment-field')),
        '화이팅!',
      );
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      expect(fakeApi.commentCalls, ['화이팅!']);
      expect(find.text('화이팅!'), findsOneWidget, reason: '목록에 즉시 붙는다');

      // 시트를 닫으면 하단 바 카운트가 1로 갱신돼 있다.
      await tester.tapAt(const Offset(400, 50)); // 딤 영역 탭 → 닫기
      await tester.pumpAndSettle();
      final commentButton = find.byKey(
        const ValueKey('archive-detail-comments'),
      );
      expect(
        find.descendant(of: commentButton, matching: find.text('1')),
        findsOneWidget,
      );
    });
  });
}

/// 상세 화면을 띄우고 첫 로드를 끝낸다.
Future<void> _pumpDetail(WidgetTester tester, _FakeArchiveApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ArchiveItemDetailScreen(
        itemId: 1,
        api: api,
        authService: _FakeAuthService(),
        roomSession: RoomSession(roomApi: _FakeRoomApi()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
