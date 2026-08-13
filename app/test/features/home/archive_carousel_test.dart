import 'package:app/features/home/archive_carousel.dart';
import 'package:app/features/home/home_api.dart';
import 'package:app/features/room/default_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('아카이브 항목 제목이 오버레이로 표시되고 탭하면 콜백이 온다', (tester) async {
    ArchiveBrief? tapped;
    await tester.pumpWidget(
      wrap(
        ArchiveCarousel(
          items: [
            ArchiveBrief(id: 1, title: '자료A', pinned: false, likeCount: 0),
            ArchiveBrief(id: 2, title: '자료B', pinned: true, likeCount: 3),
          ],
          onTapItem: (item) => tapped = item,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('자료A'), findsOneWidget);
    expect(find.text('자료B'), findsOneWidget);

    await tester.tap(find.text('자료A'));
    await tester.pumpAndSettle();
    expect(tapped?.id, 1);
  });

  testWidgets('썸네일이 없으면 기본 커버 이미지로 채운다', (tester) async {
    // 2026-08-05 요청: "사진 없으면 대체 사진으로(assets/images/covers)".
    // 회색 채움(surface-strong)만 두면 미리보기가 빈 카드처럼 보였다.
    await tester.pumpWidget(
      wrap(
        ArchiveCarousel(
          items: [
            ArchiveBrief(id: 7, title: '썸네일없음', pinned: false, likeCount: 0),
          ],
          onTapItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      defaultCoverAsset(7),
      reason: '항목 id로 정해진 커버 — 리빌드마다 바뀌면 깜빡인다',
    );
  });

  testWidgets('항목마다 다른 기본 커버가 배정된다', (tester) async {
    await tester.pumpWidget(
      wrap(
        ArchiveCarousel(
          items: [
            ArchiveBrief(id: 1, title: 'A', pinned: false, likeCount: 0),
            ArchiveBrief(id: 2, title: 'B', pinned: false, likeCount: 0),
          ],
          onTapItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final assets = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => (i.image as AssetImage).assetName)
        .toList();
    expect(assets, [defaultCoverAsset(1), defaultCoverAsset(2)]);
    expect(assets.first, isNot(assets.last));
  });

  testWidgets('핀·좋아요 뱃지는 값이 있을 때만 표시된다', (tester) async {
    await tester.pumpWidget(
      wrap(
        ArchiveCarousel(
          items: [
            ArchiveBrief(id: 2, title: '자료B', pinned: true, likeCount: 3),
          ],
          onTapItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
