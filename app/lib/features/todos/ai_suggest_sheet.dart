import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'todos_api.dart';

/// S-16 [AI추천추가] 후보 시트 — specs/0006-투두-탭.md, full_spec.md §S-16-B.
/// todo_form_sheet.dart와 동일 구조: 시트는 API를 모르고, 부모가 주입한 콜백만 호출한다.
///
/// 채택은 후보별 [추가] 즉시 생성이고 **시트는 열린 채 유지**된다(0003 확정) — 채택마다 닫으면
/// 다음 후보를 위해 재생성(실측 7~9초 + 크레딧)을 강요하게 되기 때문. 닫기는 사용자가 한다.
class AiSuggestSheet extends StatefulWidget {
  const AiSuggestSheet({
    super.key,
    required this.onFetch,
    required this.onAdopt,
    required this.onCancelAdopt,
    required this.topPadding,
  });

  final Future<List<TodoSuggestionCandidate>> Function() onFetch;

  /// 후보를 채택(생성)하고 **만들어진 투두의 id**를 돌려준다 — 시트에서 바로 취소할 때 쓴다.
  final Future<int> Function(TodoSuggestionCandidate candidate) onAdopt;

  /// 방금 추가한 투두(id)를 되돌린다(삭제). "추가" → "취소" 흐름(2026-08-09).
  final Future<void> Function(int todoId) onCancelAdopt;

  /// 상태바 높이. showModalBottomSheet가 시트 내부 컨텍스트의 top padding을 0으로 지우기
  /// 때문에(useSafeArea:true를 안 쓰는 이 프로젝트 관례), 시트를 여는 쪽 컨텍스트에서 미리
  /// 읽어 전달받는다 — 시트 내부에서 MediaQuery로 다시 읽으면 항상 0이 나온다.
  final double topPadding;

  @override
  State<AiSuggestSheet> createState() => _AiSuggestSheetState();
}

class _AiSuggestSheetState extends State<AiSuggestSheet> {
  bool _loading = true;
  bool _fetchFailed = false;
  List<TodoSuggestionCandidate> _candidates = [];

  /// 채택된 후보 index → 생성된 투두 id. 바로 취소(삭제)할 때 이 id를 쓴다(2026-08-09).
  final Map<int, int> _adoptedTodoIds = {};

