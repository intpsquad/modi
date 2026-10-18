import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'tokens.dart';

/// 좌측 스와이프로 행 뒤의 액션(삭제 등)을 드러내는 공용 부품 — design.md §6 "스와이프 액션
/// 버튼"·§8 인터랙션.
///
/// 원래 투두 탭(`todos_screen.dart`) 안에만 있던 것을 알림 내역(S-41, #111)도 쓰게 되어
/// 꺼냈다. 동작은 그대로다. 쓰는 곳: 투두 행·카테고리 헤더(S-16), 알림 내역 행(S-41).

/// 열린 스와이프 액션 패널을 화면에 **하나만** 유지하기 위한 컨트롤러 모음(요청).
/// 행/헤더가 만든 [SlidableController]를 등록해두고, 다른 동작이 시작되면 전부 닫는다.
/// 패키지의 `SlidableAutoCloseBehavior`를 쓰지 않는 이유: 열린 상태의 탭을 AbsorbPointer로
/// 먹어버려서 "닫고 그 동작도 바로 실행"(사용자 확정)이 불가능하다.
class SlidableGroup {
  final List<SlidableController> _controllers = [];

  void register(SlidableController controller) => _controllers.add(controller);

  void unregister(SlidableController controller) =>
      _controllers.remove(controller);

  /// 열려 있는 패널을 모두 닫는다. [except]는 방금 열리는 중인 자신을 제외할 때 쓴다.
  void closeAll({SlidableController? except}) {
    // close()가 리스너를 통해 목록을 건드릴 수 있어 사본을 순회한다.
    for (final controller in List.of(_controllers)) {
      if (controller == except || controller.closing) continue;
      if (controller.ratio != 0) controller.close();
    }
  }
}

/// 눌림(pressed) 배경을 직접 그리는 탭 영역 — `InkWell` 대체.
/// InkWell을 쓰지 않는 이유: ① 스플래시가 남아 좌우로 슬라이드하는 동안 행에 배경색이
/// 깔려 보인다(요청: 슬라이드 중엔 투명), ② 리플이 박스를 넘어 번진다.
/// 수평 드래그가 제스처 아레나를 가져가면 onTapCancel이 즉시 떨어져 배경이 사라진다.
class PressableBox extends StatefulWidget {
  const PressableBox({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<PressableBox> createState() => _PressableBoxState();
}

class _PressableBoxState extends State<PressableBox> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          // 눌리지 않은 상태는 투명 — 슬라이드 중에도 배경색이 생기지 않는다.
          color: _pressed ? AppColors.surfaceStrong : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: widget.child,
      ),
    );
  }
}

