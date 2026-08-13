import 'dart:async';

import 'package:app/features/archive/archive_api.dart';
import 'package:app/features/archive/archive_folder_items_screen.dart';
import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/room/room_api.dart';
import 'package:app/features/room/room_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
}

class _FakeArchiveApi extends ArchiveApi {
  _FakeArchiveApi({
    this.folderName = '폴더',
    List<ArchiveItem>? items,
    this.throwOnFetch = false,
    List<ArchiveFolder>? folders,
  }) : items = items ?? [],
       folders = folders ?? [ArchiveFolder(id: 1, name: '현재 폴더', itemCount: 0)];

  String folderName;
  List<ArchiveItem> items;
  bool throwOnFetch;
  int fetchCallCount = 0;

  /// 조회를 붙잡아 세우는 문 — 응답이 오기 전 프레임을 검사할 때 쓴다.
  Completer<void>? fetchGate;
  List<ArchiveFolder> folders;
  final List<Map<String, dynamic>> createCalls = [];

  @override
  Future<ArchiveFolderItems> fetchFolderItems(
    String idToken,
    int roomId,
    int folderId,
  ) async {
    fetchCallCount++;
    if (throwOnFetch) throw StateError('network');
    if (fetchGate != null) await fetchGate!.future;
    return ArchiveFolderItems(
      folderId: folderId,
      folderName: folderName,
      items: items,
    );
  }

  @override
  Future<List<ArchiveFolder>> fetchFolders(String idToken, int roomId) async {
    return folders;
  }

  /// 이미지 탭 피드 픽스처 — 기본 빈 목록(서버 미구현 상태와 동일).
  List<ArchiveTodoImage> images = [];
  final List<({int imageId, bool pinned})> imagePinCalls = [];

  @override
  Future<List<ArchiveTodoImage>> fetchTodoImages(
    String idToken,
    int roomId,
  ) async => images;

  @override
  Future<void> setTodoImagePinned(
    String idToken,
    int roomId,
    int imageId,
    bool pinned,
  ) async {
    imagePinCalls.add((imageId: imageId, pinned: pinned));
  }

  final List<({int itemId, bool pinned})> pinCalls = [];

  @override
  Future<ArchiveItemDetail> setItemPinned(
    String idToken,
    int roomId,
    int itemId,
    bool pinned,
  ) async {
    pinCalls.add((itemId: itemId, pinned: pinned));
    return ArchiveItemDetail(
      id: itemId,
      folderId: 1,
      title: '',
      url: null,
      source: null,
      thumbnail: null,
      summary: null,
      bodyText: '',
      pinned: pinned,
      tags: const [],
      likeCount: 0,
      likedByMe: false,
      createdAt: DateTime(2026, 7, 27),
      crawlStatus: 'DONE',
    );
  }

  @override
  Future<ArchiveItemDetail> createItem(
    String idToken,
    int roomId,
    int folderId, {
    String? url,
    String? text,
    String? memo,
    String? imageUrl,
    String? title,
  }) async {
    createCalls.add({
      'folderId': folderId,
      'url': url,
      'text': text,
      'memo': memo,
      'imageUrl': imageUrl,
      'title': title,
    });
    return ArchiveItemDetail(
      id: 999,
      folderId: folderId,
      title: title ?? text ?? url ?? '',
      url: url,
      source: null,
      thumbnail: null,
      imageUrl: imageUrl,
      summary: null,
      bodyText: text ?? '',
      pinned: false,
      tags: const [],
      likeCount: 0,
      likedByMe: false,
      createdAt: DateTime(2026, 7, 27),
      crawlStatus: 'DONE',
    );
  }
}

