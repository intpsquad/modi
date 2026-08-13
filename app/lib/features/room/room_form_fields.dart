import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// 방 만들기(S-10)·현재 방 설정(S-40-A)이 **동일한 입력 디자인**을 쓰도록 공용화한 폼 컴포넌트.
/// 토스풍 소프트필 — 라벨 + 테두리 없는 채움 입력(포커스 시 primary 얇은 보더).

/// 라벨 + 소프트필 텍스트 입력. [fieldKey]로 내부 [TextField]에 키를 달 수 있다(테스트용).
class RoomSoftField extends StatelessWidget {
  const RoomSoftField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.maxLength,
    this.maxLines = 1,
    this.fieldKey,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final int? maxLength;
  final int maxLines;
  final Key? fieldKey;

  OutlineInputBorder _border(BorderSide side) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.control),
    borderSide: side,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          maxLength: maxLength,
          maxLines: maxLines,
          minLines: maxLines > 1 ? 3 : 1,
          style: AppTypography.body,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTypography.body.copyWith(color: AppColors.mutedSoft),
            filled: true,
            fillColor: AppColors.surfaceStrong,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.base,
            ),
            border: _border(BorderSide.none),
            enabledBorder: _border(BorderSide.none),
            focusedBorder: _border(
              const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// 날짜 선택 카드 — 소프트필 + 값·달력/▼ 아이콘 + (선택) 하단 안내 마이크로카피.
class RoomDateField extends StatelessWidget {
  const RoomDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.helperText,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Material(
          color: AppColors.surfaceStrong,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: 18,
              ),
              child: Row(
                children: [
                  Expanded(child: Text(value, style: AppTypography.body)),
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            helperText!,
            style: AppTypography.caption.copyWith(color: AppColors.mutedSoft),
          ),
        ],
      ],
    );
  }
}
