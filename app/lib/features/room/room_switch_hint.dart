import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/tokens.dart';

/// 코치마크 노출 단계 — specs/0008-방-전환.md "롱프레스 코치마크".
enum RoomSwitchHintStage {
  /// 1단계: 최초 홈 진입 1회. 방이 1개뿐이어도 무조건 보여준다(사용법 자체를 먼저 각인).
  intro,

  /// 2단계: ACTIVE 방이 2개 이상이 된 뒤 1회. 실제로 쓸모가 생긴 시점에 다시 알린다.
  multi,
}

/// 코치마크 노출 이력 — `shared_preferences`. specs/0008-방-전환.md.
/// 롱프레스를 한 번이라도 성공한 사용자에게는 어느 단계도 다시 띄우지 않는다.
class RoomSwitchHintPrefs {
  RoomSwitchHintPrefs._();

  static const usedKey = 'room_switch_longpress_used';
  static const introShownKey = 'room_switch_hint_intro_shown';
  static const multiShownKey = 'room_switch_hint_multi_shown';

  /// 지금 띄워야 할 단계(없으면 null).
  static Future<RoomSwitchHintStage?> pendingStage({
    required int activeRoomCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(usedKey) ?? false) return null;
    if (!(prefs.getBool(introShownKey) ?? false)) {
      return RoomSwitchHintStage.intro;
    }
    if (activeRoomCount >= 2 && !(prefs.getBool(multiShownKey) ?? false)) {
      return RoomSwitchHintStage.multi;
    }
    return null;
  }

  static Future<void> markShown(RoomSwitchHintStage stage) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      stage == RoomSwitchHintStage.intro ? introShownKey : multiShownKey,
      true,
    );
  }

  /// 하단 네비 홈 버튼 롱프레스로 방 전환 시트를 연 순간 호출 — 이후 코치마크 영구 미노출.
  static Future<void> markUsed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(usedKey, true);
  }
}

/// 대상 위치를 스포트라이트로 비추는 코치마크 — specs/0008-방-전환.md, specs/design.md §6.
///
/// 두 가지로 쓰인다:
/// - **최초 진입 2스텝 투어**(app_shell): 네비바 홈 → 멤버 아바타. 바깥 탭으로는 안 닫히고
///   우하단 [primaryLabel] 버튼(다음/완료)으로만 진행·종료한다([dismissOnOutsideTap] = false).
///   홈 스텝은 구멍 롱프레스로 방 전환 실습을 유지한다([onTryNow]).
/// - **방 2개 이상 리마인더**(multi 단계): 버튼 없이 바깥 탭으로 닫히는 단일 스텝(기존 동작,
///   [dismissOnOutsideTap] = true·[primaryLabel] = null 기본값).
class RoomSwitchHintOverlay extends StatefulWidget {
  const RoomSwitchHintOverlay({
    super.key,
    required this.targetCenter,
    required this.onDismiss,
    this.onTryNow,
    this.title = '홈을 꾹 누르면 방을 바꿀 수 있어요',
    this.body = '지금 홈 버튼을 길게 눌러보세요',
    this.semanticsLabel = '홈 버튼을 길게 누르면 방을 전환할 수 있어요. 화면을 탭하면 이 안내를 닫습니다.',
    this.primaryLabel,
    this.onPrimary,
    this.dismissOnOutsideTap = true,
    this.bubbleBelow = false,
  });

  /// 스포트라이트로 비출 대상 중심(글로벌 좌표).
  final Offset targetCenter;

  /// 바깥/구멍을 단순 탭했다 — [dismissOnOutsideTap]일 때만 호출된다.
  final VoidCallback onDismiss;

  /// 구멍 안을 롱프레스했다(예: 홈 스텝 방 전환 실습). null이면 롱프레스 동작 없음.
  final VoidCallback? onTryNow;

  /// 말풍선 제목/본문.
  final String title;
  final String body;

  /// 스크린리더용 라벨.
  final String semanticsLabel;

  /// 우하단 진행 버튼 라벨(예: 다음/완료). null이면 버튼을 그리지 않는다.
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// 바깥/구멍 단순 탭으로 닫을지. 투어는 false(버튼으로만 진행).
  final bool dismissOnOutsideTap;

  /// 대상이 화면 상단(아바타)이면 말풍선을 구멍 아래에 두고 꼬리를 위로 뒤집는다.
  final bool bubbleBelow;

  /// 구멍 최소/최대 반지름. design.md에 모션 토큰이 없어 임시값이다(specs/OPEN.md).
  static const double holeRadiusMin = 28;
  static const double holeRadiusMax = 34;
  static const Duration pulseDuration = Duration(milliseconds: 1200);

  @override
  State<RoomSwitchHintOverlay> createState() => _RoomSwitchHintOverlayState();
}

