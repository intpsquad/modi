import 'package:flutter/material.dart';

import '../../design/todo_checkbox.dart';
import '../../design/tokens.dart';
import 'assignee_avatar.dart';
import 'todos_api.dart';

/// 담당자 다중 선택 바텀시트(홈 전환 시트 디자인 참고) — 투두 추가 시트와 미지정 처리 시트가
/// **같은 시트**를 쓰도록 공용화했다(2026-08-09).
///
/// 핸들 + '담당자' 헤더 + `border-soft` 구분선으로 나눈 멤버 행(아바타 36 + 닉네임 + 체크 24) +
/// 하단 전폭 '완료' 버튼. 완료를 누르면 선택 집합을 돌려주고, 시트를 내리거나 배경을 누르면 null.
///
/// 연타로 시트가 겹쳐 뜨지 않게 하는 가드는 **호출하는 화면의 State**에 둔다(위젯 수명과 함께
/// 정리되고 화면 전환 중 미완료 future로 플래그가 갇히지 않는다). 여기 전역 플래그를 두면
/// 화면이 비정상 폐기될 때 값이 갇혀 이후 열림을 영구히 막을 수 있어 쓰지 않는다.
///
/// [initialSelected]는 복사해 쓰므로 원본을 건드리지 않는다.
Future<Set<String>?> showAssigneePickerSheet({
  required BuildContext context,
  required List<MemberBrief> members,
  required Set<String> initialSelected,
}) {
  final working = {...initialSelected};
  return showModalBottomSheet<Set<String>>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.content,
            AppSpacing.md,
            AppSpacing.content,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              const Text('담당자', style: AppTypography.section),
              const SizedBox(height: AppSpacing.base),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Column(
                    children: [
                      for (var i = 0; i < members.length; i++) ...[
                        if (i > 0)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.borderSoft,
                          ),
                        AssigneeSheetTile(
                          member: members[i],
                          selected: working.contains(members[i].userId),
                          onTap: () => setSheet(() {
                            final id = members[i].userId;
                            if (!working.add(id)) working.remove(id);
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(working),
                  child: const Text('완료'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 담당자 시트 한 행 — 아바타 + 닉네임 + 선택 체크. 리플은 카드 라운드 안에서만 그려진다.
class AssigneeSheetTile extends StatelessWidget {
  const AssigneeSheetTile({
    super.key,
    required this.member,
    required this.selected,
    required this.onTap,
  });

  final MemberBrief member;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            AssigneeAvatar(member: member, size: 36),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(member.nickname, style: AppTypography.title)),
            TodoCheckbox(checked: selected, size: 24),
          ],
        ),
      ),
    );
  }
}
