import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../../routing/app_session.dart';
import 'invite_share.dart';
import 'invite_share_body.dart';
import 'room_session.dart';

/// 방 생성 완료 후 공유 화면에 전달하는 방 정보.
class InviteShareArgs {
  const InviteShareArgs({
    required this.roomId,
    required this.inviteCode,
    this.roomName,
    this.coverImage,
  });

  final int roomId;
  final String inviteCode;
  final String? roomName;
  final String? coverImage;
}

/// S-10-A 초대코드 공유 — 방금 만든 방의 6자리 코드 표시(specs/0004-방-생성-참여.md).
///
/// 완료 체크 그래픽 + 코드 카드(복사) + 외부 공유 3버튼(카카오톡·인스타·더보기) + 홈으로.
class InviteShareScreen extends StatefulWidget {
  InviteShareScreen({
    super.key,
    required this.roomId,
    required this.inviteCode,
    this.roomName,
    this.coverImage,
    RoomSession? roomSession,
    ShareInviteFn? shareInvite,
    KakaoInviteShareFn? shareKakao,
    CopyFn? copy,
    LaunchAppFn? launchApp,
  }) : roomSession = roomSession ?? appRoomSession,
       shareInvite = shareInvite ?? shareInviteText,
       shareKakao = shareKakao ?? shareInviteToKakao,
       copy = copy ?? copyToClipboard,
       launchApp = launchApp ?? launchExternalApp;

  final int roomId;
  final String inviteCode;
  final String? roomName;
  final String? coverImage;
  final RoomSession roomSession;
  final ShareInviteFn shareInvite;
  final KakaoInviteShareFn shareKakao;
  final CopyFn copy;
  final LaunchAppFn launchApp;

  @override
  State<InviteShareScreen> createState() => _InviteShareScreenState();
}

class _InviteShareScreenState extends State<InviteShareScreen> {
  Future<void> _goHome() async {
    appSession.markHasRooms();
    // 방금 만든 방을 "현재 방"으로 전환 — specs/0008-방-전환.md.
    await widget.roomSession.switchRoom(widget.roomId);
    if (!mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                // 콘텐츠를 세로 중앙정렬(2026-08-06 요청) — 내용이 길어 넘치면 스크롤.
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.content,
                      vertical: AppSpacing.xl,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - AppSpacing.xl * 2,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 완료 체크 그래픽
                          Container(
                            width: 72,
                            height: 72,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: AppColors.onPrimary,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const Text(
                            '방이 만들어졌어요',
                            style: AppTypography.display,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            '초대 코드를 팀원에게 공유하세요',
                            style: AppTypography.body.copyWith(
                              color: AppColors.muted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          // 카드는 화면 가장자리에서 ~30px(content 16 + 14) 안쪽으로 살짝 좁힌다.
                          // 본문(코드 카드 + 공유 3버튼)은 홈 초대 시트와 공유한다(#81).
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: InviteShareBody(
                              roomId: widget.roomId,
                              inviteCode: widget.inviteCode,
                              roomName: widget.roomName,
                              coverImage: widget.coverImage,
                              shareInvite: widget.shareInvite,
                              shareKakao: widget.shareKakao,
                              copy: widget.copy,
                              launchApp: widget.launchApp,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            '홈 화면이나 설정 › 방 멤버 관리에서 언제든 다시 볼 수 있어요',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.mutedSoft,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.content,
                  AppSpacing.sm,
                  AppSpacing.content,
                  AppSpacing.content,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _goHome,
                    child: const Text('홈으로'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
