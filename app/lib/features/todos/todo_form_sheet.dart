import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../design/option_menu.dart';
import '../../design/tokens.dart';
import 'assignee_avatar.dart';
import 'assignee_picker_sheet.dart';
import 'todos_api.dart';

enum _DueChoice { none, today, tomorrow, weekend, custom }

enum _ImageSourceChoice { camera, gallery }

/// S-16(투두 추가)/S-18(투두 상세·수정) 공용 폼 — specs/0006-투두-탭.md.
/// [initial]이 있으면 수정 모드, 없으면 생성 모드.
///
/// 2026-08-08 리디자인: 옵션 행 + 피커 방식으로 재구성.
/// 제목/메모 블록 → 정리(카테고리·담당자) → 날짜 및 시간(마감일·중요) → 이미지 추가 → 저장.
/// **이미지는 2026-08-09 저장 연결 완료**(`docs/backend/todo-image-archive-handoff.md`) — 고르면
/// 업로드 후 `imageUrl`로 저장된다. **중요는 여전히 UI만** — 백엔드 `createTodo`가 아직 지원하지
/// 않아 저장되지 않는다(로컬 상태, `docs/backend/todo-form-handoff.md`).
class TodoFormSheet extends StatefulWidget {
  const TodoFormSheet({
    super.key,
    required this.categories,
    required this.members,
    this.initial,
    this.initialCategoryId,
    required this.onSubmit,
    this.showTitle = true,
    this.fullHeight = true,
    this.today,
    this.imagePicker,
    required this.uploadImage,
  });

  final List<Category> categories;
  final List<MemberBrief> members;
  final TodoItem? initial;

  /// 생성 모드에서 미리 선택할 카테고리(해당 카테고리 하단 "＋"로 진입 시). 수정 모드에선 무시.
  final int? initialCategoryId;
  final Future<void> Function({
    required String title,
    String? detail,
    int? categoryId,
    required List<String> assigneeUserIds,
    DateTime? dueDate,
    String? imageUrl,
  })
  onSubmit;

  /// 새로 고른 이미지를 업로드해 공개 URL을 돌려준다(2026-08-09,
  /// docs/backend/todo-image-archive-handoff.md) — 실제 네트워크 호출은 항상 부모가 구현한다
  /// (roomId·idToken이 폼 바깥에 있음). [imagePicker]와 같은 결의 주입점이지만 이건 항상 필요하다.
  final Future<String> Function(List<int> bytes) uploadImage;

  /// 전체화면(수정)에 얹을 때는 AppBar가 제목/높이를 담당하므로 바텀시트 고정 높이를 끈다.
  final bool showTitle;

  /// 바텀시트 높이 정책. true(생성)=상태바 제외 전체 높이, false(수정 시트)=내용물 높이.
  /// `showTitle:false`(전체화면 Scaffold)에서는 무시된다.
  final bool fullHeight;

  /// 마감일 프리셋("오늘/내일/이번 주말")의 기준일. 프로덕션에서는 null이라 `DateTime.now()`를
  /// 쓰고, 테스트만 요일을 고정해 넣는다.
  @visibleForTesting
  final DateTime? today;

  /// 테스트에서 갤러리 접근을 대체하기 위한 주입점. 프로덕션은 기본 [ImagePicker].
  @visibleForTesting
  final Future<XFile?> Function()? imagePicker;

  @override
  State<TodoFormSheet> createState() => _TodoFormSheetState();
}

class _TodoFormSheetState extends State<TodoFormSheet> {
  late final _titleController = TextEditingController(
    text: widget.initial?.title ?? '',
  );
  late final _detailController = TextEditingController(
    text: widget.initial?.detail ?? '',
  );
  late int? _categoryId =
      widget.initial?.categoryId ?? widget.initialCategoryId;
  late final Set<String> _assigneeIds = {
    for (final a in widget.initial?.assignees ?? const <MemberBrief>[])
      a.userId,
  };
  late DateTime? _dueDate = widget.initial?.dueDate == null
      ? null
      : DateUtils.dateOnly(widget.initial!.dueDate!);

  /// 중요는 로컬 전용(백엔드 미지원, 저장 안 됨) — 위 클래스 주석 참고.
  bool _important = false;

  /// 새로 고른 이미지(아직 업로드 전). null이면 이미지를 안 바꾼 것 — 그때는
  /// [_existingImageUrl]을 그대로 유지해 보낸다(전체 교체라 안 보내면 해제되므로).
  XFile? _image;

  /// 수정 모드에서 이미 첨부돼 있던 이미지 — 새로 고르지 않으면 이 값을 그대로 보존한다.
  late final String? _existingImageUrl = widget.initial?.imageUrl;

