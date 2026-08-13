import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/tokens.dart';
import '../../routing/app_session.dart';

const onboardingIntroCompletedKey = 'onboarding_intro_completed';

/// S-01 서비스 소개 캐러셀.
///
/// 각 슬라이드는 디자이너가 만든 390×844 프레임 PNG(제목·목업이 이미 합성돼 있음)를
/// 풀블리드로 보여주고, 상단 건너뛰기 · 하단 페이지 인디케이터/CTA만 앱이 오버레이한다.
/// 인디케이터: 현재 페이지 = 브랜드 핑크(확장 pill), 나머지 = 연회색 30%(스무스 전환).
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, this.onComplete});

  final Future<void> Function()? onComplete;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _pageController = PageController();
  int _page = 0;
  bool _finishing = false;

  // 4장 캐러셀 — 투두/아카이브/홈 진행률/AI 요약 순.
  // 제목이 이미지에 구워져 있어 스크린리더용 semanticLabel을 함께 둔다(접근성).
  static const _slides = <({String asset, String label})>[
    (
      asset: 'assets/images/onboarding/onborading_1p.png',
      label: '할 일은 나눠서, 담당자만 지정하는 투두 소개',
    ),
    (
      asset: 'assets/images/onboarding/onborading_2p.png',
      label: '흩어진 링크를 폴더에 모으는 아카이브 소개',
    ),
    (
      asset: 'assets/images/onboarding/onborading_3p.png',
      label: '우리 팀 달성률을 실시간으로 보는 홈 소개',
    ),
    (
      asset: 'assets/images/onboarding/onborading_4p.png',
      label: '긴 자료도 AI가 요약해 주는 기능 소개',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      if (widget.onComplete case final callback?) {
        await callback();
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(onboardingIntroCompletedKey, true);
        appSession.markIntroCompleted();
        if (mounted) context.go('/onboarding/login');
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: [
          // 슬라이드 이미지(풀블리드). 화면비가 프레임(390×844)과 다르면 상단 정렬로
          // 제목이 항상 보이도록 두고, 남는 부분만 잘린다.
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              // '다음' 버튼을 없앤 뒤로 스와이프가 유일한 진행 수단이라 모션 감소에서도
              // 스크롤은 허용한다(2026-08-09 QA). 모션 감소는 인디케이터/버튼 페이드만 끈다.
              physics: const PageScrollPhysics(),
              itemCount: _slides.length,
              onPageChanged: (value) => setState(() => _page = value),
              itemBuilder: (context, index) => Image.asset(
                _slides[index].asset,
                key: ValueKey('intro-slide-$index'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                // 보간 품질↑ — 지금 1x 원본의 확대는 여전히 뿌옇지만(근본 해결은
                // 3x 재export), 고해상도로 교체하면 다운스케일이 더 선명해진다.
                filterQuality: FilterQuality.medium,
                semanticLabel: _slides[index].label,
                // 첫 화면이라 에셋 로드 실패 시에도 온보딩이 통째로 깨지지 않게 폴백.
                errorBuilder: (context, error, stack) =>
                    const ColoredBox(color: AppColors.canvas),
              ),
            ),
          ),
          // 상단 건너뛰기 (마지막 페이지에서는 숨김).
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.content,
                AppSpacing.content,
                AppSpacing.content,
                0,
              ),
              child: SizedBox(
                height: 48,
                child: isLast
                    ? null
                    : Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _finishing ? null : _complete,
                          child: const Text('건너뛰기'),
                        ),
                      ),
              ),
            ),
          ),
          // 하단 페이지 인디케이터 + CTA (그래픽 카드 아래, 중앙 정렬).
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.content,
                  0,
                  AppSpacing.content,
                  AppSpacing.content,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PageIndicator(
                      count: _slides.length,
                      current: _page,
                      reduceMotion: reduceMotion,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // 마지막 페이지에서만 '시작하기'를 페이드인(2026-08-09 QA). 그 전 페이지에서도
                    // 버튼 높이만큼 자리는 유지해 인디케이터가 튀지 않게 하고, 안 보일 땐 탭도 막는다.
                    AnimatedOpacity(
                      opacity: isLast ? 1 : 0,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      child: IgnorePointer(
                        ignoring: !isLast,
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _finishing ? null : _complete,
                            child: _finishing
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onPrimary,
                                    ),
                                  )
                                : const Text('시작하기'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 페이지 인디케이터 — 현재 페이지는 브랜드 핑크 확장 pill, 나머지는 연회색 30%.
/// 스와이프/탭 시 너비·색이 부드럽게 전환된다.
class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.count,
    required this.current,
    required this.reduceMotion,
  });

  final int count;
  final int current;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${current + 1}/$count 페이지',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < count; index++)
            AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: index == current ? 18 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
              decoration: BoxDecoration(
                color: index == current
                    ? AppColors.primary
                    : AppColors.mutedSoft.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
        ],
      ),
    );
  }
}
