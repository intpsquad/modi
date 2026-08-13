import 'package:flutter/widgets.dart';

/// 탭(브랜치) 전환을 옆으로 미끄러지듯 보여주는 컨테이너.
///
/// `StatefulShellRoute.indexedStack`은 전환이 즉시(프레임 하나) 일어나 붙었다 떨어지는 느낌이라
/// `navigatorContainerBuilder`로 갈아끼우고 여기서 직접 그린다.
///
/// **모든 브랜치 네비게이터를 계속 트리에 유지한다**(비활성은 [Offstage]) — `IndexedStack`이
/// 하던 "탭 상태 보존"을 그대로 지켜야 하기 때문이다. 전환 중에만 이전/새 탭 둘을 같이 그린다.
/// 오른쪽 탭으로 가면 새 화면이 오른쪽에서 들어오고 이전 화면은 왼쪽으로 빠진다.
class AnimatedBranchContainer extends StatefulWidget {
  const AnimatedBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
    this.duration = const Duration(milliseconds: 220),
  });

  final int currentIndex;
  final List<Widget> children;
  final Duration duration;

  @override
  State<AnimatedBranchContainer> createState() =>
      _AnimatedBranchContainerState();
}

class _AnimatedBranchContainerState extends State<AnimatedBranchContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// 전환 중 같이 그려지는 "빠져나가는" 탭. 애니메이션이 끝나면 null.
  int? _outgoingIndex;

  /// 왼쪽으로 가는 전환인가(= 인덱스가 커지는 방향).
  bool _forward = true;

  @override
  void didUpdateWidget(AnimatedBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex) return;
    setState(() {
      _outgoingIndex = oldWidget.currentIndex;
      _forward = widget.currentIndex > oldWidget.currentIndex;
    });
    _controller.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _outgoingIndex = null);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return Stack(
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _branch(index: i, curve: curve, child: widget.children[i]),
      ],
    );
  }

  /// 브랜치 하나. **위젯 구조(Offstage→TickerMode→SlideTransition→IgnorePointer)를
  /// 탭 상태와 무관하게 항상 동일하게 유지한다** — 구조가 바뀌면 element 가 다시 만들어져
  /// 그 탭의 State(스크롤 위치·입력값 등)가 날아간다.
  Widget _branch({
    required int index,
    required Animation<double> curve,
    required Widget child,
  }) {
    final isCurrent = index == widget.currentIndex;
    final isOutgoing = index == _outgoingIndex;
    final visible = isCurrent || isOutgoing;
    // 전환 중이 아니면(_outgoingIndex == null) 현재 탭은 제자리다 — 트윈을 걸어두면
    // 컨트롤러가 0인 첫 프레임에 화면이 통째로 옆으로 밀려난 채 뜬다.
    final animating = _outgoingIndex != null;
    // 들어오는 탭: 진행 방향 반대편에서 0으로. 빠지는 탭: 0에서 진행 방향으로.
    final sign = _forward ? 1.0 : -1.0;
    final Animation<Offset> offset;
    if (isCurrent && animating) {
      offset = Tween(begin: Offset(sign, 0), end: Offset.zero).animate(curve);
    } else if (isOutgoing) {
      offset = Tween(begin: Offset.zero, end: Offset(-sign, 0)).animate(curve);
    } else {
      offset = const AlwaysStoppedAnimation(Offset.zero);
    }
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: SlideTransition(
          position: offset,
          // 빠지는 탭은 입력을 받지 않는다(전환 중 두 화면이 겹쳐 있으므로).
          child: IgnorePointer(ignoring: !isCurrent, child: child),
        ),
      ),
    );
  }
}
