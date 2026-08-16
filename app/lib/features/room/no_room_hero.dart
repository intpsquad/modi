import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';

/// "진행 중인 방이 없다" 중앙 히어로 — S-03(온보딩 게이트)과 S-06(홈 방없음 상태)이 함께 쓴다.
///
/// 스펙은 `specs/0004-방-생성-참여.md` 의 "S-03 화면(UI) — 방 없음 허브" 절이고,
/// S-06 은 같은 스펙이 *"게이트 아님, 방 만들기/코드 입력 CTA로 동일 플로우 재진입"* 이라고
/// 못 박아 **같은 화면을 재사용**한다. CTA 전이는 `specs/0003-navigation.md` 전이표
/// (`S-06 CTA → S-10 / S-11`, push).
///
/// 🔴 `design.md` §빈 상태의 공용 [EmptyState] 를 쓰지 않는다 — 그 표가 이 화면을
/// **명시적 예외**로 적어 뒀다("진행 중인 방이 없어요 … 방 만들기·참여 CTA 2개").
/// 여기는 라인 아이콘 + 문구가 아니라 원형 그래픽 + `display` 타이틀 + CTA 2개다.
///
/// 두 화면이 다른 것은 **바깥**뿐이라 이 위젯은 그 둘을 알지 않는다:
/// - S-03 은 이 위젯을 `PopScope` 로 감싸 게이트를 유지하고, 타이틀을 조건부로 넘긴다.
/// - S-06 은 감싸지 않고 타이틀을 고정으로 넘긴다(홈에 도달했다는 건 방을 가졌다는 뜻).
class NoRoomHero extends StatelessWidget {
  const NoRoomHero({super.key, required this.title});

  /// `display` 로 렌더되는 한 줄. 호출자가 맥락에 맞게 넘긴다 —
  /// S-03 은 "첫 번째 방을 만들어볼까요?" / "현재 진행 중인 방이 없어요!",
  /// S-06 은 항상 후자.
  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.content),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.surfaceStrong,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.card_giftcard,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: AppTypography.display,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '팀과 함께할 방을 만들거나, 초대코드로 참여하세요',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.mutedSoft,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.push('/room/create'),
                child: const Text('방 만들기'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => context.push('/room/join'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.foreground,
                textStyle: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('초대코드로 참여하기'),
            ),
          ],
        ),
      ),
    );
  }
}
