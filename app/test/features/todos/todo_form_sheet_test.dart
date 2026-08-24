import 'dart:typed_data';

import 'package:app/design/theme.dart';
import 'package:app/features/todos/todo_form_sheet.dart';
import 'package:app/features/todos/todo_photo.dart';
import 'package:app/features/todos/todos_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// 2026-08-08 리디자인: 카테고리·담당자·마감일이 인라인 칩에서 옵션 피커로
/// 바뀌었고 중요 토글·이미지 추가가 UI로 붙었다. 이 파일이 그 커버리지다.
void main() {
  ({
    String title,
    String? detail,
    int? categoryId,
    List<String> assigneeUserIds,
    DateTime? dueDate,
    String? imageUrl,
  })?
  submitted;

  /// uploadImage 호출 시 넘어온 바이트 — 실제로 업로드가 트리거됐는지 확인용.
  List<int>? uploadedBytes;

  Future<void> pumpSheet(
    WidgetTester tester, {
    DateTime? today,
    TodoItem? initial,
    List<Category> categories = const [],
    List<MemberBrief> members = const [],
    Future<XFile?> Function()? imagePicker,
    Future<String> Function(List<int> bytes)? uploadImage,
  }) async {
    submitted = null;
    uploadedBytes = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TodoFormSheet(
            categories: categories,
            members: members,
            initial: initial,
            today: today ?? DateTime(2026, 8, 3),
            imagePicker: imagePicker,
            uploadImage:
                uploadImage ??
                (bytes) async {
                  uploadedBytes = bytes;
                  return 'https://storage.test/todo-image';
                },
            onSubmit:
                ({
                  required title,
                  detail,
                  categoryId,
                  required assigneeUserIds,
                  dueDate,
                  imageUrl,
                }) async {
                  submitted = (
                    title: title,
                    detail: detail,
                    categoryId: categoryId,
                    assigneeUserIds: assigneeUserIds,
                    dueDate: dueDate,
                    imageUrl: imageUrl,
                  );
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterTitle(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('todo-form-title')), text);
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('todo-form-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('제목이 비어 있으면 저장하지 않고 안내를 보인다', (tester) async {
    await pumpSheet(tester);

    await tapSubmit(tester);

    expect(submitted, isNull);
    expect(find.text('제목을 입력해 주세요'), findsOneWidget);
  });

  testWidgets('제목을 입력하고 저장하면 onSubmit이 호출된다', (tester) async {
    await pumpSheet(tester);

    await enterTitle(tester, '장보기');
    await tapSubmit(tester);

    expect(submitted?.title, '장보기');
  });

  testWidgets('카테고리 행을 탭해 피커에서 고르면 값과 저장에 반영된다', (tester) async {
    await pumpSheet(
      tester,
      categories: [
        Category(id: 7, name: '개발'),
        Category(id: 8, name: '디자인'),
      ],
    );
    await enterTitle(tester, '제목');

    // 기본은 기타.
    expect(find.text('기타'), findsOneWidget);
    await tester.tap(find.text('카테고리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('개발')); // 피커에서 선택
    await tester.pumpAndSettle();

    // 행 값이 '개발'로 바뀌었다.
    expect(find.text('개발'), findsOneWidget);
    await tapSubmit(tester);
    expect(submitted?.categoryId, 7);
  });

  testWidgets('마감일 행을 탭해 "오늘"을 고르면 저장에 반영된다', (tester) async {
    final today = DateTime(2026, 8, 3);
    await pumpSheet(tester, today: today);
    await enterTitle(tester, '제목');

    await tester.tap(find.text('마감일'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오늘'));
    await tester.pumpAndSettle();

    await tapSubmit(tester);
    expect(submitted?.dueDate, today);
  });

  testWidgets('마감일 피커의 "직접 선택"은 날짜 다이얼로그를 연다', (tester) async {
    await pumpSheet(tester, today: DateTime(2026, 8, 3));

    await tester.tap(find.text('마감일'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('직접 선택'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('담당자 행을 탭해 고르면 저장에 반영된다', (tester) async {
    await pumpSheet(
      tester,
      members: [
        MemberBrief(userId: 'u1', nickname: '준'),
        MemberBrief(userId: 'u2', nickname: '민'),
      ],
    );
    await enterTitle(tester, '제목');

    await tester.tap(find.text('담당자'));
    await tester.pumpAndSettle();
    // 피커 행엔 아바타 이니셜과 이름이 둘 다 '준' — 행 아무데나 탭하면 InkWell로 전달된다.
    await tester.tap(find.text('준').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    await tapSubmit(tester);
    expect(submitted?.assigneeUserIds, ['u1']);
  });

  testWidgets('중요 토글이 있고 켤 수 있다(UI 전용)', (tester) async {
    await pumpSheet(tester);

    expect(find.text('중요'), findsOneWidget);
    final sw = find.byType(Switch);
    expect(sw, findsOneWidget);
    expect(tester.widget<Switch>(sw).value, isFalse);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(sw).value, isTrue);
  });

  testWidgets('이미지 추가 박스 — 선택하면 첨부 상태로 바뀐다', (tester) async {
    await pumpSheet(tester, imagePicker: () async => XFile('fake.jpg'));

    expect(find.text('이미지 추가'), findsOneWidget);
    await tester.ensureVisible(find.text('이미지 추가')); // 스크롤 하단이라 보이게
    await tester.pumpAndSettle();
    await tester.tap(find.text('이미지 추가'));
    await tester.pumpAndSettle();
    // 옵션창에서 갤러리 선택.
    await tester.tap(find.text('갤러리'));
    await tester.pumpAndSettle();
    expect(find.text('이미지 1장 첨부됨'), findsOneWidget);
  });

  testWidgets('이미지를 고르고 저장하면 업로드 후 그 URL로 저장된다(2026-08-09)', (tester) async {
    // readAsBytes()가 실제 디스크를 안 타도록 fromData(메모리 백)로 만든다.
    await pumpSheet(
      tester,
      imagePicker: () async =>
          XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'fake.jpg'),
    );

    await tester.ensureVisible(find.text('이미지 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이미지 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리'));
    await tester.pumpAndSettle();

    await enterTitle(tester, '장보기');
    await tapSubmit(tester);

    expect(uploadedBytes, isNotNull);
    expect(submitted?.imageUrl, 'https://storage.test/todo-image');
  });

  testWidgets('기존 첨부 사진이 미리보기로 보인다', (tester) async {
    // 2026-08-24 #65 — 폼(=상세 S-18)에 미리보기 카드(전폭×180). 스텁 HttpClient 400
    // → errorBuilder 폴백 렌더지만 위젯 존재 검증으로 충분(아카이브 테스트와 같은 전제).
    await pumpSheet(
      tester,
      initial: TodoItem(
        id: 1,
        title: '기존 제목',
        completed: false,
        assignees: const [],
        imageUrl: 'https://storage.test/existing.jpg',
      ),
    );

    expect(find.byKey(const ValueKey('todo-photo-preview')), findsOneWidget);
    // 높이는 specs/design.md 확정값(전폭×180) — 스펙 회귀 방지.
    expect(
      tester.getSize(find.byKey(const ValueKey('todo-photo-preview'))).height,
      180,
    );
  });

  testWidgets('미리보기를 누르면 사진을 크게 볼 수 있다', (tester) async {
    // 2026-08-25 #65 — 목록 썸네일과 같은 동작.
    await pumpSheet(
      tester,
      initial: TodoItem(
        id: 1,
        title: '기존 제목',
        completed: false,
        assignees: const [],
        imageUrl: 'https://storage.test/existing.jpg',
      ),
    );

    // 미리보기는 스크롤 하단이라 보이게 올린 뒤 탭한다(이미지 추가 박스 테스트와 같은 관례).
    await tester.ensureVisible(
      find.byKey(const ValueKey('todo-photo-preview')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('todo-photo-preview')));
    await tester.pumpAndSettle();

    expect(find.byType(TodoPhotoViewer), findsOneWidget);
  });

  testWidgets('이미지를 새로 고르면 미리보기가 뜬다', (tester) async {
    // 2026-08-24 #65 — 새로 고른 로컬 파일(XFile) 분기. fromData는 path가 빈 문자열이라
    // Image.file이 실패하고 errorBuilder 폴백이 그려진다 — 존재 검증으로 충분.
    await pumpSheet(
      tester,
      imagePicker: () async =>
          XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'fake.jpg'),
    );

    expect(find.byKey(const ValueKey('todo-photo-preview')), findsNothing);

    await tester.ensureVisible(find.text('이미지 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이미지 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo-photo-preview')), findsOneWidget);
  });

  testWidgets('수정 모드에서 이미지를 새로 고르지 않으면 기존 imageUrl을 그대로 유지한다', (tester) async {
    await pumpSheet(
      tester,
      initial: TodoItem(
        id: 1,
        title: '기존 제목',
        completed: false,
        assignees: const [],
        imageUrl: 'https://storage.test/existing.jpg',
      ),
    );

    // 이미 첨부된 상태로 보여야 한다(수정 모드 진입 시 기존 이미지 표시).
    expect(find.text('이미지 1장 첨부됨'), findsOneWidget);

    await tapSubmit(tester);

    expect(uploadedBytes, isNull); // 새로 업로드하지 않았다.
    expect(submitted?.imageUrl, 'https://storage.test/existing.jpg');
  });

  testWidgets('수정 모드: 제목 프리필 + 저장 버튼, 삭제 버튼 없음', (tester) async {
    await pumpSheet(
      tester,
      initial: TodoItem(
        id: 1,
        title: '기존 제목',
        completed: false,
        assignees: const [],
      ),
    );

    expect(find.text('기존 제목'), findsOneWidget);
    expect(find.text('저장'), findsOneWidget);
    expect(find.text('삭제'), findsNothing);
  });

  testWidgets('담당자 피커를 완료 없이 닫으면 반영되지 않는다', (tester) async {
    await pumpSheet(
      tester,
      members: [MemberBrief(userId: 'u1', nickname: '준')],
    );
    await enterTitle(tester, '제목');

    await tester.tap(find.text('담당자'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('준').first); // 선택은 했지만
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // 완료 없이 바깥 탭으로 닫기
    await tester.pumpAndSettle();

    await tapSubmit(tester);
    expect(submitted?.assigneeUserIds, isEmpty);
  });

  testWidgets('금요일에는 마감일 피커에 "이번 주말"이 없다', (tester) async {
    await pumpSheet(tester, today: DateTime(2026, 8, 7)); // 금요일

    await tester.tap(find.text('마감일'));
    await tester.pumpAndSettle();
    expect(find.text('이번 주말'), findsNothing);
    expect(find.text('내일'), findsOneWidget);
  });
}
