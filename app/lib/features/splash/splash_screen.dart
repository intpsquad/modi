import 'package:flutter/material.dart';

import '../../design/modi_wordmark.dart';
import '../../design/tokens.dart';
import '../../routing/app_session.dart';

/// S-00 스플래시 — 인증 상태를 기다리는 동안 MODI 로고를 미니멀 페이드인으로 보여준다
/// (2026-08-05 — 기존 점 궤도 애니메이션에서 전환).
/// 재진입 라우팅·인증 판정은 app_router.dart의 redirect(AppSession)가 전담한다.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    // 진입: 로고 투명도 0→100%, 1.0초 ease-in-out(2026-08-09 QA — 기존 1.5초에서 단축).
    // splashMinimumDuration(1.2초)이 이 값보다 커야 페이드인이 끝난 뒤 넘어간다.
    // 이탈(fade-out)과 다음 화면 오버랩은 app_router.dart의 /splash fade 전환이 맡는다.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedBuilder(
      animation: appSession,
      builder: (context, _) {
        final hasError = appSession.bootError != null;
        return Scaffold(
          backgroundColor: AppColors.canvas,
          body: Center(
            child: Semantics(
              container: true,
              label: hasError ? 'MODI 로고, 앱 준비에 실패함' : 'MODI 로고, 앱을 준비하는 중',
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 모션 비활성화면 정적 로고, 아니면 투명도 페이드인.
                    // 공용 ModiWordmark 재사용(filterQuality.high로 선명).
                    // width 160 ≈ height 49(비율 ≈3.26:1).
                    if (reduceMotion)
                      const ModiWordmark(
                        key: ValueKey('splash-logo'),
                        height: 49,
                      )
                    else
                      FadeTransition(
                        opacity: _fade,
                        child: const ModiWordmark(
                          key: ValueKey('splash-logo'),
                          height: 49,
                        ),
                      ),
                    if (hasError) ...[
                      const SizedBox(height: AppSpacing.content),
                      Text(
                        appSession.bootError!,
                        style: AppTypography.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.cardGap),
                      OutlinedButton(
                        onPressed: appSession.retryBootstrap,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
