import 'package:app/features/shell/branch_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 탭 상태 보존을 확인하려고 쓰는, 눌러서 세는 화면.
class _Counter extends StatefulWidget {
  const _Counter({required this.label});

  final String label;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _count++),
      child: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: Center(child: Text('${widget.label}:$_count')),
      ),
    );
  }
}

void main() {
  /// index를 바꿔가며 컨테이너를 다시 그리는 하네스.
  Future<void Function(int)> pumpContainer(WidgetTester tester) async {
    late void Function(int) setIndex;
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setIndex = (i) => setState(() => index = i);
            return AnimatedBranchContainer(
              currentIndex: index,
              children: const [
                _Counter(label: 'A'),
                _Counter(label: 'B'),
                _Counter(label: 'C'),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return setIndex;
  }

  testWidgets('현재 탭만 보이고 나머지는 화면에서 감춰진다', (tester) async {
    await pumpContainer(tester);

    expect(find.text('A:0'), findsOneWidget);
    expect(find.text('B:0'), findsNothing); // offstage
    // 감춰졌을 뿐 트리에는 남아 있다(상태 보존의 전제).
    expect(find.text('B:0', skipOffstage: false), findsOneWidget);
  });

  testWidgets('오른쪽 탭으로 가면 새 화면이 오른쪽에서 들어오고 이전 화면은 왼쪽으로 빠진다', (tester) async {
    final setIndex = await pumpContainer(tester);
    // 정지 위치(가운데 정렬이라 0이 아니다) — 이동 방향은 이 값을 기준으로 판정한다.
    final rest = tester.getTopLeft(find.text('A:0')).dx;

    setIndex(1);
    await tester.pump(); // 전환 시작
    await tester.pump(const Duration(milliseconds: 80)); // 전환 중간

    // 전환 중에는 이전 탭과 새 탭이 같이 그려진다.
    expect(find.text('A:0'), findsOneWidget);
    expect(find.text('B:0'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('B:0')).dx,
      greaterThan(rest),
      reason: '새 탭은 오른쪽에서 들어온다',
    );
    expect(
      tester.getTopLeft(find.text('A:0')).dx,
      lessThan(rest),
      reason: '이전 탭은 왼쪽으로 빠진다',
    );

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('B:0')).dx, rest);
    expect(find.text('A:0'), findsNothing); // 전환이 끝나면 다시 감춰진다
  });

  testWidgets('왼쪽 탭으로 돌아가면 방향이 반대가 된다', (tester) async {
    final setIndex = await pumpContainer(tester);
    final rest = tester.getTopLeft(find.text('A:0')).dx;
    setIndex(2);
    await tester.pumpAndSettle();

    setIndex(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(
      tester.getTopLeft(find.text('A:0')).dx,
      lessThan(rest),
      reason: '왼쪽 탭은 왼쪽에서 들어온다',
    );
    expect(
      tester.getTopLeft(find.text('C:0')).dx,
      greaterThan(rest),
      reason: '이전 탭은 오른쪽으로 빠진다',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('탭을 옮겼다 돌아와도 그 탭의 상태가 남아 있다', (tester) async {
    final setIndex = await pumpContainer(tester);

    await tester.tap(find.text('A:0'));
    await tester.pump();
    await tester.tap(find.text('A:1'));
    await tester.pump();
    expect(find.text('A:2'), findsOneWidget);

    setIndex(1);
    await tester.pumpAndSettle();
    setIndex(0);
    await tester.pumpAndSettle();

    expect(
      find.text('A:2'),
      findsOneWidget,
      reason: 'IndexedStack처럼 탭 상태를 보존해야 한다',
    );
  });
}