/// 스와이프 액션 버튼 — 시각 크기 50×28(라운드 8)이지만 **히트박스는 행 높이 전체**로
/// 넓힌다(design.md §6: 탭 영역 최소 44×44 — 파괴적인 [삭제]가 [수정] 옆 4px에 붙어 있어
/// 오터치 위험이 특히 크다). 탭하면 자기 패널을 닫고 콜백을 실행한다.
///
/// [icon]을 주면 글자 대신 아이콘을 그린다(알림 내역의 휴지통, #111). [label]은 그때도
/// 스크린리더 이름으로 쓴다.
class SwipeActionButton extends StatelessWidget {
  const SwipeActionButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.icon,
  });

  /// 시각 크기 50×28, 버튼 사이·행과의 간격 4px(요청).
  static const double width = 50;
  static const double height = 28;
  static const double gap = 4;

  /// 히트박스 높이(design.md §6 탭 영역 최소 44).
  static const double hitHeight = 44;

  /// 아이콘 버전의 아이콘 크기 — 28px 박스 안에서 `caption` 글자와 비슷한 무게.
  static const double iconSize = 16;

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;
  final IconData? icon;

  /// 끝까지 당겨 삭제되는 구간에서 쓸 **배경만 좌우로 늘어난** 버전(요청 2).
  /// 높이(28)와 라벨은 그대로 두고 폭만 주어진 공간을 채운다 — 패널이 커질수록 배경이 넓어진다.
  Widget stretched() => _StretchedSwipeAction(
    label: label,
    icon: icon,
    background: background,
    foreground: foreground,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Slidable.of(context)?.close();
          onPressed();
        },
        child: SizedBox(
          width: width,
          height: hitHeight, // 히트박스(44) — 시각 박스는 아래 28
          child: Center(
            child: Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              child: _SwipeActionContent(
                label: label,
                icon: icon,
                foreground: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 버튼 안쪽 — 아이콘이 있으면 아이콘, 없으면 라벨 글자.
class _SwipeActionContent extends StatelessWidget {
  const _SwipeActionContent({
    required this.label,
    required this.icon,
    required this.foreground,
  });

  final String label;
  final IconData? icon;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    if (icon != null) {
      // 이름은 바깥 Semantics(label)가 준다 — 아이콘 자체는 읽지 않게 한다.
      return ExcludeSemantics(
        child: Icon(icon, size: SwipeActionButton.iconSize, color: foreground),
      );
    }
    return Text(
      label,
      style: AppTypography.caption.copyWith(
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
    );
  }
}

/// `DismissiblePane`의 모션. 이 위젯은 **한 번 마운트되면 계속 남는다**(패키지가
/// `isDismissibleReady`를 되돌리지 않는다) — 그래서 스스로 두 모습을 오간다:
///  · 열린 상태(패널 폭 이내) → 평소의 버튼 배치
///  · 더 당긴 상태(삭제 확정 구간) → 배경이 좌우로 넓어진 버전
/// 이걸 구분하지 않고 늘어난 버전만 주면, 손을 떼고 패널이 닫힌 뒤에도 늘어난 채로 남는다.
class _DismissMotion extends StatelessWidget {
  const _DismissMotion({required this.actionsRow, required this.stretched});

  final Widget actionsRow;
  final Widget stretched;

  @override
  Widget build(BuildContext context) {
    final controller = Slidable.of(context);
    final extentRatio = ActionPane.of(context)?.extentRatio;
    if (controller == null || extentRatio == null) return actionsRow;
    return AnimatedBuilder(
      animation: controller.animation,
      builder: (context, _) {
        // 부동소수 오차로 경계에서 깜빡이지 않게 아주 작은 여유를 둔다.
        final past = controller.ratio.abs() > extentRatio + 0.001;
        return past ? stretched : actionsRow;
      },
    );
  }
}

/// 끝까지 당기는 동안(=삭제 확정 구간) 보여주는 액션 — 같은 색·높이의 배경이 **좌우로 꽉 찬다**.
/// 라벨(또는 아이콘)은 오른쪽(원래 버튼이 있던 자리)에 남겨 무엇이 일어나는지 알 수 있게 한다.
/// 탭 대상이 아니다(손을 떼는 순간 삭제된다).
class _StretchedSwipeAction extends StatelessWidget {
  const _StretchedSwipeAction({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: SwipeActionButton.height,
        width: double.infinity,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: _SwipeActionContent(
          label: label,
          icon: icon,
          foreground: foreground,
        ),
      ),
    );
  }
}

/// 좌측 스와이프로 [actions](50×28, 사이 4px)를 드러내는 행 래퍼.
/// 자기 [SlidableController]를 [group]에 등록해, 열리는 순간 다른 패널을 모두 닫는다.
/// [onDismissed]를 주면 끝까지 당겼을 때 그대로 실행된다(투두·알림 삭제). 확인 모달이 필요한
/// 카테고리 삭제는 null로 둬서 전체 스와이프 즉시 실행을 막는다.
class SwipeActionRow extends StatefulWidget {
  const SwipeActionRow({
    super.key,
    required this.group,
    required this.actions,
    required this.child,
    this.onDismissed,
  });

  final SlidableGroup group;

  /// 드러날 액션 버튼들. [SwipeActionButton] 으로 타입을 좁혀 둔 이유는, 끝까지 당기는 구간에서
  /// 마지막 액션의 "배경만 늘어난" 버전(`stretched()`)이 필요하기 때문이다.
  final List<SwipeActionButton> actions;
  final Widget child;
  final VoidCallback? onDismissed;

  @override
  State<SwipeActionRow> createState() => _SwipeActionRowState();
}

class _SwipeActionRowState extends State<SwipeActionRow>
    with TickerProviderStateMixin {
  late final SlidableController _controller = SlidableController(this);
  // DismissiblePane은 Slidable에 key를 요구한다(리스트에서 제거될 때 상태가 다음 항목으로
  // 밀리지 않도록). 이 위젯은 호출자에게서 키를 받으니, 내부 Slidable엔 State와 1:1인 키를 준다.
  final Key _slidableKey = UniqueKey();
  bool _wasOpen = false;

  @override
  void initState() {
    super.initState();
    widget.group.register(_controller);
    _controller.animation.addListener(_handleSlide);
  }

  @override
  void dispose() {
    _controller.animation.removeListener(_handleSlide);
    widget.group.unregister(_controller);
    _controller.dispose();
    super.dispose();
  }

  /// 닫힘→열림으로 넘어가는 순간에만 다른 패널을 닫는다(매 프레임 호출 방지).
  void _handleSlide() {
    final open = _controller.ratio != 0;
    if (open && !_wasOpen) widget.group.closeAll(except: _controller);
    _wasOpen = open;
  }

  /// 드러날 폭 = [행과의 간격 4] + 버튼들(50) + [버튼 사이 간격 4].
  /// 버튼 크기를 픽셀로 고정해야 해서 실제 행 폭으로 나눠 비율(extentRatio)로 환산한다.
  double get _actionsExtent {
    final count = widget.actions.length;
    return SwipeActionButton.gap +
        count * SwipeActionButton.width +
        (count - 1) * SwipeActionButton.gap;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extentRatio = (_actionsExtent / constraints.maxWidth).clamp(
          0.05,
          0.9,
        );
        final onDismissed = widget.onDismissed;
        // 평소(패널이 열린 상태)의 버튼 배치 — BehindMotion 과 DismissiblePane 이 함께 쓴다.
        final actionsRow = Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.actions.length; i++) ...[
                if (i > 0) const SizedBox(width: SwipeActionButton.gap),
                widget.actions[i],
              ],
            ],
          ),
        );
        return Slidable(
          key: _slidableKey,
          controller: _controller,
          // BehindMotion — StretchMotion은 고정 폭 버튼을 찌그러뜨린다(버튼 크기 고정 요청).
          endActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: extentRatio,
            // 끝까지(60% 이상) 당기면 그대로 실행(투두·알림 삭제만). 그 구간에는 버튼 대신
            // **배경이 좌우로 넓어지는** 버전을 보여준다(요청 2) — 패널이 커질수록 같이 넓어진다.
            dismissible: onDismissed == null
                ? null
                : DismissiblePane(
                    onDismissed: onDismissed,
                    dismissThreshold: 0.6,
                    motion: _DismissMotion(
                      actionsRow: actionsRow,
                      stretched: widget.actions.last.stretched(),
                    ),
                  ),
            children: [Expanded(child: actionsRow)],
          ),
          child: widget.child,
        );
      },
    );
  }
}
