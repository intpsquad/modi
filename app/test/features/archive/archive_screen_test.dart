import 'package:app/design/option_menu.dart';
import 'package:app/design/theme.dart';
import 'package:app/features/archive/archive_api.dart';
import 'package:app/features/archive/archive_screen.dart';
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
}

class _FakeArchiveApi extends ArchiveApi {
  _FakeArchiveApi({List<ArchiveFolder>? folders, this.throwOnFetch = false})
    : folders = folders ?? [];

  List<ArchiveFolder> folders;
  bool throwOnFetch;
  int fetchCallCount = 0;
  final List<String> createNames = [];
  final List<int> deleteCalls = [];

  @override
  Future<List<ArchiveFolder>> fetchFolders(String idToken, int roomId) async {
    fetchCallCount++;
    if (throwOnFetch) throw StateError('network');
    return folders;
  }

  @override
  Future<ArchiveFolder> createFolder(
    String idToken,
    int roomId,
    String name,
  ) async {
    createNames.add(name);
    final created = ArchiveFolder(
      id: folders.length + 100,
      name: name,
      itemCount: 0,
    );
    folders = [...folders, created];
    return created;
  }

  @override
  Future<ArchiveFolder> renameFolder(
    String idToken,
    int roomId,
    int folderId,
    String name,
  ) async {
    final existing = folders.firstWhere((f) => f.id == folderId);
    final updated = ArchiveFolder(
      id: folderId,
      name: name,
      itemCount: existing.itemCount,
    );
    folders = [
      for (final f in folders)
        if (f.id == folderId) updated else f,
    ];
    return updated;
  }

  @override
  Future<void> deleteFolder(String idToken, int roomId, int folderId) async {
    deleteCalls.add(folderId);
    folders = folders.where((f) => f.id != folderId).toList();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('폴더 목록과 항목 개수가 렌더된다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      folders: [ArchiveFolder(id: 1, name: '스터디 자료', itemCount: 3)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('스터디 자료'), findsOneWidget);
    expect(find.text('저장된 항목 3개'), findsOneWidget);
  });

  testWidgets('폴더가 없으면 빈 상태와 CTA가 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveScreen(
          api: _FakeArchiveApi(),
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아직 폴더가 없어요'), findsOneWidget);
    expect(find.text('폴더 추가하기'), findsOneWidget);
  });

  testWidgets('폴더를 추가하면 목록에 반영된다', (tester) async {
    final fakeApi = _FakeArchiveApi();

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 상단 + 버튼을 누르면 바로 폴더 추가 다이얼로그가 뜬다(검색·⋯ 메뉴 제거).
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '새 폴더');
    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(fakeApi.createNames, ['새 폴더']);
    expect(find.text('새 폴더'), findsOneWidget);
  });

  testWidgets('폴더 이름을 수정하면 목록에 반영된다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      folders: [ArchiveFolder(id: 1, name: '원래 이름', itemCount: 0)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이름 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '바뀐 이름');
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    expect(find.text('바뀐 이름'), findsOneWidget);
    expect(find.text('원래 이름'), findsNothing);
  });

  testWidgets('폴더 ⋮ 를 누르면 바텀시트가 아니라 옵션창이 버튼 아래에 뜬다', (tester) async {
    // 2026-08-05 요청: "폴더 옵션 누르면 공통 컴포넌트-옵션창에서 삭제/수정 노출".
    final fakeApi = _FakeArchiveApi(
      folders: [ArchiveFolder(id: 1, name: '폴더', itemCount: 0)],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ArchiveScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final trigger = tester.getRect(find.byIcon(Icons.more_vert));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.byType(OptionMenuCard<String>), findsOneWidget);
    expect(find.byType(ListTile), findsNothing, reason: '바텀시트 목록은 폐기');
    expect(find.text('이름 수정'), findsOneWidget);
    expect(find.text('삭제'), findsOneWidget);

    final card = tester.getRect(find.byType(OptionMenuCard<String>));
    expect(card.top, greaterThanOrEqualTo(trigger.bottom - 1), reason: '버튼 아래');
  });

  testWidgets('삭제 확인 모달을 거쳐야 폴더가 삭제된다', (tester) async {
    final fakeApi = _FakeArchiveApi(
      folders: [ArchiveFolder(id: 1, name: '삭제될 폴더', itemCount: 0)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(fakeApi.deleteCalls, isEmpty);
    expect(find.text('폴더를 삭제할까요?'), findsOneWidget);
    expect(find.text('폴더 안의 자료도 모두 함께 삭제돼요. 되돌릴 수 없어요.'), findsOneWidget);

    await tester.tap(find.text('삭제').last);
    await tester.pumpAndSettle();

    expect(fakeApi.deleteCalls, [1]);
    expect(find.text('삭제될 폴더'), findsNothing);
  });

  testWidgets('로드 실패 시 에러 안내와 재시도 버튼이 보이고, 재시도하면 다시 호출한다', (tester) async {
    final fakeApi = _FakeArchiveApi(throwOnFetch: true);

    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveScreen(
          api: fakeApi,
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _FakeRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('폴더 목록을 불러오지 못했어요'), findsOneWidget);
    expect(fakeApi.fetchCallCount, 1);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(fakeApi.fetchCallCount, 2);
  });

  testWidgets('진행 중인 방이 없으면 안내가 보인다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ArchiveScreen(
          api: _FakeArchiveApi(),
          authService: _FakeAuthService(),
          roomSession: RoomSession(roomApi: _NoActiveRoomApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('진행 중인 방이 없어요'), findsOneWidget);
  });
}