  /// 처리 중(추가 또는 취소)인 후보 index — 그 행에 스피너를 띄우고 다른 행을 잠근다.
  int? _busyIndex;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _fetchFailed = false;
      _errorText = null;
    });
    try {
      final candidates = await widget.onFetch();
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _fetchFailed = true;
      });
    }
  }

  Future<void> _adopt(int index) async {
    setState(() {
      _busyIndex = index;
      _errorText = null;
    });
    try {
      final todoId = await widget.onAdopt(_candidates[index]);
      if (!mounted) return;
      setState(() => _adoptedTodoIds[index] = todoId);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = '추가하지 못했어요. 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _busyIndex = null);
    }
  }

  /// 방금 추가한 후보를 되돌린다(생성된 투두 삭제) — 시트에서 바로 "취소"(2026-08-09).
  Future<void> _cancelAdopt(int index) async {
    final todoId = _adoptedTodoIds[index];
    if (todoId == null) return;
    setState(() {
      _busyIndex = index;
      _errorText = null;
    });
    try {
      await widget.onCancelAdopt(todoId);
      if (!mounted) return;
      setState(() => _adoptedTodoIds.remove(index));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = '취소하지 못했어요. 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _busyIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 후보가 많아지면 시트가 화면 최상단까지 자라 상태바를 덮었다(QA 신고). "화면 높이 -
    // 상태바 높이"로 상한을 건다. widget.topPadding을 쓰는 이유는 위 필드 문서 참고 —
    // 여기서 MediaQuery.viewPaddingOf(context).top을 읽으면 시트 내부라 항상 0이 나온다.
    // minHeight는 두지 않는다 — 로딩/에러/빈 상태처럼 내용이 짧을 때는 그대로 내용물 높이로 뜬다.
    final maxHeight = MediaQuery.sizeOf(context).height - widget.topPadding;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      // SafeArea(top:false) — 하단 '닫기' 버튼이 시스템 내비게이션 바(제스처 바·삼성 3버튼)와
      // 겹치지 않게 안전영역만큼 띄운다(2026-08-09 QA 신고). viewInsets.bottom은 키보드만
      // 보정하므로 시스템 바와 무관 — archive_item_register_sheet와 같은 패턴.
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.content,
            right: AppSpacing.content,
            top: AppSpacing.content,
            bottom:
                MediaQuery.of(context).viewInsets.bottom + AppSpacing.content,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI 추천', style: AppTypography.section),
              const SizedBox(height: AppSpacing.content),
              Flexible(child: _buildBody()),
              if (_errorText != null) ...[
                const SizedBox(height: AppSpacing.cardGap),
                Text(
                  _errorText!,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.accentDanger,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.content),
              Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('닫기'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    // design.md §6 상태 패턴: AI/네트워크 로딩은 스피너 + 짧은 문구.
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: AppSpacing.cardGap),
              Text('목표를 분석해 투두를 추천하고 있어요', style: AppTypography.bodySmall),
            ],
          ),
        ),
      );
    }
    if (_fetchFailed) {
      // design.md §6 에러: 안내 문구 + Secondary 버튼("다시 시도").
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('추천을 불러오지 못했어요', style: AppTypography.title),
              const SizedBox(height: AppSpacing.cardGap),
              OutlinedButton(onPressed: _fetch, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }
    if (_candidates.isEmpty) {
      // 서버 계약상 빈 후보는 에러가 아니다(TodoSuggestionResponse javadoc) — 빈 상태 문구.
      //
      // ⚠️ 부제목이 원인을 **단정하지 않는다.** 빈 결과의 원인은 둘인데(자료가 없다 /
      // 이미 추천한 것과 겹친다) 이 시트는 어느 쪽인지 모른다 — 자료 개수가 안 들어온다.
      // 원래 문구는 "아카이브에 자료를 담으면 더 잘 추천할 수 있어요" 하나였는데, 실제로
      // 빈 결과가 나온 주된 원인은 제외 창이 차서였다. 자료를 아무리 담아도 안 풀리는
      // 상황에서 자료를 담으라고 시켰다(`specs/0001-architecture.md`).
      // 그래서 두 행동을 다 제시한다. "잠시 후 다시"는 오래된 노출이 창 밖으로
      // 밀려나면서 실제로 통한다.
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('추천할 투두를 찾지 못했어요', style: AppTypography.title),
              SizedBox(height: AppSpacing.sm),
              Text(
                '자료를 더 담거나, 잠시 후 다시 시도해 주세요',
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _candidates.length,
      itemBuilder: (context, index) => _buildCandidateRow(index),
    );
  }

  Widget _buildCandidateRow(int index) {
    final candidate = _candidates[index];
    final adopted = _adoptedTodoIds.containsKey(index);
    final busy = _busyIndex == index;

    // 카테고리를 **보여주지 않는다** AI 가 카테고리를 정하지 않기로 했고,
    // 채택하면 기타(미분류)로 들어가 사용자가 투두 탭에서 직접 분류한다.
    // 왜 그 기능을 걷어냈는지는 `ai/docs/RESTORE-category-assignment.md`.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Text(candidate.title, style: AppTypography.title)),
          const SizedBox(width: AppSpacing.cardGap),
          if (adopted)
            // 추가한 뒤엔 **취소**로 바뀐다(2026-08-09) — 방금 만든 투두를 시트에서 바로 되돌린다.
            // 취소는 부차 액션이라 **완전 연한 회색**(`color.border`) 텍스트로 눌러 둔다.
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: AppColors.border,
              ),
              onPressed: _busyIndex != null ? null : () => _cancelAdopt(index),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.mutedSoft,
                      ),
                    )
                  : const Text('취소'),
            )
          else
            OutlinedButton(
              // 테마 공통 minimumSize는 너비가 무한대(Size.fromHeight)라 Row 안에서는
              // 레이아웃이 깨진다 — 높이 48만 유지하고 너비 강제는 푼다.
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              // 다른 행이 처리 중일 때는 함께 잠근다 — 연타로 같은 후보가 두 번 생성되는
              // 것을 막는다.
              onPressed: _busyIndex != null ? null : () => _adopt(index),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Text('추가'),
            ),
        ],
      ),
    );
  }
}
