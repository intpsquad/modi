import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../design/confirm_dialog.dart';
import '../../design/modi_bottom_sheet.dart';
import '../../design/tokens.dart';
import 'invite_share.dart';

/// 초대 코드를 가져오는 경계 — 호출부가 자기 API 로 채운다(테스트에서 고정값 주입).
typedef InviteCodeLoader = Future<String> Function();

/// 초대 코드 카드 + 외부 공유 3버튼. **S-10-A 화면과 홈 초대 시트가 같은 본문을 쓴다**
/// (2026-08-31 #81에서 승격 — 그전에는 S-10-A 화면 안의 private 위젯이었다).
///
/// 공유 동작(복사·카카오·인스타·더보기)을 여기서 갖는다. 화면이 셋으로 갈리면 같은 실패
/// 문구·같은 인스타 우회를 세 번 유지해야 한다.
class InviteShareBody extends StatefulWidget {
  const InviteShareBody({
    super.key,
    required this.roomId,
    required this.inviteCode,
    this.roomName,
    this.coverImage,
    ShareInviteFn? shareInvite,
    KakaoInviteShareFn? shareKakao,
    CopyFn? copy,
    LaunchAppFn? launchApp,
  }) : shareInvite = shareInvite ?? shareInviteText,
       shareKakao = shareKakao ?? shareInviteToKakao,
       copy = copy ?? copyToClipboard,
       launchApp = launchApp ?? launchExternalApp;

  final int roomId;
  final String inviteCode;
  final String? roomName;
  final String? coverImage;
  final ShareInviteFn shareInvite;
  final KakaoInviteShareFn shareKakao;
  final CopyFn copy;
  final LaunchAppFn launchApp;

  @override
  State<InviteShareBody> createState() => _InviteShareBodyState();
}

class _InviteShareBodyState extends State<InviteShareBody> {
  InviteShareData get _invite => InviteShareData(
    roomId: widget.roomId,
    code: widget.inviteCode,
    roomName: widget.roomName,
    coverImage: widget.coverImage,
  );

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
        _invite.message,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CodeCard(code: widget.inviteCode, onCopy: _copyCode),
        const SizedBox(height: AppSpacing.xl),
        const Text('외부로 공유하기', style: AppTypography.title),
        const SizedBox(height: AppSpacing.base),
        _ShareRow(
          onKakao: _shareKakao,
          onInstagram: _shareInstagram,
          onMore: _shareSheet,
        ),
      ],
    );
  }
}

/// 홈 아바타 줄의 `+`에서 여는 초대 시트(#81).
///
/// S-10-A 화면과 **같은 본문**([InviteShareBody])을 쓴다 — 코드 카드·복사·공유 3버튼.
/// 코드는 열 때 [codeLoader]로 가져온다(방 생성 직후와 달리 홈에는 코드가 없다).
Future<void> showInviteSheet({
  required BuildContext context,
  required int roomId,
  required InviteCodeLoader codeLoader,
  String? roomName,
  String? coverImage,
}) {
  return showModiSheet<void>(
    context: context,
    builder: (_) => _InviteSheet(
      roomId: roomId,
      codeLoader: codeLoader,
      roomName: roomName,
      coverImage: coverImage,
    ),
  );
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({
    required this.roomId,
    required this.codeLoader,
    this.roomName,
    this.coverImage,
  });

  final int roomId;
  final InviteCodeLoader codeLoader;
  final String? roomName;
  final String? coverImage;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  late Future<String> _code;

  @override
  void initState() {
    super.initState();
    _code = widget.codeLoader();
  }

  void _retry() => setState(() => _code = widget.codeLoader());

  @override
  Widget build(BuildContext context) {
    return ModiBottomSheet(
      title: '팀원 초대하기',
      child: FutureBuilder<String>(
        future: _code,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            // 코드를 못 받으면 공유할 것이 없다 — 본문을 그리지 않고 재시도만 준다.
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Column(
                children: [
                  Text(
                    '초대 코드를 불러오지 못했어요',
                    style: AppTypography.body.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  TextButton(
                    key: const ValueKey('invite-sheet-retry'),
                    onPressed: _retry,
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            );
          }
          return InviteShareBody(
            roomId: widget.roomId,
            inviteCode: snapshot.data!,
            roomName: widget.roomName,
            coverImage: widget.coverImage,
          );
        },
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
