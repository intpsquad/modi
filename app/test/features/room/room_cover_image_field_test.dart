import 'dart:typed_data';

import 'package:app/features/room/room_cover_image_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

XFile _fakeFile() =>
    XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'x.jpg');

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('빈 상태는 "대표 이미지 추가"를 보여준다', (tester) async {
    await tester.pumpWidget(
      _host(
        RoomCoverImageField(
          uploadImage: (file) async => 'https://cdn/x.jpg',
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('대표 이미지 추가'), findsOneWidget);
  });

  testWidgets('탭→갤러리 선택→업로드 성공 시 onChanged가 URL로 호출되고 미리보기가 뜬다', (
    tester,
  ) async {
    String? changed;
    ImageSource? pickedSource;

    await tester.pumpWidget(
      _host(
        RoomCoverImageField(
          pickImage: (source) async {
            pickedSource = source;
            return _fakeFile();
          },
          uploadImage: (file) async => 'https://cdn/uploaded.jpg',
          onChanged: (url) => changed = url,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('cover-image-box')));
    await tester.pumpAndSettle();
    // 소스 선택 시트
    expect(find.text('갤러리에서 선택'), findsOneWidget);
    expect(find.text('카메라로 촬영'), findsOneWidget);

    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();

    expect(pickedSource, ImageSource.gallery);
    expect(changed, 'https://cdn/uploaded.jpg');
    // 업로드 완료 상태: 삭제 버튼이 뜨고 빈 상태 문구는 사라진다.
    expect(find.byKey(const ValueKey('cover-image-remove')), findsOneWidget);
    expect(find.text('대표 이미지 추가'), findsNothing);

    // 삭제하면 다시 빈 상태 + onChanged(null).
    await tester.tap(find.byKey(const ValueKey('cover-image-remove')));
    await tester.pumpAndSettle();
    expect(changed, isNull);
    expect(find.text('대표 이미지 추가'), findsOneWidget);
  });

  testWidgets('업로드 실패 시 인라인 에러를 보여준다', (tester) async {
    await tester.pumpWidget(
      _host(
        RoomCoverImageField(
          pickImage: (source) async => _fakeFile(),
          uploadImage: (file) async => throw StateError('boom'),
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('cover-image-box')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('갤러리에서 선택'));
    await tester.pumpAndSettle();

    expect(find.textContaining('업로드에 실패'), findsOneWidget);
  });

  testWidgets('enableCamera=false면 시트 없이 바로 갤러리로 픽한다', (tester) async {
    ImageSource? pickedSource;
    await tester.pumpWidget(
      _host(
        RoomCoverImageField(
          enableCamera: false,
          pickImage: (source) async {
            pickedSource = source;
            return null; // 취소
          },
          uploadImage: (file) async => 'x',
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('cover-image-box')));
    await tester.pumpAndSettle();

    expect(find.text('갤러리에서 선택'), findsNothing); // 시트 안 뜸
    expect(pickedSource, ImageSource.gallery);
  });
}