  // 옵션창(showOptionMenu)을 누른 행 바로 아래에 띄우기 위한 앵커.
  final _categoryRowKey = GlobalKey();
  final _dueRowKey = GlobalKey();
  final _imageBoxKey = GlobalKey();

  bool _loading = false;

  /// 담당자 선택 시트가 떠 있는 동안 true — 연타로 시트가 겹쳐 뜨지 않게(2026-08-09).
  bool _pickerOpen = false;
  String? _errorText;

  DateTime get _today => DateUtils.dateOnly(widget.today ?? DateTime.now());
  DateTime get _tomorrow => _today.add(const Duration(days: 1));

  DateTime get _weekend {
    final daysUntilSaturday = (DateTime.saturday - _today.weekday + 7) % 7;
    return _today.add(
      Duration(days: daysUntilSaturday == 0 ? 7 : daysUntilSaturday),
    );
  }

  bool get _weekendIsTomorrow => _weekend == _tomorrow;

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = '제목을 입력해 주세요');
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      // 새로 고른 이미지가 있으면 업로드해 URL을 얻는다 — 없으면 기존 이미지를 그대로 유지.
      final image = _image;
      final imageUrl = image == null
          ? _existingImageUrl
          : await widget.uploadImage(await image.readAsBytes());
      await widget.onSubmit(
        title: title,
        detail: _detailController.text.trim().isEmpty
            ? null
            : _detailController.text.trim(),
        categoryId: _categoryId,
        assigneeUserIds: _assigneeIds.toList(),
        dueDate: _dueDate,
        imageUrl: imageUrl,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = '저장하지 못했어요. 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── 값 라벨 ───────────────────────────────────────────────
  String get _categoryLabel {
    final id = _categoryId;
    if (id == null) return '기타';
    for (final c in widget.categories) {
      if (c.id == id) return c.name;
    }
    return '기타';
  }

  String get _dueLabel {
    final d = _dueDate;
    if (d == null) return '없음';
    if (d == _today) return '오늘';
    if (d == _tomorrow) return '내일';
    if (!_weekendIsTomorrow && d == _weekend) return '이번 주말';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}.$m.$day';
  }

  List<MemberBrief> get _selectedMembers =>
      widget.members.where((m) => _assigneeIds.contains(m.userId)).toList();

  // ── 피커 (옵션창 = showOptionMenu, 담당자만 체크 팝업) ─────────
  Future<void> _pickCategory() async {
    const otherSentinel = -1; // 기타(null)를 옵션창 값으로 나를 센티넬(양수 id와 안 겹침).
    final picked = await showOptionMenu<int>(
      context: context,
      anchorKey: _categoryRowKey,
      preferAbove: true,
      items: [
        const OptionMenuItem(label: '기타', value: otherSentinel),
        for (final c in widget.categories)
          OptionMenuItem(label: c.name, value: c.id),
      ],
    );
    if (picked == null || !mounted) return; // null = 바깥 탭(닫힘)
    setState(() => _categoryId = picked == otherSentinel ? null : picked);
  }

  Future<void> _pickDueDate() async {
    final picked = await showOptionMenu<_DueChoice>(
      context: context,
      anchorKey: _dueRowKey,
      preferAbove: true,
      items: [
        const OptionMenuItem(label: '없음', value: _DueChoice.none),
        const OptionMenuItem(label: '오늘', value: _DueChoice.today),
        const OptionMenuItem(label: '내일', value: _DueChoice.tomorrow),
        if (!_weekendIsTomorrow)
          const OptionMenuItem(label: '이번 주말', value: _DueChoice.weekend),
        const OptionMenuItem(label: '직접 선택', value: _DueChoice.custom),
      ],
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case _DueChoice.none:
        setState(() => _dueDate = null);
      case _DueChoice.today:
        setState(() => _dueDate = _today);
      case _DueChoice.tomorrow:
        setState(() => _dueDate = _tomorrow);
      case _DueChoice.weekend:
        setState(() => _dueDate = _weekend);
      case _DueChoice.custom:
        await _pickCustomDueDate();
    }
  }

  Future<void> _pickCustomDueDate() async {
    final floor = _today.subtract(const Duration(days: 365));
    final current = _dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? _today,
      firstDate: current != null && current.isBefore(floor) ? current : floor,
      lastDate: _today.add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    setState(() => _dueDate = DateUtils.dateOnly(picked));
  }

  /// 담당자 — 공용 다중 선택 바텀시트([showAssigneePickerSheet], 미지정 처리 시트와 동일).
  /// 완료 시에만 반영. 연타로 시트가 겹쳐 뜨지 않게 [_pickerOpen]으로 잠근다(2026-08-09).
  Future<void> _pickAssignees() async {
    if (_pickerOpen) return;
    _pickerOpen = true;
    try {
      final result = await showAssigneePickerSheet(
        context: context,
        members: widget.members,
        initialSelected: _assigneeIds,
      );
      if (result != null && mounted) {
        setState(() {
          _assigneeIds
            ..clear()
            ..addAll(result);
        });
      }
    } finally {
      _pickerOpen = false;
    }
  }

  Future<void> _pickImage() async {
    final choice = await showOptionMenu<_ImageSourceChoice>(
      context: context,
      anchorKey: _imageBoxKey,
      preferAbove: true,
      items: const [
        OptionMenuItem(
          label: '사진 찍기',
          value: _ImageSourceChoice.camera,
          icon: Icons.photo_camera_outlined,
        ),
        OptionMenuItem(
          label: '갤러리',
          value: _ImageSourceChoice.gallery,
          icon: Icons.photo_library_outlined,
        ),
      ],
    );
    if (choice == null || !mounted) return;
    final source = choice == _ImageSourceChoice.camera
        ? ImageSource.camera
        : ImageSource.gallery;
    final override = widget.imagePicker;
    final XFile? picked = override != null
        ? await override()
        : await ImagePicker().pickImage(source: source);
    if (picked == null || !mounted) return;
    setState(() => _image = picked);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 내용물 높이 시트(수정): Flexible로 내용만큼만, 넘치면 스크롤. 그 외: Expanded로 채움.
    final contentHeightSheet = widget.showTitle && !widget.fullHeight;
    final scrollArea = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.content,
        AppSpacing.sm,
        AppSpacing.content,
        AppSpacing.content,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleMemoBlock(
            titleController: _titleController,
            memoController: _detailController,
            enabled: !_loading,
          ),
          const SizedBox(height: AppSpacing.lg),
          _Section(
            label: '정리',
            child: _OptionBox(
              rows: [
                _OptionRow(
                  label: '카테고리',
                  value: _categoryLabel,
                  anchorKey: _categoryRowKey,
                  onTap: _loading ? null : _pickCategory,
                ),
                _OptionRow(
                  label: '담당자',
                  trailing: _AssigneeTrailing(members: _selectedMembers),
                  onTap: _loading ? null : _pickAssignees,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Section(
            label: '날짜 및 시간',
            child: _OptionBox(
              rows: [
                _OptionRow(
                  label: '마감일',
                  value: _dueLabel,
                  anchorKey: _dueRowKey,
                  onTap: _loading ? null : _pickDueDate,
                ),
                _OptionRow(
                  label: '중요',
                  showChevron: false,
                  // 알림 설정과 동일한 기본 Switch(커스텀 색 없음).
                  trailing: Switch(
                    value: _important,
                    onChanged: _loading
                        ? null
                        : (v) => setState(() => _important = v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ImageAddBox(
            anchorKey: _imageBoxKey,
            hasImage: _image != null || _existingImageUrl != null,
            onTap: _loading ? null : _pickImage,
          ),
          if (_errorText != null) ...[
            const SizedBox(height: AppSpacing.cardGap),
            Text(
              _errorText!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.accentDanger,
              ),
            ),
          ],
        ],
      ),
    );

    // 하단 full-width 저장 버튼, 바닥에서 24px.
    final saveButton = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.content,
        AppSpacing.cardGap,
        AppSpacing.content,
        24,
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          key: const ValueKey('todo-form-submit'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onPrimary,
                  ),
                )
              : const Text('저장'),
        ),
      ),
    );

    final column = Column(
      mainAxisSize: contentHeightSheet ? MainAxisSize.min : MainAxisSize.max,
      children: [
        contentHeightSheet
            ? Flexible(child: scrollArea)
            : Expanded(child: scrollArea),
        saveButton,
      ],
    );

    // 입력 영역 밖(빈 곳)을 탭하면 키보드를 내린다(2026-08-09 요청). translucent라 입력·버튼·
    // 옵션 행의 자체 탭은 그대로 동작하고, 빈 영역 탭만 여기서 포커스를 해제한다.
    final body = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: column,
    );

    // 전체화면(수정, Scaffold)은 부모가 높이를 준다.
    if (!widget.showTitle) return body;
    // 시트: 하단 시스템 내비바(제스처 바)에 저장 버튼이 안 가리게 SafeArea(bottom).
    // 내용물 높이 시트(수정): 내용만큼, 키보드는 viewInsets로 띄움.
    if (contentHeightSheet) {
      return Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SafeArea(top: false, child: body),
      );
    }
    // 전체높이 시트(생성): 상태바 제외 전체 높이. 키보드가 저장 버튼 안 가리게 viewInsets 띄움.
    final height =
        media.size.height - media.viewPadding.top - media.viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: SafeArea(top: false, child: body),
      ),
    );
  }
}

