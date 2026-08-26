import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../design/confirm_dialog.dart';
import '../../design/tokens.dart';
import '../../routing/app_session.dart';
import 'invite_share.dart';
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
  InviteShareData get _invite => InviteShareData(
    roomId: widget.roomId,
    code: widget.inviteCode,
    roomName: widget.roomName,
    coverImage: widget.coverImage,
  );

  String get _message => _invite.message;

  Future<void> _copyCode() async {
    await widget.copy(widget.inviteCode);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('코드를 복사했어요')));
  }

  Future<void> _shareSheet() async {
    try {
      await widget.shareInvite(
        _message,
        sharePositionOrigin: inviteShareOrigin(context),
      );
    } catch (error) {
      debugPrint('공유하기를 열지 못했어요: $error');
      _showMessage('공유하기를 열지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _shareKakao() async {
    try {
      await widget.shareKakao(_invite);
    } catch (_) {
      _showMessage('카카오톡 공유를 열지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _shareInstagram() async {
    try {
      // 인스타는 "DM 작성+텍스트 프리필" 딥링크가 없어, 코드를 먼저 복사하고 확인 팝업으로
      // "복사됐으니 인스타에서 붙여넣어라"를 안내한 뒤 이동한다(2026-08-07: 갑자기 앱이
      // 열려 오류처럼 보이던 문제 개선 — 입장 확인 모달과 같은 디자인).
      await widget.copy(widget.inviteCode);
      if (!mounted) return;
      final go = await showAppConfirmDialog(
        context: context,
        icon: Icons.content_copy_rounded,
        title: '인스타그램으로 이동할까요?',
        message: '초대 코드를 복사했어요.\n인스타그램에서 DM에 붙여넣어 보낼 수 있어요.',
        cancelLabel: '취소',
        confirmLabel: '이동',
      );
      if (go != true) return;
      final opened = await widget.launchApp('instagram://');
      if (!opened && mounted) {
        _showMessage('인스타그램을 열지 못했어요. 복사된 코드를 DM에 붙여넣어 주세요.');
      }
    } catch (_) {
      _showMessage('초대 코드를 복사하지 못했어요. 다시 시도해 주세요.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

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
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: _CodeCard(
                              code: widget.inviteCode,
                              onCopy: _copyCode,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            '설정 › 방 멤버 관리에서 언제든 다시 볼 수 있어요',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.mutedSoft,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          const Text('외부로 공유하기', style: AppTypography.title),
                          const SizedBox(height: AppSpacing.base),
                          _ShareRow(
                            onKakao: _shareKakao,
                            onInstagram: _shareInstagram,
                            onMore: _shareSheet,
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

/// 초대 코드 카드 — 레이블 + 코드(Jalnan2) + "코드 복사" pill 버튼.
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.onCopy});

  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            '초대 코드',
            style: AppTypography.badge.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(code, style: AppTypography.inviteCode),
          const SizedBox(height: AppSpacing.base),
          Material(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: AppColors.foreground,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text('코드 복사', style: AppTypography.title),
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

/// 외부 공유 아이콘 3종(카카오톡·인스타·더보기) 가로 배치.
class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.onKakao,
    required this.onInstagram,
    required this.onMore,
  });

  final VoidCallback onKakao;
  final VoidCallback onInstagram;
  final VoidCallback onMore;

  // 인스타그램 공식 브랜드 그라데이션(소셜 로그인 브랜드색과 동일한 예외 — design.md §2).
  static const _instaGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFF56040)],
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ShareButton(
          label: '카카오톡',
          background: AppColors.kakao,
          svgAsset: 'assets/icons/kakao_login_symbol.svg',
          icon: Icons.chat_bubble_rounded,
          iconColor: AppColors.kakaoLabel,
          onTap: onKakao,
        ),
        const SizedBox(width: AppSpacing.base),
        _ShareButton(
          label: '인스타',
          gradient: _instaGradient,
          svgAsset: 'assets/icons/insta_symbol.svg',
          icon: Icons.camera_alt_rounded,
          iconColor: AppColors.onPrimary,
          onTap: onInstagram,
        ),
        const SizedBox(width: AppSpacing.base),
        _ShareButton(
          label: '더보기',
          background: AppColors.surfaceStrong,
          icon: Icons.ios_share,
          iconColor: AppColors.foreground,
          onTap: onMore,
        ),
      ],
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.background,
    this.gradient,
    this.svgAsset,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final Color? background;
  final Gradient? gradient;

  /// 있으면 [icon] 대신 이 SVG를 렌더한다(브랜드 글리프 — 예: 인스타).
  final String? svgAsset;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                gradient: gradient,
                shape: BoxShape.circle,
              ),
              child: svgAsset != null
                  ? SvgPicture.asset(
                      svgAsset!,
                      width: 26,
                      height: 26,
                      colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                    )
                  : Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(label, style: AppTypography.caption),
          ],
        ),
      ),
    );
  }
}
