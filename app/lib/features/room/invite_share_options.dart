import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'invite_share.dart';

/// 설정 화면처럼 공유 채널 아이콘을 항상 노출하지 않는 진입점에서 쓰는 선택 시트.
///
/// "더보기"만 OS Native Share Sheet를 열고, 카카오·인스타는 각각의 제약에 맞는
/// 전용 동작을 수행한다.
Future<void> showInviteShareOptions(
  BuildContext context, {
  required InviteShareData invite,
  required ShareInviteFn shareInvite,
  required KakaoInviteShareFn shareKakao,
  required CopyFn copy,
  required LaunchAppFn launchApp,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _InviteShareOptionsSheet(
      hostContext: context,
      invite: invite,
      shareInvite: shareInvite,
      shareKakao: shareKakao,
      copy: copy,
      launchApp: launchApp,
    ),
  );
}

class _InviteShareOptionsSheet extends StatelessWidget {
  const _InviteShareOptionsSheet({
    required this.hostContext,
    required this.invite,
    required this.shareInvite,
    required this.shareKakao,
    required this.copy,
    required this.launchApp,
  });

  final BuildContext hostContext;
  final InviteShareData invite;
  final ShareInviteFn shareInvite;
  final KakaoInviteShareFn shareKakao;
  final CopyFn copy;
  final LaunchAppFn launchApp;

  void _showMessage(String message) {
    if (!hostContext.mounted) return;
    ScaffoldMessenger.of(hostContext)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runKakao(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    try {
      await shareKakao(invite);
    } catch (error) {
      debugPrint('카카오톡 공유를 열지 못했어요: $error');
      _showMessage('카카오톡 공유를 열지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _runInstagram(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    try {
      final opened = await shareInviteToInstagram(
        code: invite.code,
        copy: copy,
        launchApp: launchApp,
      );
      _showMessage(
        opened
            ? '초대 코드를 복사했어요. 인스타그램 DM에서 붙여넣어 주세요.'
            : '초대 코드는 복사됐어요. 인스타그램을 열지 못했으니 DM에 붙여넣어 주세요.',
      );
    } catch (error) {
      debugPrint('초대 코드를 복사하지 못했어요: $error');
      _showMessage('초대 코드를 복사하지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _runMore(BuildContext sheetContext) async {
    // sheetContext는 pop 직후 죽으므로, 시트를 띄운 화면의 hostContext로 앵커를 구한다.
    final origin = inviteShareOrigin(hostContext);
    Navigator.of(sheetContext).pop();
    try {
      await shareInvite(invite.message, sharePositionOrigin: origin);
    } catch (error) {
      debugPrint('공유하기를 열지 못했어요: $error');
      _showMessage('공유하기를 열지 못했어요. 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.content,
          AppSpacing.sm,
          AppSpacing.content,
          AppSpacing.content,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('초대 코드 공유', style: AppTypography.title),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '공유할 채널을 선택해 주세요.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.base),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const _ChannelIcon(
                background: AppColors.kakao,
                icon: Icons.chat_bubble_rounded,
                foreground: AppColors.kakaoLabel,
              ),
              title: const Text('카카오톡'),
              subtitle: const Text('방 카드와 참여하기 버튼으로 공유해요'),
              onTap: () => _runKakao(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const _ChannelIcon(
                background: AppColors.surfaceStrong,
                icon: Icons.camera_alt_rounded,
                foreground: AppColors.foreground,
              ),
              title: const Text('인스타그램'),
              subtitle: const Text('초대 코드를 복사하고 앱을 열어요'),
              onTap: () => _runInstagram(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const _ChannelIcon(
                background: AppColors.surfaceStrong,
                icon: Icons.ios_share,
                foreground: AppColors.foreground,
              ),
              title: const Text('더보기'),
              subtitle: const Text('기기의 기본 공유하기를 열어요'),
              onTap: () => _runMore(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelIcon extends StatelessWidget {
  const _ChannelIcon({
    required this.background,
    required this.icon,
    required this.foreground,
  });

  final Color background;
  final IconData icon;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, color: foreground, size: 20),
    );
  }
}
