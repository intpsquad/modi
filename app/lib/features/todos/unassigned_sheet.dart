import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'assignee_picker_sheet.dart';
import 'todos_api.dart';

/// S-17 미지정 처리 — specs/0006-투두-탭.md. 개별 지정형 리스트: 항목마다 담당자를 지정하면 즉시 목록에서 사라지고,
/// 전체 처리되면 자동으로 닫힌다(0003 확정, 2026-08-04 리디자인에서도 사용자가 이 동작을 유지하기로 확정).
///
/// **닫기 버튼이 없다.** 마지막 항목을 처리하면 스스로 닫히고, 중간에 그만두려면 시트를 내리거나 배경을 누른다
/// (`showModalBottomSheet(showDragHandle: true)` — 손잡이가 그 길을 보여준다).
///
/// ⚠️ **행을 `ListTile` 로 만들지 말 것.** 테마의 `outlinedButtonTheme.minimumSize` 가 너비 무한대
/// (`Size.fromHeight`)라, `ListTile.trailing` 에 버튼을 넣으면 그 무한대가 타일 전체 너비로 굳어
/// `Trailing widget consumes the entire tile width` 로 **시트가 통째로 안 그려졌다**(2026-08-04 실측 —
/// 배너를 눌러도 빈 시트만 떴다). 지금은 `Row` + `Expanded` 라 그 함정 자체가 없다.
class UnassignedSheet extends StatefulWidget {
  const UnassignedSheet({
    super.key,
    required this.initialTodos,
    required this.members,
    required this.onAssign,
  });

  final List<TodoItem> initialTodos;
  final List<MemberBrief> members;
  final Future<void> Function(TodoItem todo, List<String> assigneeUserIds)
  onAssign;

  @override
  State<UnassignedSheet> createState() => _UnassignedSheetState();
}

class _UnassignedSheetState extends State<UnassignedSheet> {
  late final List<TodoItem> _remaining = List.of(widget.initialTodos);

  /// 서버로 보내는 중인 행 — 스피너를 그 행에만 띄우고 다른 행의 메뉴를 잠근다.
  int? _busyId;

  /// 담당자 선택 시트가 떠 있는 동안 true — 연타로 시트가 겹쳐 뜨지 않게(2026-08-09).
  bool _pickerOpen = false;
  String? _errorText;