// ── 제목/메모 블록 ─────────────────────────────────────────
class _TitleMemoBlock extends StatelessWidget {
  const _TitleMemoBlock({
    required this.titleController,
    required this.memoController,
    required this.enabled,
  });

  final TextEditingController titleController;
  final TextEditingController memoController;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          // 제목 62 — 하단 white 1px 구분선.
          Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.surface, width: 1),
              ),
            ),
            alignment: Alignment.centerLeft,
            child: TextField(
              key: const ValueKey('todo-form-title'),
              controller: titleController,
              enabled: enabled,
              maxLength: 50,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.foreground,
              ),
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                counterText: '',
                hintText: '새로운 투두',
                hintStyle: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.mutedSoft,
                ),
              ),
            ),
          ),
          // 메모 62 — muted-soft 16.
          Container(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            alignment: Alignment.centerLeft,
            child: TextField(
              key: const ValueKey('todo-form-detail'),
              controller: memoController,
              enabled: enabled,
              maxLength: 500,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 16,
                color: AppColors.mutedSoft,
              ),
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                counterText: '',
                hintText: '메모',
                hintStyle: TextStyle(fontSize: 16, color: AppColors.mutedSoft),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 섹션(라벨 + 옵션박스) ──────────────────────────────────
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

// 흰 옵션박스 — 행 사이 border-soft 1px, 마지막 행은 구분선 없음.
class _OptionBox extends StatelessWidget {
  const _OptionBox({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    // 바깥 stroke도 행 구분선과 같은 border-soft로(2026-08-08 요청).
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(
                          color: AppColors.borderSoft,
                          width: 1,
                        ),
                      ),
              ),
              child: rows[i],
            ),
        ],
      ),
    );
  }
}

