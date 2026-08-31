import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import 'modi_bottom_sheet.dart';
import 'tokens.dart';

/// 시간 선택 휠 시트 — specs/design.md §7(2026-08-31, #80).
///
/// Material `showTimePicker`(시계 다이얼)를 대체한다. 다이얼은 앱 톤과 겉돌았고,
/// 실제로 고르는 동작도 느렸다.
///
/// **취소 버튼이 없다** — scrim 탭이나 스와이프로 닫으면 `null`이 돌아오고 호출부가
/// 기존 값을 지킨다. 참조 디자인과 같고, 시트 규격(design.md §6)이 CTA를 하나만 둔다.
///
/// **선택 칸을 더블탭하면 숫자를 직접 칠 수 있다**(시·분만). 휠로 60칸을 굴리는 것보다
/// 빠른 경우가 있고, Material 피커의 키보드 토글이 사라진 자리를 이것이 메운다.
Future<TimeOfDay?> showTimeWheelSheet({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  return showModiSheet<TimeOfDay>(
    context: context,
    builder: (_) => _TimeWheelSheet(initialTime: initialTime),
  );
}

/// 휠 한 칸 높이. design.md 스페이싱 스케일 밖의 값이라 여기 한 곳에만 둔다 —
/// 휠은 글자가 잘리지 않을 만큼의 높이가 필요해 4px 스케일로는 잡히지 않는다.
const double _itemExtent = 44;

/// 휠 전체 높이 — 가운데 한 칸 + 위아래 두 칸씩이 보이는 크기.
const double _wheelHeight = _itemExtent * 5;

/// 지금 키보드로 편집 중인 휠. 오전·오후는 숫자가 아니라 대상이 아니다.
enum _Editing { none, hour, minute }

class _TimeWheelSheet extends StatefulWidget {
  const _TimeWheelSheet({required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<_TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<_TimeWheelSheet> {
  late int _hour12;
  late int _minute;
  late bool _isPm;

  // ⚠️ `final` 이 아니다 — 편집을 마치면 **새로 만들어 끼운다**(아래 _commitEdit 주석).
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  late final FixedExtentScrollController _periodController;

  _Editing _editing = _Editing.none;
  final _editController = TextEditingController();
  final _editFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final hour = widget.initialTime.hour;
    _isPm = hour >= 12;
    // 0시·12시는 12시로 읽는다(12시간제) — 0을 그대로 두면 휠에 없는 값이 된다.
    _hour12 = hour % 12 == 0 ? 12 : hour % 12;
    _minute = widget.initialTime.minute;

    _hourController = FixedExtentScrollController(initialItem: _hour12 - 1);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
    _periodController = FixedExtentScrollController(initialItem: _isPm ? 1 : 0);

    // 포커스를 잃으면(다른 곳 터치·키보드 내림) 편집을 끝낸다.
    _editFocus.addListener(() {
      if (!_editFocus.hasFocus && _editing != _Editing.none) _commitEdit();
    });
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    _editController.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  /// 휠 값 → 24시간제 [TimeOfDay].
  TimeOfDay get _selected {
    final base = _hour12 % 12; // 12시는 0시로 되돌린다
    return TimeOfDay(hour: _isPm ? base + 12 : base, minute: _minute);
  }

  void _startEdit(_Editing target) {
    final current = target == _Editing.hour ? _hour12 : _minute;
    setState(() {
      _editing = target;
      _editController.text = '$current';
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
    _editFocus.requestFocus();
  }

  /// 친 값을 휠에 반영하고 편집을 끝낸다.
  ///
  /// **범위를 넘는 값은 거부하지 않고 잘라 맞춘다**(13시 → 12시, 99분 → 59분).
  /// 입력을 막으면 왜 안 먹는지 알 수 없어 더 답답하다. 빈 값·숫자가 아니면 기존 값을 지킨다.
  void _commitEdit() {
    final target = _editing;
    if (target == _Editing.none) return;
    final typed = int.tryParse(_editController.text.trim());

    setState(() {
      _editing = _Editing.none;
      if (typed == null) return;
      // ⚠️ `jumpToItem` 으로는 안 된다. 편집 중에는 피커 자리에 입력창이 있어 컨트롤러가
      // **detach 상태**라 점프가 먹지 않고, 피커가 다시 그려질 때 생성 시점의
      // initialItem(편집 전 값)으로 되돌아간다. 그래서 컨트롤러를 새로 만들어 끼운다.
      if (target == _Editing.hour) {
        _hour12 = typed.clamp(1, 12);
        _hourController.dispose();
        _hourController = FixedExtentScrollController(initialItem: _hour12 - 1);
      } else {
        _minute = typed.clamp(0, 59);
        _minuteController.dispose();
        _minuteController = FixedExtentScrollController(initialItem: _minute);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ModiBottomSheet(
      title: '시간 선택',
      button: ElevatedButton(
        key: const ValueKey('time-wheel-confirm'),
        onPressed: () {
          // 키보드가 떠 있는 채로 완료를 누르면 친 값이 버려지므로 먼저 반영한다.
          _commitEdit();
          Navigator.of(context).pop(_selected);
        },
        child: const Text('완료'),
      ),
      child: SizedBox(
        height: _wheelHeight,
        child: Row(
          children: [
            Expanded(
              child: _Wheel(
                wheelKey: const ValueKey('time-wheel-hour'),
                fieldKey: const ValueKey('time-wheel-hour-field'),
                controller: _hourController,
                labels: [for (var h = 1; h <= 12; h++) '$h'],
                onSelected: (index) => setState(() => _hour12 = index + 1),
                isEditing: _editing == _Editing.hour,
                onDoubleTap: () => _startEdit(_Editing.hour),
                editController: _editController,
                editFocus: _editFocus,
                onEditSubmitted: _commitEdit,
                maxLength: 2,
              ),
            ),
            Expanded(
              child: _Wheel(
                wheelKey: const ValueKey('time-wheel-minute'),
                fieldKey: const ValueKey('time-wheel-minute-field'),
                controller: _minuteController,
                // 1분 단위(2026-08-31 확정) — 기존에 저장된 값이 어떤 분이든 휠이 가리킬 수 있다.
                labels: [
                  for (var m = 0; m < 60; m++) m.toString().padLeft(2, '0'),
                ],
                onSelected: (index) => setState(() => _minute = index),
                isEditing: _editing == _Editing.minute,
                onDoubleTap: () => _startEdit(_Editing.minute),
                editController: _editController,
                editFocus: _editFocus,
                onEditSubmitted: _commitEdit,
                maxLength: 2,
              ),
            ),
            Expanded(
              child: _Wheel(
                wheelKey: const ValueKey('time-wheel-period'),
                controller: _periodController,
                // AM/PM 이 아니라 우리말 — 고른 뒤 화면에 보이는 값
                // (`formatTimeOfDayKorean`)과 같은 말이어야 한다(2026-08-31 확정).
                labels: const ['오전', '오후'],
                onSelected: (index) => setState(() => _isPm = index == 1),
                // 숫자가 아니므로 직접 입력 대상이 아니다.
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 휠 한 줄 — 가운데 선택 칸만 강조하고 나머지는 흐리게.
///
/// [onDoubleTap]이 있으면 선택 칸을 더블탭해 숫자를 직접 칠 수 있다.
class _Wheel extends StatelessWidget {
  const _Wheel({
    required this.wheelKey,
    required this.controller,
    required this.labels,
    required this.onSelected,
    this.fieldKey,
    this.isEditing = false,
    this.onDoubleTap,
    this.editController,
    this.editFocus,
    this.onEditSubmitted,
    this.maxLength,
  });

  final Key wheelKey;
  final Key? fieldKey;
  final FixedExtentScrollController controller;
  final List<String> labels;
  final ValueChanged<int> onSelected;
  final bool isEditing;
  final VoidCallback? onDoubleTap;
  final TextEditingController? editController;
  final FocusNode? editFocus;
  final VoidCallback? onEditSubmitted;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTypography.title.copyWith(
      color: AppColors.foreground,
    );

    // ⚠️ 선택 칸 배경은 **피커 뒤에** 깐다. `selectionOverlay` 로 넘기면 자식 위에
    // 그려져서 불투명 색이 선택된 값을 통째로 가린다(#80 실기 확인에서 잡았다 —
    // 위젯 테스트는 페인트 순서를 안 보므로 find.text 로는 안 걸린다).
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                height: _itemExtent,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
              ),
            ),
          ),
          if (isEditing)
            Center(
              // ⚠️ 높이를 _itemExtent 로 고정하지 않는다. 고정하면 TextField 가 그 안에서
              // **위쪽 정렬**이라 더블탭하는 순간 숫자가 제자리에서 위로 튄다(실기 확인).
              // 내용 높이 그대로 두고 바깥 Center 가 선택 칸 한가운데에 놓는다.
              child: IntrinsicWidth(
                child: TextField(
                  key: fieldKey,
                  controller: editController,
                  focusNode: editFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: maxLength,
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  style: labelStyle,
                  onSubmitted: (_) => onEditSubmitted?.call(),
                  // 휠 바깥 어디든 터치하면 키보드가 내려가고 편집이 끝난다.
                  // TapRegion 기반이라 **필드 안쪽 탭은 걸리지 않는다** — 직접
                  // GestureDetector 를 씌우면 필드를 누를 때도 함께 닫힌다.
                  onTapOutside: (_) => editFocus?.unfocus(),
                  // ⚠️ 전역 inputDecorationTheme 을 **전부** 꺼야 한다. `border` 만
                  // 끄면 filled:true + fillColor:surface(흰색) 와 enabled/focused
                  // 테두리가 남아, 회색 칸 위에 흰 둥근 사각형이 덧대어진다.
                  // 여기서는 선택 칸(회색 배경) 위에서 글자만 바뀌어야 한다.
                  decoration: const InputDecoration(
                    counterText: '',
                    filled: false,
                    fillColor: Color(0x00000000),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
            )
          else
            CupertinoPicker(
              key: wheelKey,
              scrollController: controller,
              itemExtent: _itemExtent,
              onSelectedItemChanged: onSelected,
              backgroundColor: const Color(0x00000000),
              // 배경을 뒤에 깔았으므로 기본 오버레이(회색 띠·구분선)는 끈다.
              selectionOverlay: const SizedBox.shrink(),
              children: [
                for (final label in labels)
                  Center(child: Text(label, style: labelStyle)),
              ],
            ),
        ],
      ),
    );
  }
}