  Future<void> _assign(TodoItem todo, List<String> assigneeUserIds) async {
    // 담당자를 한 명도 안 고르고 완료했으면 아무것도 하지 않는다(행 유지).
    if (assigneeUserIds.isEmpty) return;
    // `_busyId` 로 다른 행을 잠그지만, setState 가 반영되기 전 같은 프레임의 두 번째
    // 선택은 그걸로 못 막는다 — **`await` 앞에서 동기적으로** 한 번 더 끊는다.
    if (_busyId != null) return;
    _busyId = todo.id;
    setState(() => _errorText = null);
    try {
      await widget.onAssign(todo, assigneeUserIds);
      if (!mounted) return;
      setState(() => _remaining.removeWhere((t) => t.id == todo.id));
      // 전부 처리되면 스스로 닫는다(0003 확정). `isCurrent` 로 **이 시트가 맨 위일 때만** 닫는다 —
      // 지금 경로에서는 메뉴가 이미 pop 된 뒤라 항상 참이지만, 그 보장이 호출 순서에만 있어서
      // 코드만 읽는 사람에게는 안 보인다(2026-08-04 리뷰 P2-9).
      if (_remaining.isEmpty && (ModalRoute.of(context)?.isCurrent ?? false)) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = '담당자 지정에 실패했어요. 다시 시도해 주세요');
    } finally {
      _busyId = null;
      if (mounted) setState(() {});
    }
  }

  /// 시트 최소 높이 — 항목이 적어도 너무 납작하지 않게(2026-08-09).
  static const double _minSheetHeight = 450;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.content,
        right: AppSpacing.content,
        top: AppSpacing.content,
        // 갤럭시 등 하단 제스처/내비 바에 마지막 행이 안 가리게 safe-area 여백을 더한다.
        bottom:
            media.viewInsets.bottom +
            media.viewPadding.bottom +
            AppSpacing.content,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minSheetHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('담당자 미지정', style: AppTypography.section),
                const Spacer(),
                if (_remaining.isNotEmpty)
                  _CountBadge(count: _remaining.length),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              '담당자를 지정하면 개인 진행률에 반영돼요',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: AppSpacing.content),
            if (_errorText != null) ...[
              Text(
                _errorText!,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.accentDanger,
                ),
              ),
              const SizedBox(height: AppSpacing.cardGap),
            ],
            if (_remaining.isEmpty)
              const Text('처리할 미지정 투두가 없어요', style: AppTypography.bodySmall)
            else
              Flexible(child: _buildCard()),
          ],
        ),
      ),
    );
  }

  /// design.md §컴포넌트 카드: `surface` + `border` 1px + `radius.card`. 행 사이만 얇은 구분선.
  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      // 카드 라운드 밖으로 구분선·잉크가 새지 않게 자른다.
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _remaining.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, thickness: 1, color: AppColors.borderSoft),
        itemBuilder: (context, index) => _buildRow(_remaining[index]),
      ),
    );
  }

  /// 🔴 담당자 컨트롤/스피너가 차지하는 높이(탭 영역 최소 44 이상). 스피너 분기가 이 값으로
  /// 자리를 맞춰 지정할 때 행이 튀지 않게 한다.
  static const double _controlHeight = 48;

  /// 행의 '미지정' 컨트롤을 누르면 **투두 추가와 동일한 담당자 선택 바텀시트**를 연다
  /// (2026-08-09 붙어 뜨던 팝업 메뉴 → 공용 바텀시트). 고른 담당자를
  /// 지정하면 행이 사라진다.
  Future<void> _pickForRow(TodoItem todo) async {
    if (_busyId != null || _pickerOpen) return; // 연타로 시트 두 개 방지
    _pickerOpen = true;
    try {
      final picked = await showAssigneePickerSheet(
        context: context,
        members: widget.members,
        initialSelected: const {},
      );
      if (picked == null || !mounted) return; // 취소(시트 내림)
      await _assign(todo, picked.toList());
    } finally {
      _pickerOpen = false;
    }
  }

  Widget _buildRow(TodoItem todo) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.content),
      child: Row(
        children: [
          Expanded(child: Text(todo.title, style: AppTypography.title)),
          const SizedBox(width: AppSpacing.cardGap),
          SizedBox(
            height: _controlHeight,
            child: Center(
              child: _busyId == todo.id
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : _AssigneeTrigger(
                      enabled: _busyId == null,
                      onTap: () => _pickForRow(todo),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 행의 담당자 선택 컨트롤 — 누르면 공용 담당자 선택 바텀시트를 연다(투두 추가와 동일).
/// 값은 담당자를 고르면 행이 사라지므로 항상 "미지정"이다 — 셰브론은 "누르면 고른다"는 표시.
class _AssigneeTrigger extends StatelessWidget {
  const _AssigneeTrigger({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 탭 영역을 넓게(높이 44+) 잡는다(design.md §6·§9). 리플/하이라이트는 없앤다.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Semantics(
        button: true,
        label: '담당자 선택',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ⚠️ 색은 `muted` 다 — `mutedSoft`는 design.md §9 가 비활성 텍스트에만 허용한다.
              // 이건 눌리는 요소라 `muted`(AA 통과)를 쓴다.
              Text(
                '미지정',
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.unfold_more, size: 16, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// 남은 개수 뱃지. design.md §뱃지의 형태(`radius.pill`·타이포 `badge`·패딩 4×10)를 따르되 **색은
/// primary 틴트**다 — 목업이 그 색이고, 같은 틴트 방식을 `CrawlStatusBadge` 가 이미 쓴다.
/// ⚠️ design.md §뱃지에는 primary 변형이 아직 없다(specs/OPEN.md 에 기록).
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '$count개',
        style: AppTypography.badge.copyWith(color: AppColors.primary),
      ),
    );
  }
}
