import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// 홈 활동 배너 한 줄 안의 조각. 닉네임 등 강조할 부분만 [bold]로 굵게 그린다.
class ActivitySegment {
  const ActivitySegment(this.text, {this.bold = false});

  final String text;
  final bool bold;
}

/// 활동 배너에 노출하는 한 줄 메시지(닉네임 Bold + 본문 Regular 조합).
class ActivityMessage {
  const ActivityMessage(this.segments);

  /// 강조 없는 단문(마일스톤·D-day 등)용.
  factory ActivityMessage.plain(String text) =>
      ActivityMessage([ActivitySegment(text)]);

  final List<ActivitySegment> segments;

  String get plainText => segments.map((s) => s.text).join();
}

/// S-04 홈 · 활동 캡슐 배너(라이브 티커) — specs/0005-홈-대시보드.md.
///
/// 스터디원 활동을 한 줄씩 [interval](기본 4초) 간격으로 부드럽게 롤링해 소셜 프루프를
/// 유도한다. 메시지가 하나뿐이면 정적으로 두고, 누르는 동안엔 자동 회전을 잠시 멈춘다.
/// 접근성 "동작 줄이기"(reduce motion)가 켜져 있으면 자동 회전 없이 첫 메시지만 보이고,
/// 바뀌는 문구는 `Semantics(liveRegion)`으로 스크린리더에 알린다.
/// [messages]는 caller가 중요·최신순으로 정렬해 넣는다(위젯은 앞에서부터 순환).
class ActivityCapsuleBanner extends StatefulWidget {
  const ActivityCapsuleBanner({
    super.key,
    required this.messages,
    this.interval = const Duration(seconds: 4),
    this.reduceMotion,
  });

  final List<ActivityMessage> messages;
  final Duration interval;

  /// null이면 `MediaQuery.disableAnimations`(OS 동작 줄이기)를 따른다. 테스트 주입용.
  final bool? reduceMotion;

  @override
  State<ActivityCapsuleBanner> createState() => _ActivityCapsuleBannerState();
}

class _ActivityCapsuleBannerState extends State<ActivityCapsuleBanner> {
  int _index = 0;
  Timer? _timer;
  bool _paused = false;

  bool get _reduceMotion =>
      widget.reduceMotion ?? MediaQuery.of(context).disableAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant ActivityCapsuleBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages.length != widget.messages.length ||
        oldWidget.interval != widget.interval) {
      if (widget.messages.isNotEmpty) {
        _index = _index % widget.messages.length;
      }
      _restartTimer();
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.messages.length > 1 && !_reduceMotion) {
      _timer = Timer.periodic(widget.interval, (_) {
        if (!mounted || _paused) return;
        setState(() => _index = (_index + 1) % widget.messages.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    if (messages.isEmpty) return const SizedBox.shrink();

    final message = messages[_index.clamp(0, messages.length - 1)];

    final banner = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        // 배경: #FFFFFF 80% 불투명(2026-08-07 요청). 테두리 없음.
        color: Color(0xCCFFFFFF),
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
        // 바깥쪽 그림자 — 디자이너 지정값(X0 Y2 blur10 spread0, #A5A5A5 @20%).
        // design.md의 AppElevation.float와 다른 커스텀값 → OPEN.md 드리프트 항목에 기록.
        boxShadow: [
          BoxShadow(
            color: Color(0x33A5A5A5),
            offset: Offset(0, 2),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          const _GradientDot(),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: _reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeOut,
                  // 기본 layoutBuilder는 가운데 정렬이라 왼쪽(start)으로 바꾼다.
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previousChildren, ?currentChild],
                  ),
                  // 위로 밀려 올라가는 전환: 새 문구는 아래에서 올라오고 이전 문구는 위로 빠진다.
                  transitionBuilder: (child, animation) {
                    final key = (child.key as ValueKey<int>?)?.value;
                    final incoming = key == _index;
                    final begin = incoming
                        ? const Offset(0, 1)
                        : const Offset(0, -1);
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: begin,
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    );
                  },
                  child: Text.rich(
                    TextSpan(
                      children: [
                        for (final segment in message.segments)
                          TextSpan(
                            text: segment.text,
                            style: segment.bold
                                ? const TextStyle(fontWeight: FontWeight.w700)
                                : null,
                          ),
                      ],
                    ),
                    key: ValueKey<int>(_index),
                    textAlign: TextAlign.left,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // 누르는 동안 자동 회전 정지 — reduce motion 대응과 함께 "멈출 수 있게".
    return Listener(
      onPointerDown: (_) => _paused = true,
      onPointerUp: (_) => _paused = false,
      onPointerCancel: (_) => _paused = false,
      child: banner,
    );
  }
}

/// 좌측 시각 앵커(2026-08-07 요청) — 14×14 큰 원(#FF385C→#FF7BF8 좌→우 그라데이션 @30%
/// 불투명) 안에 작은 단색 원(#FF385C). 그라데이션 색은 primary·aiGradientEnd의 30% 알파값.
class _GradientDot extends StatelessWidget {
  const _GradientDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x4DFF385C), Color(0x4DFF7BF8)],
        ),
      ),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary,
        ),
        child: SizedBox(width: 6, height: 6),
      ),
    );
  }
}
