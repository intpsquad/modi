import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../design/time_wheel_sheet.dart';
import 'schedule_api.dart';
import 'schedule_time_format.dart';

/// S-20-B(생성)/S-20-A(수정) 공용 폼 시트 — specs/0009-일정-탭.md.
/// [initial]이 있으면 수정 모드(제목 하단 '일정 삭제' 링크), 없으면 생성 모드.
/// 시작 날짜는 기본 [date](또는 initial.date)이지만 "기간" 행에서 시작·종료
/// 날짜를 함께 편집할 수 있다(2026-08-04 사용자 요청 — 종료일·종료시간 지원).
class ScheduleFormSheet extends StatefulWidget {
  const ScheduleFormSheet({
    super.key,
    required this.date,
    this.initial,
    required this.onSubmit,
    this.onDelete,
  });

  final DateTime date;
  final ScheduleItem? initial;
  final Future<void> Function({
    required String title,
    required DateTime date,
    String? time,
    DateTime? endDate,
    String? endTime,
    String? detail,
    String? place,
  })
  onSubmit;
  final Future<void> Function()? onDelete;

  @override
  State<ScheduleFormSheet> createState() => _ScheduleFormSheetState();
}

class _ScheduleFormSheetState extends State<ScheduleFormSheet> {
  late final _titleController = TextEditingController(
    text: widget.initial?.title ?? '',
  );
  late final _detailController = TextEditingController(
    text: widget.initial?.detail ?? '',
  );
  late DateTime _date = widget.initial?.date ?? widget.date;
  DateTime? _endDate;
  TimeOfDay? _time;
  TimeOfDay? _endTime;
  String? _place;
  bool _loading = false;
  String? _errorText;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _time = _parseTime(widget.initial?.time);
    _endTime = _parseTime(widget.initial?.endTime);
    _endDate = widget.initial?.endDate;
    final rawPlace = widget.initial?.place?.trim();
    if (rawPlace != null && rawPlace.isNotEmpty) {
      _place = rawPlace;
    }
  }

  static TimeOfDay? _parseTime(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimeWheelSheet(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() => _time = picked);
  }

  /// 시작 시간을 지우면 종료 시간도 함께 지운다 — 종료 시간은 시작 시간이
  /// 있어야 설정 가능하다(서버 검증 규칙과 동일).
  void _clearTime() => setState(() {
    _time = null;
    _endTime = null;
  });

  Future<void> _pickEndTime() async {
    final picked = await showTimeWheelSheet(
      context: context,
      initialTime: _endTime ?? _time ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() => _endTime = picked);
  }

  Future<void> _pickDateRange() async {
    final firstDate = DateTime(_date.year - 2, _date.month, _date.day);
    final lastDate = DateTime(_date.year + 5, _date.month, _date.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: DateTimeRange(start: _date, end: _endDate ?? _date),
    );
    if (picked == null) return;
    final start = _dateOnly(picked.start);
    final end = _dateOnly(picked.end);
    setState(() {
      _date = start;
      // endDate와 date가 같으면 단일일 표현으로 정규화한다(서버와 동일 규칙).
      _endDate = end.isAtSameMomentAs(start) ? null : end;
    });
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _pickPlace() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _PlaceInputDialog(initial: _place),
    );
    if (result == null) return;
    setState(() => _place = result.isEmpty ? null : result);
  }

  /// 서버 `ScheduleService.validateRange`와 동일한 규칙을 제출 전에 미리
  /// 확인해 불필요한 왕복 없이 바로 인라인 에러를 보여준다.
  String? _validateRange() {
    final endDate = _endDate;
    if (endDate != null && endDate.isBefore(_date)) {
      return '종료 날짜는 시작 날짜보다 빠를 수 없어요';
    }
    final time = _time;
    final endTime = _endTime;
    if (endTime != null) {
      if (time == null) {
        return '종료 시간을 설정하려면 시작 시간을 먼저 설정해야 해요';
      }
      final sameDay = endDate == null;
      final timeMinutes = time.hour * 60 + time.minute;
      final endMinutes = endTime.hour * 60 + endTime.minute;
      if (sameDay && endMinutes <= timeMinutes) {
        return '종료 시간은 시작 시간보다 늦어야 해요';
      }
    }
    return null;
  }

  String? _timeString(TimeOfDay? time) => time == null
      ? null
      : '${time.hour.toString().padLeft(2, '0')}:'
            '${time.minute.toString().padLeft(2, '0')}:00';

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorText = '제목을 입력해 주세요');
      return;
    }
    final rangeError = _validateRange();
    if (rangeError != null) {
      setState(() => _errorText = rangeError);
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await widget.onSubmit(
        title: title,
        date: _date,
        time: _timeString(_time),
        endDate: _endDate,
        endTime: _timeString(_endTime),
        detail: _detailController.text.trim().isEmpty
            ? null
            : _detailController.text.trim(),
        place: _place,
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

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이 일정을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '삭제',
              style: TextStyle(color: AppColors.accentDanger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await widget.onDelete!();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = '삭제하지 못했어요. 다시 시도해 주세요';
      });
    }
  }

  /// "M월 D일 일정 …" 시트 제목.
  String get _sheetTitle =>
      '${_date.month}월 ${_date.day}일 일정 ${_isEdit ? '수정' : '추가'}';

  /// "기간" 행 값 — 단일일이면 "M월 D일", 다중일이면 "M월 D일 - M월 D일".
  String get _periodLabel {
    final start = '${_date.month}월 ${_date.day}일';
    final endDate = _endDate;
    if (endDate == null) return start;
    return '$start - ${endDate.month}월 ${endDate.day}일';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 키보드가 뜨면 그만큼 시트를 밀어 올린다.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        // 하단 시스템 인셋(안드로이드 네비바·홈 인디케이터)을 흡수해 방 전환 시트처럼
        // 하단바와 겹치지 않게 한다. 키보드가 뜨면 viewInsets가 이미 밀어 올려
        // SafeArea 하단 인셋이 0이 되므로 이중 여백은 없다.
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.content,
            right: AppSpacing.content,
            top: AppSpacing.sm,
            bottom: AppSpacing.content,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 그리퍼 핸들.
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.content),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                Text(_sheetTitle, style: AppTypography.section),
                const SizedBox(height: AppSpacing.content),
                TextField(
                  controller: _titleController,
                  enabled: !_loading,
                  maxLength: 50,
                  style: AppTypography.title,
                  decoration: const InputDecoration(hintText: '제목'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _detailController,
                  enabled: !_loading,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(hintText: '메모'),
                ),
                const SizedBox(height: AppSpacing.content),
                // 기간·시간·종료·장소 그룹 박스.
                //
                // ⚠️ `width: double.infinity`가 필요하다. 바깥 Column이
                // `crossAxisAlignment.start`라 자식에게 **loose** 가로 제약을 주는데, 그러면 이
                // Container가 내용 폭으로 줄어들고 안쪽 Row의 `Spacer()`가 0이 되어 라벨과 값이
                // 붙어버린다(2026-08-05 실측: 꺽쇠가 오른쪽 끝 368이 아니라 325에 있었다).
                // 전폭으로 만들면 기존 _SheetRow의 Spacer가 그대로 space-between이 된다.
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    // 행이 박스 폭을 꽉 채워야 _SheetRow의 Spacer가 space-between이 된다.
                    // 기본값(center)은 자식에게 loose 제약을 줘서 행이 내용 폭으로 줄어든다.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SheetRow(
                        label: '기간',
                        value: _periodLabel,
                        isPlaceholder: false,
                        onTap: _loading ? null : _pickDateRange,
                      ),
                      const Divider(height: 1, indent: AppSpacing.content),
                      _SheetRow(
                        label: '시간',
                        value: _time == null
                            ? '종일'
                            : formatTimeOfDayKorean(_time!),
                        isPlaceholder: _time == null,
                        onTap: _loading ? null : _pickTime,
                        onClear: (_time == null || _loading)
                            ? null
                            : _clearTime,
                      ),
                      // 종료 시간은 시작 시간이 있어야 설정 가능하므로, 시작 시간이
                      // 없을 때는 행 자체를 감춰 서버 제약을 UI로 드러낸다.
                      if (_time != null) ...[
                        const Divider(height: 1, indent: AppSpacing.content),
                        _SheetRow(
                          label: '종료',
                          value: _endTime == null
                              ? '미설정'
                              : formatTimeOfDayKorean(_endTime!),
                          isPlaceholder: _endTime == null,
                          onTap: _loading ? null : _pickEndTime,
                          onClear: (_endTime == null || _loading)
                              ? null
                              : () => setState(() => _endTime = null),
                        ),
                      ],
                      const Divider(height: 1, indent: AppSpacing.content),
                      _SheetRow(
                        label: '장소',
                        value: _place ?? '미지정',
                        isPlaceholder: _place == null,
                        onTap: _loading ? null : _pickPlace,
                        onClear: (_place == null || _loading)
                            ? null
                            : () => setState(() => _place = null),
                      ),
                    ],
                  ),
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
                const SizedBox(height: AppSpacing.content),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
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
                        : Text(_isEdit ? '저장' : '추가하기'),
                  ),
                ),
                if (_isEdit) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: TextButton(
                      onPressed: _loading ? null : _confirmDelete,
                      child: const Text(
                        '일정 삭제',
                        style: TextStyle(color: AppColors.accentDanger),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 장소 자유 텍스트 입력 다이얼로그 — 컨트롤러 수명을 자체 State가 관리한다
/// (호출부에서 await 직후 dispose하면 닫힘 애니메이션 중 참조돼 에러).
class _PlaceInputDialog extends StatefulWidget {
  const _PlaceInputDialog({this.initial});

  final String? initial;

  @override
  State<_PlaceInputDialog> createState() => _PlaceInputDialogState();
}

class _PlaceInputDialogState extends State<_PlaceInputDialog> {
  late final _controller = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('장소'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 100,
        decoration: const InputDecoration(hintText: '장소를 입력해 주세요'),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('확인'),
        ),
      ],
    );
  }
}