// 옵션 행 — 라벨 + (값 텍스트 또는 커스텀 trailing) + 셰브론. h62, padding 14/16.
// 탭 리플/하이라이트 없이(주변이 어두워지지 않게) GestureDetector로 처리한다.
// [anchorKey]는 옵션창(showOptionMenu)을 이 행 바로 아래에 띄우기 위한 앵커.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    this.value,
    this.trailing,
    this.showChevron = true,
    this.onTap,
    this.anchorKey,
  });

  final String label;
  final String? value;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;
  final Key? anchorKey;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      key: anchorKey,
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(label, style: AppTypography.title),
          const Spacer(),
          if (trailing != null)
            trailing!
          else if (value != null)
            Text(
              value!,
              style: AppTypography.body.copyWith(color: AppColors.mutedSoft),
            ),
          if (showChevron) ...[
            const SizedBox(width: 8),
            const Icon(Icons.unfold_more, size: 18, color: AppColors.mutedSoft),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }
}

// 담당자 바텀시트 한 칸 — 아바타 + 이름 + 선택 체크(홈 전환 시트 _RoomTile 참고).
class _AssigneeTrailing extends StatelessWidget {
  const _AssigneeTrailing({required this.members});

  final List<MemberBrief> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Text(
        '없음',
        style: AppTypography.body.copyWith(color: AppColors.mutedSoft),
      );
    }
    final shown = members.take(3).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final m in shown) ...[
          AssigneeAvatar(member: m, size: 26),
          const SizedBox(width: 4),
        ],
        if (members.length > shown.length)
          Text(
            '+${members.length - shown.length}',
            style: AppTypography.caption.copyWith(color: AppColors.mutedSoft),
          ),
      ],
    );
  }
}

// 이미지 추가 — 아웃라인 박스(UI만, 백엔드 미저장). 탭 리플 없음(GestureDetector).
class _ImageAddBox extends StatelessWidget {
  const _ImageAddBox({required this.hasImage, this.onTap, this.anchorKey});

  final bool hasImage;
  final VoidCallback? onTap;
  final Key? anchorKey;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        key: anchorKey,
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Text(
              hasImage ? '이미지 1장 첨부됨' : '이미지 추가',
              style: AppTypography.title.copyWith(color: AppColors.foreground),
            ),
            const Spacer(),
            Icon(
              hasImage ? Icons.check : Icons.add,
              size: 20,
              color: AppColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
