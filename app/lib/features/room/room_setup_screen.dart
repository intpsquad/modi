import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import 'room_session.dart';

/// S-03 방 만들기/참여 허브 — 온보딩 게이트(스킵 불가, specs/0004-방-생성-참여.md).
/// 방 소속 0개일 때 뜨는 중앙 히어로 엠티 스테이트.
///
/// 뒤로가기 정책(2026-08-06 확정): 방 0개 사용자는 라우터 게이트(app_router.dart)에
/// 갇혀 있어 pop할 이전 화면이 없다 → 화면 내 상단 뒤로가기 버튼은 두지 않는다(죽은 버튼).
/// 단 방을 가졌던 적 있는 사용자(returning)에 한해 PopScope를 풀어 안드로이드 시스템
/// back으로 앱을 최소화할 수 있게 한다. 첫 가입 사용자(신규)는 게이트를 그대로 유지(back 차단).
class RoomSetupScreen extends StatefulWidget {
  RoomSetupScreen({super.key, RoomSession? roomSession})
    : roomSession = roomSession ?? appRoomSession;

  final RoomSession roomSession;

  @override
  State<RoomSetupScreen> createState() => _RoomSetupScreenState();
}

class _RoomSetupScreenState extends State<RoomSetupScreen> {
  // 방을 한 번이라도 가진 적 있으면 "방을 다 나감", 아니면 "첫 가입"으로 문구를 가른다.
  // 로드 전 기본값은 첫 가입 문구.
  bool _hadRoomBefore = false;

  @override
  void initState() {
    super.initState();
    widget.roomSession.hasEverEnteredRoom().then((had) {
      if (mounted) setState(() => _hadRoomBefore = had);
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _hadRoomBefore ? '현재 진행 중인 방이 없어요!' : '첫 번째 방을 만들어볼까요?';
    return PopScope(
      // returning(방을 가졌던 사용자)만 시스템 back 허용(안드로이드 앱 최소화).
      // 신규(첫 가입)는 온보딩 게이트 유지 — back 완전 차단.
      canPop: _hadRoomBefore,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
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
        ),
      ),
    );
  }
}
