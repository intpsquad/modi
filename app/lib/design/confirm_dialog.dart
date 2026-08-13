import 'package:flutter/material.dart';

import 'tokens.dart';

/// 공용 확인/알림 다이얼로그 — 원형 아이콘 + 타이틀 + 메시지 + 버튼(1~2개).
/// 초대코드 입장 확인·실패 알림·인스타 공유 안내 등에서 같은 셸을 공유한다
/// (2026-08-07 초대코드 입장 확인 모달 디자인에서 추출).
///
/// 반환: 확인 `true` / 취소 `false` / 바깥 탭 등 닫힘 `null`.
/// [cancelLabel]이 null이면 단일 확인 버튼(알림형), 있으면 [취소 | 확인] 2버튼(확인형).
/// [accent]는 아이콘 색(+10% 배경) — 실패 알림은 `accent-danger`. 확인 버튼은 항상 primary.
Future<bool?> showAppConfirmDialog({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String message,
  String confirmLabel = '확인',
  String? cancelLabel,
  Color accent = AppColors.primary,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 28),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              title,
              style: AppTypography.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (cancelLabel == null)
              SizedBox(
                width: double.infinity,
                child: AppDialogButton(
                  label: confirmLabel,
                  background: AppColors.primary,
                  foreground: AppColors.onPrimary,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: AppDialogButton(
                      label: cancelLabel,
                      background: AppColors.surfaceStrong,
                      foreground: AppColors.foreground,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppDialogButton(
                      label: confirmLabel,
                      background: AppColors.primary,
                      foreground: AppColors.onPrimary,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

/// 다이얼로그 하단 버튼 — 채움색/글자색 지정형(design.md 컨트롤 라운드).
class AppDialogButton extends StatelessWidget {
  const AppDialogButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      child: Text(
        label,
        style: AppTypography.button.copyWith(color: foreground),
      ),
    );
  }
}

/// 파괴적 액션 확인 다이얼로그 — 아이콘 없이 제목/메시지/버튼(취소 | 액션).
/// 폭 318(작은 화면에선 축소), 높이는 지정 패딩(상20·제목하8·메시지하20·하단20)으로 잡혀
/// 로그아웃 168·회원탈퇴 188·방나가기 212에 맞는다. 버튼은 318에서 정확히 135×48, 라벨 16/600
/// (취소 #222 / 액션 흰색). 액션 채움색은 [confirmColor](로그아웃=primary, 회원탈퇴·방나가기=accentDanger).
/// [warning]이 있으면 메시지 아래 경고 박스를 넣는다(방 나가기). 반환: 확인 true / 취소·바깥 false·null.
Future<bool?> showActionConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  Color confirmColor = AppColors.primary,
  Widget? warning,
  Key? confirmKey,
  Key? cancelKey,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      // 폭은 318이되, 좁은 화면(예: 320)에서는 여백을 뺀 만큼으로 줄여 오버플로를 막는다.
      final available = MediaQuery.sizeOf(context).width - 40;
      final width = available < 318 ? available : 318.0;
      return Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  title,
                  style: AppTypography.title,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  message,
                  style: AppTypography.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              if (warning != null) ...[
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: warning,
                ),
              ],
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionDialogButton(
                        key: cancelKey,
                        label: '취소',
                        background: AppColors.surfaceStrong,
                        foreground: AppColors.foreground,
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _ActionDialogButton(
                        key: confirmKey,
                        label: confirmLabel,
                        background: confirmColor,
                        foreground: AppColors.onPrimary,
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    },
  );
}

/// 파괴적 확인 다이얼로그 버튼 — 높이 48(폭은 부모 Expanded), 라벨 16/600.
class _ActionDialogButton extends StatelessWidget {
  const _ActionDialogButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.button.copyWith(
            fontWeight: FontWeight.w600,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