class _RoomSwitchHintOverlayState extends State<RoomSwitchHintOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: RoomSwitchHintOverlay.pulseDuration,
  );

  late final Animation<double> _radius = Tween<double>(
    begin: RoomSwitchHintOverlay.holeRadiusMin,
    end: RoomSwitchHintOverlay.holeRadiusMax,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 시스템 "동작 줄이기"가 켜져 있으면 반짝임 없이 최대 반지름으로 고정한다.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final holeTop =
        widget.targetCenter.dy - RoomSwitchHintOverlay.holeRadiusMax;
    final holeBottom =
        widget.targetCenter.dy + RoomSwitchHintOverlay.holeRadiusMax;
    // 바깥/구멍 단순 탭 콜백 — 투어(버튼 진행)에서는 닫히지 않도록 null.
    final tapToDismiss = widget.dismissOnOutsideTap ? widget.onDismiss : null;

    return Positioned.fill(
      child: Semantics(
        container: true,
        label: widget.semanticsLabel,
        // OverlayEntry는 Material 밖이라 Text가 노란 밑줄 경고 스타일로 그려진다 — 실기에서 확인.
        // 배경은 스포트라이트가 직접 칠하므로 transparency로 감싸기만 한다.
        child: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              // 바깥 어디든 탭 → (허용 시) 닫기. 투어에서는 흡수만 하고 안 닫는다.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: tapToDismiss,
                child: AnimatedBuilder(
                  animation: _radius,
                  builder: (context, _) => CustomPaint(
                    size: screen,
                    painter: _SpotlightPainter(
                      center: widget.targetCenter,
                      radius: _radius.value,
                    ),
                  ),
                ),
              ),
              // 말풍선 — 대상 위(기본) 또는 아래(bubbleBelow)에 두고 꼬리로 대상을 가리킨다.
              // 진행 버튼(다음/완료)은 말풍선 하단에 들어간다(하단 고정 시 네비바와 겹쳐서).
              if (widget.bubbleBelow)
                Positioned(
                  left: AppSpacing.content,
                  right: AppSpacing.content,
                  top: holeBottom + AppSpacing.sm,
                  child: _HintBubble(
                    title: widget.title,
                    body: widget.body,
                    tailCenterX: widget.targetCenter.dx - AppSpacing.content,
                    tailUp: true,
                    primaryLabel: widget.primaryLabel,
                    onPrimary: widget.onPrimary,
                  ),
                )
              else
                Positioned(
                  left: AppSpacing.content,
                  right: AppSpacing.content,
                  bottom: screen.height - holeTop + AppSpacing.sm,
                  child: _HintBubble(
                    title: widget.title,
                    body: widget.body,
                    tailCenterX: widget.targetCenter.dx - AppSpacing.content,
                    tailUp: false,
                    primaryLabel: widget.primaryLabel,
                    onPrimary: widget.onPrimary,
                  ),
                ),
              // 구멍 영역 — 홈 스텝에서 여기 롱프레스가 방 전환 실습이다.
              Positioned(
                left:
                    widget.targetCenter.dx -
                    RoomSwitchHintOverlay.holeRadiusMax,
                top: holeTop,
                width: RoomSwitchHintOverlay.holeRadiusMax * 2,
                height: RoomSwitchHintOverlay.holeRadiusMax * 2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: widget.onTryNow,
                  onTap: tapToDismiss,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 전면 dim(`color.scrim`) + 대상 위치만 원형으로 뚫고 강조 링을 그린다.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(scrim, Paint()..color = AppColors.scrim);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.center != center || oldDelegate.radius != radius;
}

class _HintBubble extends StatelessWidget {
  const _HintBubble({
    required this.title,
    required this.body,
    required this.tailCenterX,
    required this.tailUp,
    this.primaryLabel,
    this.onPrimary,
  });

  final String title;
  final String body;
  final double tailCenterX;

  /// 꼬리가 위(말풍선이 대상 아래)인지, 아래(말풍선이 대상 위)인지.
  final bool tailUp;

  /// 말풍선 하단 진행 버튼(다음/완료). null이면 버튼 없음(리마인더 단계).
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  static const double _tailWidth = 16;
  static const double _tailHeight = 8;

  @override
  Widget build(BuildContext context) {
    // 꼬리를 대상 중심에 맞춘다(말풍선 좌측 기준 좌표).
    final tail = Padding(
      padding: EdgeInsets.only(
        left: (tailCenterX - _tailWidth / 2).clamp(
          AppRadius.card,
          double.infinity,
        ),
      ),
      child: CustomPaint(
        size: const Size(_tailWidth, _tailHeight),
        painter: _TailPainter(pointUp: tailUp),
      ),
    );
    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppElevation.float,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: AppTypography.title),
          const SizedBox(height: AppSpacing.xs),
          Text(body, style: AppTypography.bodySmall),
          if (primaryLabel case final label?) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: onPrimary,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(label),
              ),
            ),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: tailUp ? [tail, card] : [card, tail],
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter({required this.pointUp});

  final bool pointUp;

  @override
  void paint(Canvas canvas, Size size) {
    final tail = Path();
    if (pointUp) {
      // 꼭짓점이 위(말풍선 아래에 붙어 대상을 위로 가리킴).
      tail
        ..moveTo(0, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width / 2, 0)
        ..close();
    } else {
      // 꼭짓점이 아래.
      tail
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close();
    }
    canvas.drawPath(tail, Paint()..color = AppColors.canvas);
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) =>
      oldDelegate.pointUp != pointUp;
}
