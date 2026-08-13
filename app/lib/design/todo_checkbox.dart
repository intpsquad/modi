import 'package:flutter/material.dart';

import 'tokens.dart';

/// 투두 체크박스 — specs/design.md §6(컴포넌트 규격). 미완료=테두리만, 완료=primary 채움+흰 체크.
/// 홈 대시보드(S-04)와 투두 탭(S-15)이 함께 쓰는 공용 위젯.
/// [onTap]이 null이면 읽기전용 — 상태 색(완료=채움/미완료=테두리)은 그대로 보여주되
/// InkWell 없이 탭이 차단된다(멤버 투두 S-30-M, specs/design.md §7 상태 패턴).
/// [enabled]가 false면 완료 권한이 없는 투두(담당자가 있고 내가 담당이 아님, FR-39)로,
/// 미완료 원을 회색(surface-soft)으로 흐리게 표시하고 탭을 차단한다.
class TodoCheckbox extends StatelessWidget {
  const TodoCheckbox({
    super.key,
    required this.checked,
    this.onTap,
    this.size = 44,
    this.borderColor,
    this.enabled = true,
  });

  final bool checked;
  final VoidCallback? onTap;

  /// 히트박스(정사각) 크기. 기본 44(design.md 접근성). 밀집 목록에선 22로 낮춰 쓴다.
  final double size;

  /// 미완료 원 테두리색. null이면 design.md 토큰(border). 정밀 스펙에선 지정해 덮어쓴다.
  final Color? borderColor;

  /// 완료 처리 권한 여부. false면 회색 비활성 표시 + 탭 차단(담당자 전용 투두).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // 비활성(완료 권한 없음) + 미완료 = 회색 채움으로 "잠김"을 드러낸다.
    // 이미 완료된 건은 담당자가 완료한 것이므로 그대로 primary 채움을 보인다.
    final disabledUnchecked = !enabled && !checked;
    final box = SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: checked
                ? AppColors.primary
                : (disabledUnchecked
                      ? AppColors.surfaceSoft
                      : Colors.transparent),
            border: checked
                ? null
                : Border.all(
                    color: borderColor ?? AppColors.border,
                    width: 1.5,
                  ),
          ),
          child: checked
              ? const Icon(Icons.check, size: 14, color: AppColors.onPrimary)
              : null,
        ),
      ),
    );
    final effectiveOnTap = enabled ? onTap : null;
    if (effectiveOnTap == null) {
      // 비활성(완료 권한 없음)일 때는 탭을 흡수해 부모 행의 '상세 열기'로 새지 않게 한다.
      // (enabled인데 onTap만 null인 순수 읽기전용 케이스는 기존대로 탭을 통과시킨다.)
      if (!enabled) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: box,
        );
      }
      return box;
    }
    return InkWell(
      onTap: effectiveOnTap,
      customBorder: const CircleBorder(),
      child: box,
    );
  }
}
