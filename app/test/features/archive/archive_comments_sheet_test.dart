import 'package:app/design/theme.dart';
import 'package:app/features/archive/archive_api.dart';
import 'package:app/features/archive/archive_comments_sheet.dart';
import 'package:app/features/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 자료 댓글 시트(S-25-B) — 본인 한정 수정/삭제.
///
/// 🔴 이 시트는 2026-08-09 에 구현됐는데 **테스트가 없었다**(2026-08-16 로드맵 정합성
/// 작업 중 발견). `archive_item_detail_screen_test.dart` 의 `_FakeAuthService` 는
/// `currentUserId => null` 로 눌러 `⋯` 가 아예 안 뜨게 해 두고 *"현재 댓글 테스트는
/// ⋯를 검증하지 않는다"* 고 적어 뒀다 — 즉 **작성자 판정이 한 번도 검증된 적이 없다.**
///
/// 서버는 작성자 본인이 아니면 403 이지만(`NotCommentAuthorException`), 앱이 남의 댓글에
/// `⋯` 를 띄우면 사용자는 눌렀다가 실패를 본다. 그 판정을 여기서 고정한다.

const _myUid = 'uid-me';

class _FakeAuthService extends AuthService {
  _FakeAuthService({this.uid = _myUid});

  final String? uid;

  @override
  Future<String> getIdToken() async => 'fake-token';

  @override
  String? get currentUserId => uid;
}

class _FakeArchiveApi extends ArchiveApi {
  _FakeArchiveApi({required this.comments, this.failMutations = false});

  List<ArchiveComment> comments;
  final bool failMutations;

  final List<int> deletedIds = [];
  final List<(int, String)> updated = [];

  @override
  Future<List<ArchiveComment>> fetchComments(
    String idToken,
    int roomId,
    int itemId,
  ) async => comments;

  @override
  Future<ArchiveItemCreator> fetchMyBrief(String idToken) async =>
      ArchiveItemCreator(userId: _myUid, nickname: '나');

  @override
  Future<ArchiveComment> updateComment(
    String idToken,
    int roomId,
    int itemId,
    int commentId,
    String body,
  ) async {
    if (failMutations) throw StateError('서버 오류');
    updated.add((commentId, body));
    return _comment(id: commentId, body: body, authorId: _myUid);
  }

  @override
  Future<void> deleteComment(
    String idToken,
    int roomId,
    int itemId,
    int commentId,
  ) async {
    if (failMutations) throw StateError('서버 오류');
    deletedIds.add(commentId);
  }
}

ArchiveComment _comment({
  required int id,
  required String body,
  String? authorId,
  String nickname = '작성자',
}) {
  return ArchiveComment(
    id: id,
    body: body,
    createdAt: DateTime(2026, 8, 16, 10),
    author: authorId == null
        ? null
        : ArchiveItemCreator(userId: authorId, nickname: nickname),
  );
}

void main() {
  Future<_FakeArchiveApi> pump(
    WidgetTester tester, {
    required List<ArchiveComment> comments,
    String? currentUserId = _myUid,
    bool failMutations = false,
    void Function(int)? onCountChanged,
  }) async {
    final api = _FakeArchiveApi(
      comments: comments,
      failMutations: failMutations,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ArchiveCommentsSheet(
            api: api,
            authService: _FakeAuthService(uid: currentUserId),
            roomId: 1,
            itemId: 2,
            onCountChanged: onCountChanged ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  /// 🔴 이 파일의 핵심. 서버가 403 으로 막기 전에 앱이 먼저 안 보여줘야 한다.
  testWidgets('⋯ 는 내 댓글에만 붙는다 — 남의 댓글·탈퇴 작성자에는 없다', (tester) async {
    await pump(
      tester,
      comments: [
        _comment(id: 1, body: '내 댓글', authorId: _myUid, nickname: '나'),
        _comment(id: 2, body: '남의 댓글', authorId: 'uid-other', nickname: '남'),
        _comment(id: 3, body: '탈퇴한 사람 댓글'), // author == null
      ],
    );

    expect(find.text('내 댓글'), findsOneWidget);
    expect(find.text('남의 댓글'), findsOneWidget);
    expect(find.text('탈퇴한 사람 댓글'), findsOneWidget);

    // 댓글 3개 중 ⋯ 는 하나뿐이어야 한다.
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
  });

  testWidgets('로그인 사용자를 모르면 어떤 댓글에도 ⋯ 가 붙지 않는다', (tester) async {
    await pump(
      tester,
      currentUserId: null,
      comments: [_comment(id: 1, body: '내 댓글', authorId: _myUid)],
    );

    expect(find.byIcon(Icons.more_horiz), findsNothing);
  });

  testWidgets('내 댓글을 수정하면 서버로 새 본문이 나가고 목록이 갱신된다', (tester) async {
    final api = await pump(
      tester,
      comments: [_comment(id: 7, body: '고치기 전', authorId: _myUid)],
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '고친 뒤');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(api.updated, [(7, '고친 뒤')]);
    expect(find.text('고친 뒤'), findsOneWidget);
    expect(find.text('고치기 전'), findsNothing);
  });

  testWidgets('수정 다이얼로그에서 취소하면 서버를 부르지 않는다', (tester) async {
    final api = await pump(
      tester,
      comments: [_comment(id: 7, body: '그대로', authorId: _myUid)],
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '바꾼 척');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(api.updated, isEmpty);
    expect(find.text('그대로'), findsOneWidget);
  });

  testWidgets('삭제는 확인 모달을 거치고, 확정하면 목록과 카운트가 함께 줄어든다', (tester) async {
    final counts = <int>[];
    final api = await pump(
      tester,
      onCountChanged: counts.add,
      comments: [
        _comment(id: 7, body: '지울 댓글', authorId: _myUid),
        _comment(id: 8, body: '남길 댓글', authorId: 'uid-other'),
      ],
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    // 확인 모달이 떠야 한다 — 파괴적 액션은 확인을 거친다(CLAUDE.md).
    expect(find.text('댓글을 삭제할까요?'), findsOneWidget);
    expect(api.deletedIds, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();

    expect(api.deletedIds, [7]);
    expect(find.text('지울 댓글'), findsNothing);
    expect(find.text('남길 댓글'), findsOneWidget);
    // 최초 로드에서 2, 삭제 뒤 1 — 부모 하단 바 카운트가 어긋나지 않게 콜백으로 알린다
    // (시트가 드래그로 닫혀도 맞도록 pop 결과가 아니라 콜백을 쓴다).
    expect(counts, [2, 1]);
  });

  testWidgets('삭제 확인 모달에서 취소하면 서버를 부르지 않는다', (tester) async {
    final api = await pump(
      tester,
      comments: [_comment(id: 7, body: '지우지 않을 댓글', authorId: _myUid)],
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    expect(api.deletedIds, isEmpty);
    expect(find.text('지우지 않을 댓글'), findsOneWidget);
  });

  testWidgets('삭제가 서버에서 실패하면 목록을 지우지 않고 안내만 띄운다', (tester) async {
    await pump(
      tester,
      failMutations: true,
      comments: [_comment(id: 7, body: '살아남을 댓글', authorId: _myUid)],
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '삭제'));
    await tester.pumpAndSettle();

    expect(find.text('댓글 삭제에 실패했어요'), findsOneWidget);
    expect(find.text('살아남을 댓글'), findsOneWidget);
  });
}
