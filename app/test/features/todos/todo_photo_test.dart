import 'package:app/features/todos/todo_photo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 사진 크게 보기(2026-08-25 #65) — 여는 것은 각 화면 테스트가 보고, 여기서는
/// **닫는 경로와 안 여는 조건**을 본다. 새 화면의 핵심 상호작용인데 여는 검증만
/// 있으면 나중에 레이아웃을 바꿀 때 아무도 못 잡는다(2026-08-25 리뷰 지적).
///
/// 네트워크 이미지는 테스트 스텁 HttpClient가 400을 주므로 폴백이 그려진다 —
/// 아카이브 테스트와 같은 전제다.
void main() {
  /// 뷰어를 여는 버튼 하나짜리 화면. 실제 호출부(썸네일·미리보기)와 같은 진입점
  /// (`showTodoPhoto`)을 쓴다.
  Future<void> pumpOpener(WidgetTester tester, {String? url}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTodoPhoto(context, url),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('닫기 버튼을 누르면 닫힌다', (tester) async {
    await pumpOpener(tester, url: 'https://storage.test/photo.jpg');
    await open(tester);
    expect(find.byType(TodoPhotoViewer), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo-photo-close')));
    await tester.pumpAndSettle();

    expect(find.byType(TodoPhotoViewer), findsNothing);
    expect(find.text('열기'), findsOneWidget, reason: '원래 화면으로 돌아온다');
  });

  testWidgets('사진을 탭해도 닫힌다', (tester) async {
    await pumpOpener(tester, url: 'https://storage.test/photo.jpg');
    await open(tester);

    // 화면 한가운데 = 사진 위(또는 폴백 위). specs/design.md "사진 크게 보기".
    await tester.tapAt(tester.getCenter(find.byType(TodoPhotoViewer)));
    await tester.pumpAndSettle();

    expect(find.byType(TodoPhotoViewer), findsNothing);
  });

  testWidgets('시스템 뒤로 가기로도 닫힌다', (tester) async {
    await pumpOpener(tester, url: 'https://storage.test/photo.jpg');
    await open(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(TodoPhotoViewer), findsNothing);
  });

  testWidgets('사진이 없으면 아예 열리지 않는다', (tester) async {
    await pumpOpener(tester, url: null);
    await open(tester);

    expect(find.byType(TodoPhotoViewer), findsNothing);
  });

  testWidgets('빈 문자열도 사진 없음으로 본다', (tester) async {
    await pumpOpener(tester, url: '');
    await open(tester);

    expect(find.byType(TodoPhotoViewer), findsNothing);
  });

  testWidgets('확대·이동 영역이 사진 상자가 아니라 화면 전체다', (tester) async {
    // 🔴 회귀 방지 — InteractiveViewer를 Center 안쪽에 두면 영역이 사진 크기로 줄어서
    // 검은 여백에서 시작한 제스처가 죽고 확대한 사진이 잘린다(2026-08-25 리뷰).
    await pumpOpener(tester, url: 'https://storage.test/photo.jpg');
    await open(tester);

    final viewer = tester.getSize(find.byType(InteractiveViewer));
    final screen = tester.getSize(find.byType(TodoPhotoViewer));

    expect(viewer, screen);
  });
}
