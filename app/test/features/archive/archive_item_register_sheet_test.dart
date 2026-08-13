import 'dart:typed_data';

import 'package:app/features/archive/archive_api.dart';
import 'package:app/features/archive/archive_item_register_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// 폴더 직접 업로드 이미지 자료(V26, 2026-08-09 후속 확정) — [ArchiveItemRegisterSheet]에 이미지
/// 모드가 붙으면서 그 커버리지를 이 파일에 둔다. `todo_form_sheet_test.dart`의 이미지 테스트와
/// 같은 패턴(가짜 [imagePicker]/`uploadImage` 주입).
void main() {
  ({
    int folderId,
    String? url,
    String? text,
    String? memo,
    String? imageUrl,
    String? title,
  })?
  submitted;
  List<int>? uploadedBytes;

  Future<void> pumpSheet(
    WidgetTester tester, {
    ArchiveRegisterMode initialMode = ArchiveRegisterMode.link,
    Future<XFile?> Function()? imagePicker,
    Future<String> Function(List<int> bytes)? uploadImage,
  }) async {
    submitted = null;
    uploadedBytes = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArchiveItemRegisterSheet(
            folders: [ArchiveFolder(id: 1, name: '기본', itemCount: 0)],
            initialFolderId: 1,
            initialMode: initialMode,
            imagePicker: imagePicker,
            uploadImage:
                uploadImage ??
                (bytes) async {
                  uploadedBytes = bytes;
                  return 'https://storage.test/archive-image';
                },
            onSubmit:
                ({required folderId, url, text, memo, imageUrl, title}) async {
                  submitted = (
                    folderId: folderId,
                    url: url,
                    text: text,
                    memo: memo,
                    imageUrl: imageUrl,
                    title: title,
                  );
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('이미지 모드 — 사진을 선택하면 선택 상태로 바뀐다', (tester) async {
    await pumpSheet(
      tester,
      initialMode: ArchiveRegisterMode.image,
      imagePicker: () async => XFile('fake.jpg'),
    );

    expect(find.text('이미지 선택'), findsOneWidget);
    await tester.tap(find.text('이미지 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리'));
    await tester.pumpAndSettle();

    expect(find.text('이미지 1장 선택됨'), findsOneWidget);
  });

  testWidgets('이미지를 고르고 등록하면 업로드 후 그 URL과 제목으로 등록된다', (tester) async {
    await pumpSheet(
      tester,
      initialMode: ArchiveRegisterMode.image,
      imagePicker: () async =>
          XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'fake.jpg'),
    );

    await tester.tap(find.text('이미지 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '여행 사진');
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();

    expect(uploadedBytes, [1, 2, 3]);
    expect(submitted?.imageUrl, 'https://storage.test/archive-image');
    expect(submitted?.title, '여행 사진');
    expect(submitted?.url, null);
    expect(submitted?.text, null);
  });

  testWidgets('이미지 모드에서 사진 없이 등록하면 인라인 에러가 뜬다', (tester) async {
    await pumpSheet(tester, initialMode: ArchiveRegisterMode.image);

    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();

    expect(find.text('사진을 선택해 주세요'), findsOneWidget);
    expect(submitted, isNull);
  });

  testWidgets('제목을 비우고 등록하면 title이 null로 넘어간다(서버가 "사진"으로 채운다)', (tester) async {
    await pumpSheet(
      tester,
      initialMode: ArchiveRegisterMode.image,
      imagePicker: () async =>
          XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'fake.jpg'),
    );

    await tester.tap(find.text('이미지 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();

    expect(submitted?.title, null);
    expect(submitted?.imageUrl, 'https://storage.test/archive-image');
  });
}
