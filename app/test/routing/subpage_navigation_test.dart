import 'package:app/design/theme.dart';
import 'package:app/routing/app_router.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 하위 페이지 규칙(2026-08-05 요청) — specs/0003-navigation.md.
/// ① 뒤로가기 아이콘은 `<`(chevron), ② 오른쪽→왼쪽으로 밀려 들어옴,
/// ③ 네비바가 보이지 않음(루트 네비게이터에 push), ④ 왼쪽 끝에서 오른쪽으로 끌면 뒤로.

/// 셸 브랜치 안에 중첩된 하위 라우트를 모두 모은다(탭 루트 화면은 제외).
List<GoRoute> _shellSubRoutes(List<RouteBase> routes) {
  final found = <GoRoute>[];
  void collectNested(RouteBase route) {
    for (final child in route.routes) {
      if (child is GoRoute) found.add(child);
      collectNested(child);
    }
  }

  for (final route in routes) {
    if (route is StatefulShellRoute) {
      for (final branch in route.branches) {
        for (final branchRoute in branch.routes) {
          collectNested(branchRoute);
        }
      }
    }
  }
  return found;
}

void main() {
  group('하위 페이지의 네비바 노출 규칙', () {
    test('자료 본문 등은 루트 push(네비바 숨김), 아카이브 폴더 자료 목록만 브랜치(네비바 유지)', () {
      final subRoutes = _shellSubRoutes(appRouter.configuration.routes);

      expect(
        subRoutes.map((r) => r.path),
        containsAll(['folder/:id', 'item/:id']),
      );
      for (final route in subRoutes) {
        if (route.path == 'folder/:id') {
          // 2026-08-08 요청 — 폴더 선택·자료 선택 화면까지는 하단 네비바를 유지한다.
          // 셸 브랜치 안에 두어(parentNavigatorKey 없음) 네비바가 함께 보인다.
          expect(
            route.parentNavigatorKey,
            isNull,
            reason: 'folder/:id는 셸 브랜치 안이라 하단 네비바가 유지돼야 한다.',
          );
        } else {
          // 자료 본문(item/:id)·투두 상세·마이 하위 등은 몰입 위해 네비바를 덮는다.
          expect(
            route.parentNavigatorKey,
            same(rootNavigatorKey),
            reason:
                '${route.path}는 루트 네비게이터에 push해 네비바를 덮어야 한다 — '
                'parentNavigatorKey: rootNavigatorKey.',
          );
        }
      }
    });
  });

  group('전환 애니메이션 · 뒤로가기 아이콘', () {
    test('모든 플랫폼이 Cupertino 전환을 쓴다(우→좌 슬라이드 + 엣지 백 제스처)', () {
      final builders = AppTheme.light.pageTransitionsTheme.builders;

      for (final platform in TargetPlatform.values) {
        expect(
          builders[platform],
          isA<CupertinoPageTransitionsBuilder>(),
          reason: '$platform 전환이 기본(Zoom/Fade)으로 돌아가면 엣지 백 제스처가 사라진다',
        );
      }
    });

    testWidgets('AppBar 기본 뒤로가기는 `<`(chevron_left)다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('하위')),
                      body: const Text('하위 본문'),
                    ),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);
    });

    testWidgets('새 페이지는 오른쪽에서 왼쪽으로 밀려 들어온다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const Scaffold(body: Center(child: Text('하위 본문'))),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
      double bodyX() => tester.getTopLeft(find.text('하위 본문')).dx;

      // 먼저 정지 위치를 잰다 — 시작 오프셋을 이 기준으로 비교해야 의미가 있다.
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      final restX = bodyX();
      Navigator.of(tester.element(find.text('하위 본문'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('열기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      // 화면 **오른쪽 끝 바깥**에서 출발한다 = 정지 위치보다 화면폭만큼 오른쪽.
      // 기본 전환(Zoom/PredictiveBack)은 200px 정도만 움직여 여기서 걸린다.
      expect(
        bodyX() - restX,
        greaterThan(screenWidth * 0.9),
        reason: '오른쪽 화면 밖에서 들어와야 한다',
      );

      await tester.pump(const Duration(milliseconds: 80));
      final midX = bodyX();
      expect(midX, lessThan(restX + screenWidth * 0.9), reason: '왼쪽으로 이동 중');

      await tester.pump(const Duration(milliseconds: 120));
      expect(bodyX(), lessThan(midX), reason: '계속 왼쪽으로 이동한다');

      await tester.pumpAndSettle();
      expect(bodyX(), closeTo(restX, 0.5), reason: '전환이 끝나면 제자리에 앉는다');
    });

    testWidgets('왼쪽 끝을 잡고 오른쪽으로 끌면 이전 화면이 드러난다', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const Scaffold(body: Center(child: Text('하위 본문'))),
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      expect(find.text('열기'), findsNothing);

      // 왼쪽 끝(x≈2)에서 오른쪽으로 스와이프 → 뒤로.
      await tester.timedDragFrom(
        const Offset(2, 300),
        const Offset(400, 0),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(find.text('하위 본문'), findsNothing);
      expect(find.text('열기'), findsOneWidget);
    });
  });
}
