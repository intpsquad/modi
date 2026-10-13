import 'dart:async';

import 'package:flutter/material.dart';

import 'tokens.dart';

/// 누른 위젯 **바로 위**에 뿅 떠올랐다 팔랑 사라지는 작은 토스트 — specs/design.md §6, #105.
///
/// 기본 [SnackBar]를 대신한다. 스낵바는 화면 맨 아래에 뜨는데, 누른 버튼이 화면 위쪽에 있으면
/// **눈이 따라가야 하고** 모양도 Material 기본값이라 이 앱 톤에서 혼자 튄다.
///
/// ⚠️ **지금 쓰는 곳은 콕찌르기(S-30-M) 성공·실패 둘뿐이다.** 앱에는 `showSnackBar`가 아직 20여
/// 곳 남아 있고, 이 토스트가 괜찮다고 판단되면 그때 옮긴다 — 한 번에 바꾸지 않는다.
///
/// 쓰는 쪽은 앵커 위젯을 [CompositedTransformTarget]으로 감싸고 그 [LayerLink]를 넘긴다:
///
/// ```dart
/// final _link = LayerLink();
/// ...
/// CompositedTransformTarget(link: _link, child: _PokeButton(...))
/// ...
/// showFloatToast(context, _link, '콕 찔렀어요');
/// ```
void showFloatToast(BuildContext context, LayerLink link, String message) {
  final overlay = Overlay.maybeOf(context);
  // 화면이 이미 사라진 뒤(비동기 응답이 늦게 온 경우)에는 조용히 포기한다 —
  // 피드백 하나 때문에 화면이 깨지는 쪽이 더 나쁘다.
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FloatToast(
      link: link,
      message: message,
      onFinished: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _FloatToast extends StatefulWidget {
  const _FloatToast({
    required this.link,
    required this.message,
    required this.onFinished,
  });

  final LayerLink link;
  final String message;
  final VoidCallback onFinished;

  @override
  State<_FloatToast> createState() => _FloatToastState();
}

class _FloatToastState extends State<_FloatToast>
    with SingleTickerProviderStateMixin {
  /// 🔴 아래 값들은 **임시값이다.** `specs/design.md`에는 색·타이포·간격·라운드·엘리베이션만
  /// 있고 **모션(duration·easing) 절이 아예 없다** — `specs/OPEN.md`「모션/애니메이션 토큰 부재」.
  /// `room_switch_hint.dart`의 펄스도 같은 이유로 상단 상수로 모아뒀다. 모션 토큰이 생기면
  /// **이 네 줄만** 토큰으로 바꾸면 된다.
  static const Duration enterDuration = Duration(milliseconds: 220);
  static const Duration holdDuration = Duration(milliseconds: 1200);
  static const Duration exitDuration = Duration(milliseconds: 180);

  /// 등장할 때 아래에서 떠오르는 거리(px).
  static const double riseDistance = 8;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: enterDuration,
    reverseDuration: exitDuration,
  );
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    // 🔴 등장·유지·퇴장을 **하나의 컨트롤러로 묶지 않는다.** 묶으면 위젯 테스트의
    // `pumpAndSettle()`이 애니메이션을 끝까지 재생해, 토스트가 사라진 뒤에 검사하게 된다
    // (member_todos_screen_test.dart 의 기존 테스트가 그렇게 돼 있다).
    // 유지 구간을 Timer 로 두면 settle 은 등장만 끝내고 반환하므로 문구가 보인다 —
    // SnackBar 가 쓰는 구조와 같다.
    _enter.forward();
    _hold = Timer(holdDuration, () async {
      if (!mounted) return;
      await _enter.reverse();
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    // 🔴 반드시 취소한다. 남겨두면 테스트가 끝난 뒤에도 타이머가 살아 있어
    // "A Timer is still pending…" 으로 **무관한 테스트까지** 깨진다.
    _hold?.cancel();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 접근성 설정으로 애니메이션을 끈 사용자에게는 움직이지 않고 그냥 보인다.
    final animate = !MediaQuery.of(context).disableAnimations;

    return Positioned(
      // left/top 만 주고 크기를 비워 둔다 — 자식이 제 크기대로 잡고,
      // 실제 위치는 아래 CompositedTransformFollower 가 앵커를 따라가며 정한다.
      // (left/right 를 함께 주면 높이가 무한으로 내려와 레이아웃이 터진다.)
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: widget.link,
        // 🔴 **오른쪽 끝을 버튼 오른쪽에 맞춘다**(가운데 정렬이 아니다).
        // 이 버튼은 프로필 행 오른쪽 끝에 있어서, 가운데에 맞추면 긴 문구
        // ("콕 찌르지 못했어요")가 화면 밖으로 잘린다. 오른쪽을 맞추면 버튼이 화면 안에
        // 있는 한 토스트도 안에 있다 — 클램프 계산이 필요 없다.
        targetAnchor: Alignment.topRight,
        followerAnchor: Alignment.bottomRight,
        offset: const Offset(0, -AppSpacing.xs),
        showWhenUnlinked: false,
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _enter,
            builder: (context, child) {
              final t = animate ? _enter.value : 1.0;
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * riseDistance),
                  // 0.92 → 1.0 으로 살짝 부풀며 들어온다("뿅").
                  child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
                ),
              );
            },
            child: _bubble(),
          ),
        ),
      ),
    );
  }

  Widget _bubble() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.foreground,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: AppElevation.float,
        ),
        child: Text(
          widget.message,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