/// 그룹 박스 안의 선택 행 — 라벨 + 값(미설정 시 muted) + (해제) + chevron.
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.label,
    required this.value,
    required this.isPlaceholder,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final bool isPlaceholder;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        // 세로 14 = 입력 필드(theme.dart inputDecorationTheme)와 동일한 컨트롤
        // 높이 — 위 제목/메모 TextField와 행 높이를 맞춘다.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.content,
          vertical: 14,
        ),
        child: Row(
          children: [
            Text(label, style: AppTypography.body),
            // ⚠️ `Spacer()` + `Flexible(값)`을 함께 쓰면 **둘 다 flex라 남는 공간을 반씩
            // 나눠 갖고**, loose인 값 쪽에서 남은 몫이 꺽쇠 **뒤에** 쌓여 값·꺽쇠가 가운데에
            // 붕 뜬다(2026-08-05 실측: 꺽쇠 오른쪽이 367이어야 하는데 260에 있었다).
            // 값 하나만 Expanded로 두고 오른쪽 정렬하면 라벨=왼쪽, 값+꺽쇠=오른쪽이 된다.
            Expanded(
              child: Text(
                value,
                style: AppTypography.body.copyWith(
                  color: isPlaceholder ? AppColors.muted : AppColors.foreground,
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(Icons.close, size: 18, color: AppColors.muted),
                ),
              ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