ArchiveItem _item({
  required int id,
  required String title,
  List<String> tags = const [],
  int likeCount = 0,
  bool pinned = false,
  DateTime? createdAt,
  String crawlStatus = 'DONE',
  String? url = 'https://example.com/a', // 기본은 링크 자료(링크 탭). 텍스트 자료는 url: null.
  String? imageUrl, // 폴더 직접 업로드 이미지 자료(이미지 탭)면 채운다 — url은 null이어야 한다.
}) {
  return ArchiveItem(
    id: id,
    title: title,
    url: url,
    source: '출처',
    thumbnail: null,
    imageUrl: imageUrl,
    pinned: pinned,
    createdAt: createdAt ?? DateTime(2026, 7, 20),
    tags: tags,
    likeCount: likeCount,
    crawlStatus: crawlStatus,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('카드에 제목·태그·도메인이 렌더되고 총 개수가 보인다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      folderName: '스터디 자료',
      items: [
        _item(
          id: 1,
          title: '유용한 글',
          tags: ['여행', '맛집'],
          likeCount: 3,
          url: 'https://velog.io/@me/dp-note',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('스터디 자료'), findsOneWidget); // 상단바 폴더명
    expect(find.text('총 1개'), findsOneWidget); // 리스트 헤더 개수
    expect(find.text('유용한 글'), findsOneWidget);
    expect(find.text('#여행'), findsOneWidget);
    expect(find.text('#맛집'), findsOneWidget);
    // 좋아요 수는 카드 우상단에 작게 표시한다(2026-08-09 요청 — 목록에서도 보이게).
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    // 리디자인(2026-08-08): 날짜·출처 대신 URL 도메인.
    expect(find.text('velog.io'), findsOneWidget);
  });

  testWidgets('링크 자료의 도메인 추출(www 제거)', (tester) async {
    final fakeApi = _FakeArchiveApi(
      items: [_item(id: 1, title: '글', url: 'https://www.naver.com/a')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('naver.com'), findsOneWidget); // www. 제거
  });

  testWidgets('S-25-D: crawlStatus에 따라 분석 중/분석 실패 배지가 보이고 DONE은 배지가 없다', (
    tester,
  ) async {
    final fakeApi = _FakeArchiveApi(
      folderName: '읽을거리',
      items: [
        _item(id: 1, title: '분석 중인 링크', crawlStatus: 'PENDING'),
        _item(id: 2, title: '분석 실패한 링크', crawlStatus: 'FAILED'),
        _item(id: 3, title: '정상 항목', crawlStatus: 'DONE'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('분석 중'), findsOneWidget);
    expect(find.text('분석 실패'), findsOneWidget);
  });

  testWidgets('분석 상태 배지는 제목 아래가 아니라 태그 칩과 같은 줄에 온다', (tester) async {
    // 2026-08-05 요청: "분석실패 칩 기존 칩 위치로". 예전에는 타일 맨 아래(날짜 밑)에 있었다.
    final fakeApi = _FakeArchiveApi(
      folderName: '읽을거리',
      items: [
        _item(id: 1, title: '분석 실패한 링크', tags: ['여행'], crawlStatus: 'FAILED'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final badge = tester.getRect(find.text('분석 실패'));
    final chip = tester.getRect(find.text('#여행'));
    final title = tester.getRect(find.text('분석 실패한 링크'));

    expect(badge.center.dy, closeTo(chip.center.dy, 2), reason: '칩과 같은 줄');
    expect(badge.bottom, lessThan(title.top), reason: '제목 위에 있다');
  });

  testWidgets('등록 시트를 바깥 탭으로 닫으면 에러도 스피너도 뜨지 않는다', (tester) async {
    // 2026-08-05 신고: "파일 추가 바텀시트 닫으려고 바깥 영역 누르면 에러 뜸 + 로딩".
    final fakeApi = _FakeArchiveApi(items: [_item(id: 1, title: '기존자료')]);

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fetchesBefore = fakeApi.fetchCallCount;

    await tester.tap(find.byKey(const ValueKey('archive-register-button')));
    await tester.pumpAndSettle();
    // ＋는 이제 바로 시트를 열지 않고 옵션창(링크/텍스트/이미지 추가)을 먼저 띄운다(2026-08-08).
    await tester.tap(find.text('링크 추가'));
    await tester.pumpAndSettle();
    expect(find.text('자료 등록'), findsOneWidget);

    // 시트 바깥(맨 위)을 탭해 닫는다.
    await tester.tapAt(const Offset(400, 40));
    await tester.pumpAndSettle();

    expect(find.text('자료 등록'), findsNothing, reason: '시트가 닫힌다');
    expect(find.textContaining('불러오지 못했어요'), findsNothing, reason: '에러 없음');
    expect(find.text('자료를 불러오고 있어요'), findsNothing, reason: '스피너 없음');
    expect(find.text('기존자료'), findsOneWidget, reason: '목록이 그대로 남는다');
    expect(
      fakeApi.fetchCallCount,
      fetchesBefore,
      reason: '등록하지 않았으므로 다시 조회하지 않는다',
    );
  });

  testWidgets('자료를 등록한 뒤 재조회하는 동안에도 기존 목록이 그대로 보인다', (tester) async {
    // 2026-08-05 요청: "로딩 없애기, 기존 자료 보여주고 자료 추가되면 그 상태에서 추가되게".
    final fakeApi = _FakeArchiveApi(items: [_item(id: 1, title: '기존자료')]);

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('archive-register-button')));
    await tester.pumpAndSettle();
    // ＋는 이제 바로 시트를 열지 않고 옵션창(링크/텍스트/이미지 추가)을 먼저 띄운다(2026-08-08).
    await tester.tap(find.text('텍스트 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '새자료');
    // 등록 후 목록 재조회를 붙잡아 세운다.
    fakeApi.fetchGate = Completer<void>();
    await tester.tap(find.text('등록'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 시트 닫힘 애니메이션

    expect(find.text('자료를 불러오고 있어요'), findsNothing, reason: '스피너로 갈아끼우지 않는다');
    expect(find.text('기존자료'), findsOneWidget);

    fakeApi.items = [_item(id: 1, title: '기존자료'), _item(id: 2, title: '새자료')];
    fakeApi.fetchGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('새자료'), findsOneWidget, reason: '결과가 오면 항목이 하나 늘어난다');
  });

  testWidgets('폴더에 자료가 없으면 빈 상태 문구가 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: _FakeArchiveApi(),
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아직 링크 자료가 없어요'), findsOneWidget);
    // 빈 상태엔 더 이상 액션 버튼을 두지 않는다 — 아이콘+문구만(2026-08-08).
    expect(find.text('자료 추가하기'), findsNothing);
  });

  testWidgets('상단바 ＋로 텍스트를 등록하면 API가 호출되고 목록이 갱신된다', (tester) async {
    final fakeApi = _FakeArchiveApi();

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('archive-register-button')));
    await tester.pumpAndSettle();
    // ＋는 이제 바로 시트를 열지 않고 옵션창(링크/텍스트/이미지 추가)을 먼저 띄운다(2026-08-08).
    await tester.tap(find.text('텍스트 추가'));
    await tester.pumpAndSettle();

    expect(find.text('자료 등록'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '등록할 내용');
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();

    expect(fakeApi.createCalls, [
      {
        'folderId': 1,
        'url': null,
        'text': '등록할 내용',
        'memo': null,
        'imageUrl': null,
        'title': null,
      },
    ]);
    // 등록 성공 후 시트가 닫히고 목록이 다시 조회된다.
    expect(fakeApi.fetchCallCount, 2);
    // 🔴 등록 성공을 스낵바로 알리지 않는다(2026-08-06). 시트가 닫히는 것이 성공 신호이고,
    // 바로 위 재조회로 방금 넣은 자료가 목록에 나타난다 — 화면이 이미 하는 말이다.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('AppBar의 ＋ 버튼으로 링크를 입력하지 않고 등록하면 인라인 에러가 뜬다', (tester) async {
    final fakeApi = _FakeArchiveApi(items: [_item(id: 1, title: '기존 항목')]);

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('archive-register-button')));
    await tester.pumpAndSettle();
    // ＋는 이제 바로 시트를 열지 않고 옵션창(링크/텍스트/이미지 추가)을 먼저 띄운다(2026-08-08).
    await tester.tap(find.text('링크 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();

    expect(find.text('링크를 입력해 주세요'), findsOneWidget);
    expect(fakeApi.createCalls, isEmpty);
  });

  testWidgets('검색어를 입력하면 제목·태그에 일치하는 항목만 보인다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      items: [
        _item(id: 1, title: '스터디 노트', tags: ['공부']),
        _item(id: 2, title: '여행 후기', tags: ['여행']),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('archive-search-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '여행');
    await tester.pumpAndSettle();

    expect(find.text('스터디 노트'), findsNothing);
    expect(find.text('여행 후기'), findsOneWidget);
  });

  testWidgets('좋아요순으로 바꾸면 좋아요 많은 항목이 먼저 보인다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      items: [
        _item(
          id: 1,
          title: '적게 좋아요 받은 글',
          likeCount: 1,
          createdAt: DateTime(2026, 7, 20),
        ),
        _item(
          id: 2,
          title: '많이 좋아요 받은 글',
          likeCount: 5,
          createdAt: DateTime(2026, 7, 10),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 최신순 기본: 서버가 이미 created_at desc로 내려주므로 '적게 좋아요 받은 글'이 먼저.
    var firstTitle = tester
        .widgetList<Text>(find.textContaining('좋아요 받은 글'))
        .first
        .data;
    expect(firstTitle, '적게 좋아요 받은 글');

    await tester.tap(find.byKey(const ValueKey('archive-sort-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('좋아요순').last);
    await tester.pumpAndSettle();

    firstTitle = tester
        .widgetList<Text>(find.textContaining('좋아요 받은 글'))
        .first
        .data;
    expect(firstTitle, '많이 좋아요 받은 글');
  });

  testWidgets('핀 고정 항목은 최신순에서도 항상 최상단이다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      items: [
        _item(id: 1, title: '최신 비핀 글', createdAt: DateTime(2026, 7, 27)),
        _item(
          id: 2,
          title: '오래된 핀 글',
          pinned: true,
          createdAt: DateTime(2026, 7, 1),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstTitle = tester
        .widgetList<Text>(find.textContaining('글'))
        .first
        .data;
    expect(firstTitle, '오래된 핀 글');
  });

  testWidgets('좋아요순으로 바꿔도 핀 고정 항목이 최상단을 유지한다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      items: [
        _item(id: 1, title: '좋아요 많은 비핀 글', likeCount: 10),
        _item(id: 2, title: '좋아요 없는 핀 글', pinned: true, likeCount: 0),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('archive-sort-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('좋아요순').last);
    await tester.pumpAndSettle();

    final firstTitle = tester
        .widgetList<Text>(find.textContaining('글'))
        .first
        .data;
    expect(firstTitle, '좋아요 없는 핀 글');
  });

  testWidgets('로드 실패 시 에러 안내와 재시도 버튼이 보이고, 재시도하면 다시 호출한다', (tester) async {
    final fakeApi = _FakeArchiveApi(throwOnFetch: true);

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('항목 목록을 불러오지 못했어요'), findsOneWidget);
    expect(fakeApi.fetchCallCount, 1);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(fakeApi.fetchCallCount, 2);
  });

  testWidgets('진행 중인 방이 없으면 안내가 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: _FakeArchiveApi(),
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _NoActiveRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('진행 중인 방이 없어요'), findsOneWidget);
  });

  // ---------------------------------------------- 등록됐다는 신호 (2026-08-06 피드백)

  testWidgets('분석 중인 자료가 있으면 몇 건인지 알려준다', (tester) async {
    // 🔴 등록이 비동기가 되면서 [등록] 뒤 화면이 곧바로 조용해진다. 개별 항목 배지만으로는
    // 눈에 안 띄어 "공유가 된 건가?"가 됐다는 피드백에서 나온 안내다.
    final fakeApi = _FakeArchiveApi(
      items: [
        _item(id: 1, title: '분석 중인 것', crawlStatus: 'PENDING'),
        _item(id: 2, title: '또 분석 중', crawlStatus: 'PENDING'),
        _item(id: 3, title: '끝난 것'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('자료 2건을 분석하고 있어요'), findsOneWidget);
  });

  testWidgets('전부 끝났으면 안내를 띄우지 않는다', (tester) async {
    // 반대편 말뚝 — 늘 떠 있으면 안내가 아니라 잡음이 된다.
    final fakeApi = _FakeArchiveApi(items: [_item(id: 1, title: '끝난 것')]);

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('분석하고 있어요'), findsNothing);
  });

  testWidgets('실패한 자료는 분석 중으로 세지 않는다', (tester) async {
    // FAILED 를 세면 영영 안 사라지는 안내가 된다 — 그건 확정된 상태다.
    final fakeApi = _FakeArchiveApi(
      items: [_item(id: 1, title: '실패한 것', crawlStatus: 'FAILED')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('분석하고 있어요'), findsNothing);
  });

  // ---- 2026-08-08 리디자인: 라인 탭 · 핀 토글 · 검색 토글 ----

  Future<void> pumpScreen(WidgetTester tester, _FakeArchiveApi api) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveFolderItemsScreen(
          folderId: 1,
          api: api,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('이미지 탭으로 바꾸면(피드 비었을 때) 안내 빈 상태가 뜨고 링크 자료는 숨는다', (tester) async {
    final api = _FakeArchiveApi(items: [_item(id: 1, title: '링크 자료')]);
    await pumpScreen(tester, api);

    expect(find.text('링크 자료'), findsOneWidget);

    await tester.tap(find.text('이미지'));
    await tester.pumpAndSettle();

    // 2026-08-09 후속: 폴더 업로드 + 투두 첨부 두 소스 다 비었을 때 안내 문구.
    expect(find.textContaining('아직 이미지가 없어요'), findsOneWidget);
    expect(find.text('링크 자료'), findsNothing);
  });

  testWidgets('탭 순서는 링크·텍스트·이미지다', (tester) async {
    // 2026-08-08 요청: 기존 링크/이미지/텍스트 → 링크/텍스트/이미지로 순서 변경.
    final api = _FakeArchiveApi();
    await pumpScreen(tester, api);

    final linkX = tester.getTopLeft(find.text('링크')).dx;
    final textX = tester.getTopLeft(find.text('텍스트')).dx;
    final imageX = tester.getTopLeft(find.text('이미지')).dx;

    expect(linkX, lessThan(textX));
    expect(textX, lessThan(imageX));
  });

  testWidgets('이미지 탭에도 총 개수 헤더가 보인다', (tester) async {
    // 이미지 자료 데이터가 아직 없어 항상 0(2026-08-08 요청).
    final api = _FakeArchiveApi();
    await pumpScreen(tester, api);

    await tester.tap(find.text('이미지'));
    await tester.pumpAndSettle();

    expect(find.text('총 0개'), findsOneWidget);
  });

  testWidgets('＋를 누르면 링크/텍스트/이미지 추가 옵션창이 뜬다', (tester) async {
    // 2026-08-08: ＋가 더 이상 바로 시트를 열지 않고 옵션창을 먼저 띄운다.
    final api = _FakeArchiveApi();
    await pumpScreen(tester, api);

    await tester.tap(find.byKey(const ValueKey('archive-register-button')));
    await tester.pumpAndSettle();

    expect(find.text('링크 추가'), findsOneWidget);
    expect(find.text('텍스트 추가'), findsOneWidget);
    expect(find.text('이미지 추가'), findsOneWidget);
    expect(find.text('자료 등록'), findsNothing, reason: '시트는 아직 안 열렸다');
  });

  testWidgets('"이미지 추가"를 고르면 등록시트가 이미지 모드로 열린다', (tester) async {
    // 2026-08-09 후속 확정: 폴더 직접 업로드 이미지 자료(V26) — 더 이상 준비 중 안내가 아니다.
    final api = _FakeArchiveApi();
    await pumpScreen(tester, api);

    await tester.tap(find.byKey(const ValueKey('archive-register-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이미지 추가'));
    await tester.pumpAndSettle();

    expect(find.text('자료 등록'), findsOneWidget);
    expect(find.text('이미지 선택'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('카드 핀 아이콘을 탭하면 서버에 반영되고 고정 상태로 바뀐다', (tester) async {
    final api = _FakeArchiveApi(items: [_item(id: 7, title: '고정할 자료')]);
    await pumpScreen(tester, api);

    // 핀 SVG는 상태를 key로 구분한다(off↔on). 처음엔 미고정 — 라인 아이콘.
    expect(find.byKey(const ValueKey('archive-pin-off')), findsOneWidget);
    SvgAssetLoader assetOf(Key key) =>
        (tester
                .widget<SvgPicture>(
                  find.descendant(
                    of: find.byKey(key),
                    matching: find.byType(SvgPicture),
                  ),
                )
                .bytesLoader)
            as SvgAssetLoader;
    expect(
      assetOf(const ValueKey('archive-pin-off')).assetName,
      'assets/icons/majesticons_pin-line.svg',
    );

    await tester.tap(find.byKey(const ValueKey('archive-pin-off')));
    await tester.pumpAndSettle();

    expect(api.pinCalls, [(itemId: 7, pinned: true)]);
    // 고정되면 색만 바뀌는 게 아니라 채워진 다른 아이콘(primary_pin.svg)으로 바뀐다.
    expect(find.byKey(const ValueKey('archive-pin-on')), findsOneWidget);
    expect(
      assetOf(const ValueKey('archive-pin-on')).assetName,
      'assets/icons/primary_pin.svg',
    );
  });

  testWidgets('분석 실패(FAILED)로 제목이 원본 URL 그대로면 안내 문구로 대체한다', (tester) async {
    const url = 'https://example.com/very/long/unresolved/path';
    final api = _FakeArchiveApi(
      items: [_item(id: 1, title: url, url: url, crawlStatus: 'FAILED')],
    );
    await pumpScreen(tester, api);

    expect(find.text('제목을 가져오지 못했어요'), findsOneWidget);
    expect(find.text(url), findsNothing);
    // 도메인 줄은 그대로 유지된다(중복 없이 아래에만 출처가 남는다).
    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('255자 넘는 URL이 title에서 잘려 url과 완전히 같지 않아도 안내 문구로 대체한다', (
    tester,
  ) async {
    // 서버는 title을 255자에서 자르지만 url은 2048자까지 허용한다(ArchiveTextLimits) — 그래서
    // 실제로는 title == url 완전 일치가 아니라 title이 잘린 URL 접두어로 남는 게 흔하다.
    final longUrl = 'https://example.com/${'a' * 400}'; // 255자보다 훨씬 긴 URL.
    final truncatedTitle = longUrl.substring(0, 255);
    final api = _FakeArchiveApi(
      items: [
        _item(
          id: 1,
          title: truncatedTitle,
          url: longUrl,
          crawlStatus: 'FAILED',
        ),
      ],
    );
    await pumpScreen(tester, api);

    expect(find.text('제목을 가져오지 못했어요'), findsOneWidget);
    expect(find.text(truncatedTitle), findsNothing);
  });

  testWidgets('분석 중(PENDING)으로 제목이 원본 URL이어도 그대로 보여준다', (tester) async {
    const url = 'https://example.com/pending-path';
    final api = _FakeArchiveApi(
      items: [_item(id: 1, title: url, url: url, crawlStatus: 'PENDING')],
    );
    await pumpScreen(tester, api);

    expect(find.text(url), findsOneWidget);
    expect(find.text('제목을 가져오지 못했어요'), findsNothing);
  });

  testWidgets('url 없는(메모형) 자료는 텍스트 탭에만 보이고 링크 탭에는 없다', (tester) async {
    final api = _FakeArchiveApi(
      items: [
        _item(id: 1, title: '링크 자료', url: 'https://velog.io/@me/x'),
        _item(id: 2, title: '메모 자료', url: null),
      ],
    );
    await pumpScreen(tester, api);

    // 기본 링크 탭: 링크 자료만.
    expect(find.text('링크 자료'), findsOneWidget);
    expect(find.text('메모 자료'), findsNothing);

    await tester.tap(find.text('텍스트').last);
    await tester.pumpAndSettle();

    expect(find.text('메모 자료'), findsOneWidget);
    expect(find.text('링크 자료'), findsNothing);
  });

  testWidgets('상단바 검색 아이콘을 누르면 검색창이 나타난다', (tester) async {
    final api = _FakeArchiveApi(items: [_item(id: 1, title: '자료')]);
    await pumpScreen(tester, api);

    expect(find.byType(TextField), findsNothing); // 처음엔 검색창 없음
    await tester.tap(find.byKey(const ValueKey('archive-search-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('검색이 열리면 폴더명·＋ 아이콘이 검색바로 완전히 대체되고, 돋보기를 다시 누르면 닫힌다', (
    tester,
  ) async {
    final api = _FakeArchiveApi(
      folderName: '스터디 자료',
      items: [_item(id: 1, title: '자료')],
    );
    await pumpScreen(tester, api);

    expect(find.text('스터디 자료'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('archive-register-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('archive-search-toggle')));
    await tester.pumpAndSettle();

    // 상단바 자체가 검색바로 바뀐다 — 폴더명·＋ 아이콘은 사라진다.
    expect(find.text('스터디 자료'), findsNothing);
    expect(find.byKey(const ValueKey('archive-register-button')), findsNothing);
    expect(find.text('검색할 내용을 입력해주세요.'), findsOneWidget);

    // 돋보기(이제 검색바 안쪽 suffix)를 다시 누르면 닫히고 원래 상단바로 돌아온다.
    await tester.tap(find.byKey(const ValueKey('archive-search-toggle')));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('스터디 자료'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('archive-register-button')),
      findsOneWidget,
    );
  });

  testWidgets('검색바 밖(본문)을 탭하면 검색이 닫힌다', (tester) async {
    final api = _FakeArchiveApi(
      folderName: '스터디 자료',
      items: [_item(id: 1, title: '자료')],
    );
    await pumpScreen(tester, api);

    await tester.tap(find.byKey(const ValueKey('archive-search-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // 본문(리스트 헤더 "총 N개")을 탭한다 — 검색바 자체가 아닌 곳.
    await tester.tap(find.text('총 1개'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('스터디 자료'), findsOneWidget);
  });

  group('이미지 탭(2026-08-09, 투두 이미지 피드)', () {
    ArchiveTodoImage image({
      required int id,
      required String title,
      bool pinned = false,
      ArchiveItemCreator? assignee,
    }) => ArchiveTodoImage(
      id: id,
      imageUrl: 'https://example.com/img-$id.jpg',
      todoId: id * 10,
      todoTitle: title,
      assignee: assignee,
      pinned: pinned,
      createdAt: DateTime(2026, 8, 9),
    );

    Future<void> openImageTab(
      WidgetTester tester,
      _FakeArchiveApi fakeApi,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ArchiveFolderItemsScreen(
            folderId: 1,
            api: fakeApi,
            authService: _FakeAuthService(),
            roomSession: RoomSession(roomApi: _FakeRoomApi()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('이미지'));
      await tester.pumpAndSettle();
    }

    testWidgets('피드가 비어 있으면(서버 미구현 포함) 안내 빈 상태가 보인다', (tester) async {
      final fakeApi = _FakeArchiveApi(items: []);
      await openImageTab(tester, fakeApi);

      expect(find.text('총 0개'), findsWidgets);
      expect(find.textContaining('아직 이미지가 없어요'), findsOneWidget);
    });

    testWidgets('2열 그리드에 투두 제목·핀·담당자 아바타가 렌더된다', (tester) async {
      final fakeApi = _FakeArchiveApi(items: [])
        ..images = [
          image(
            id: 1,
            title: '관련 투두 제목',
            pinned: true,
            assignee: ArchiveItemCreator(userId: 'u1', nickname: '준호'),
          ),
          image(id: 2, title: '두 번째 투두'),
        ];
      await openImageTab(tester, fakeApi);

      expect(find.text('총 2개'), findsOneWidget);
      expect(find.text('관련 투두 제목'), findsOneWidget);
      expect(find.text('두 번째 투두'), findsOneWidget);
      // 핀: 고정 1개(on) + 미고정 1개(off).
      expect(find.byKey(const ValueKey('archive-pin-on')), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-pin-off')), findsOneWidget);
      // 담당자 아바타 이니셜(사진 로드 전 폴백).
      expect(find.text('준'), findsOneWidget);
    });

    testWidgets('이미지 핀을 탭하면 서버에 반영된다', (tester) async {
      final fakeApi = _FakeArchiveApi(items: [])
        ..images = [image(id: 1, title: '투두')];
      await openImageTab(tester, fakeApi);

      await tester.tap(find.byKey(const ValueKey('archive-pin-off')));
      await tester.pumpAndSettle();

      expect(fakeApi.imagePinCalls, [(imageId: 1, pinned: true)]);
      expect(find.byKey(const ValueKey('archive-pin-on')), findsOneWidget);
    });

    testWidgets('투두 제목이 잘리면 탭해서 전체를 펼칠 수 있다', (tester) async {
      const longTitle = '아주 길어서 한 줄을 넘겨 말줄임되는 관련 투두 제목 예시입니다';
      final fakeApi = _FakeArchiveApi(items: [])
        ..images = [image(id: 1, title: longTitle)];
      await openImageTab(tester, fakeApi);

      Text titleWidget() => tester.widget<Text>(find.text(longTitle));
      expect(titleWidget().maxLines, 1);

      await tester.tap(find.text(longTitle));
      await tester.pump();
      expect(titleWidget().maxLines, isNull);
    });
  });

  group('폴더 직접 업로드 이미지 자료(V26, 2026-08-09 후속 확정)', () {
    testWidgets('링크·텍스트 탭에 새지 않고 이미지 탭 "이 폴더에 올린 사진" 섹션에만 보인다', (tester) async {
      final api = _FakeArchiveApi(
        items: [
          _item(id: 1, title: '링크 자료'),
          _item(id: 2, title: '텍스트 자료', url: null),
          _item(
            id: 3,
            title: '업로드한 사진',
            url: null,
            imageUrl: 'https://example.com/photo.jpg',
          ),
        ],
      );
      await pumpScreen(tester, api);

      // 링크 탭(기본): 이미지 자료가 안 보인다.
      expect(find.text('링크 자료'), findsOneWidget);
      expect(find.text('업로드한 사진'), findsNothing);

      await tester.tap(find.text('텍스트'));
      await tester.pumpAndSettle();
      // 텍스트 탭: 이미지 자료가 새지 않는다(url==null이라 예전 필터로는 걸러지지 않았다).
      expect(find.text('텍스트 자료'), findsOneWidget);
      expect(find.text('업로드한 사진'), findsNothing);

      await tester.tap(find.text('이미지'));
      await tester.pumpAndSettle();
      expect(find.text('이 폴더에 올린 사진'), findsOneWidget);
      expect(find.text('업로드한 사진'), findsOneWidget);
      expect(find.text('투두에 첨부된 사진'), findsNothing); // 투두 이미지가 없으면 섹션 자체가 없다.
      expect(find.text('총 1개'), findsOneWidget);
    });

    testWidgets('폴더 업로드 사진과 투두 첨부 사진이 있으면 두 섹션이 모두 보인다', (tester) async {
      final api =
          _FakeArchiveApi(
              items: [
                _item(
                  id: 3,
                  title: '업로드한 사진',
                  url: null,
                  imageUrl: 'https://example.com/photo.jpg',
                ),
              ],
            )
            ..images = [
              ArchiveTodoImage(
                id: 10,
                imageUrl: 'https://example.com/todo.jpg',
                todoId: 100,
                todoTitle: '투두 사진',
                assignee: null,
                pinned: false,
                createdAt: DateTime(2026, 8, 9),
              ),
            ];
      await pumpScreen(tester, api);

      await tester.tap(find.text('이미지'));
      await tester.pumpAndSettle();

      expect(find.text('이 폴더에 올린 사진'), findsOneWidget);
      expect(find.text('업로드한 사진'), findsOneWidget);
      expect(find.text('투두에 첨부된 사진'), findsOneWidget);
      expect(find.text('총 2개'), findsOneWidget);
      // 두 섹션이 쌓여 두 번째 섹션이 뷰포트 캐시 범위 밖일 수 있다 — 렌더 트리 존재만 확인.
      expect(find.text('투두 사진', skipOffstage: false), findsOneWidget);
    });

    testWidgets('폴더 업로드 사진의 핀을 탭하면 일반 자료 핀 API로 반영된다', (tester) async {
      final api = _FakeArchiveApi(
        items: [
          _item(
            id: 5,
            title: '핀 테스트 사진',
            url: null,
            imageUrl: 'https://example.com/pin.jpg',
          ),
        ],
      );
      await pumpScreen(tester, api);

      await tester.tap(find.text('이미지'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('archive-pin-off')));
      await tester.pumpAndSettle();

      expect(api.pinCalls, [(itemId: 5, pinned: true)]);
      expect(find.byKey(const ValueKey('archive-pin-on')), findsOneWidget);
    });
  });
}
