import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../auth/auth_service.dart';
import '../settings/settings_screens.dart';
import 'room_session.dart';

/// S-12 종료된 방 재시작.
class RestartRoomScreen extends StatefulWidget {
  RestartRoomScreen({
    super.key,
    required this.roomId,
    SettingsApi? api,
    AuthService? authService,
  }) : api = api ?? SettingsApi(),
       authService = authService ?? AuthService();

  final int roomId;
  final SettingsApi api;
  final AuthService authService;

  @override
  State<RestartRoomScreen> createState() => _RestartRoomScreenState();
}

class _RestartRoomScreenState extends State<RestartRoomScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _goal;
  final _detail = TextEditingController();
  late final RoomSummary? _room;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _room = _findRoom();
    _name = TextEditingController(text: _room?.name ?? '');
    _goal = TextEditingController(text: _room?.goal ?? '');
    _startDate = DateTime.now();
    final previousDuration =
        _room?.endDate.difference(_room.startDate).inDays ?? 30;
    _endDate = _startDate.add(Duration(days: previousDuration.clamp(1, 365)));
  }

  RoomSummary? _findRoom() {
    for (final room in appRoomSession.rooms) {
      if (room.id == widget.roomId) return room;
    }
    return null;
  }

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _restart() async {
    final room = _room;
    if (room == null || !(_formKey.currentState?.validate() ?? false)) return;
    if (_startDate.isAfter(_endDate)) {
      setState(() => _error = '시작일은 종료일보다 늦을 수 없어요');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final token = await widget.authService.getIdToken();
      await widget.api.updateRoom(
        token,
        room.id,
        name: _name.text.trim(),
        goal: _goal.text.trim(),
        goalDetail: _detail.text.trim().isEmpty ? null : _detail.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
      );
      await appRoomSession.loadRooms(token);
      await appRoomSession.switchRoom(room.id);
      if (mounted) context.go('/home');
    } catch (_) {
      if (mounted) setState(() => _error = '방을 재시작하지 못했어요');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('방 수정 · 재시작')),
        body: const Center(child: Text('재시작할 방 정보를 찾지 못했어요')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('방 수정 · 재시작')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.content),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.accentWarningBackground,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.replay,
                    size: 20,
                    color: AppColors.accentWarningText,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '기간을 연장하면 방이 다시 진행중이 됩니다.\n기존 멤버와 자료는 그대로 유지돼요.',
                      style: AppTypography.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            const Text('방 이름', style: AppTypography.title),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _name,
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '방 이름을 입력해 주세요' : null,
            ),
            const SizedBox(height: AppSpacing.base),
            const Text('기간 연장', style: AppTypography.title),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _RestartDateField(
                    value: _formatDate(_startDate),
                    onTap: () => _pickDate(true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Text('–'),
                ),
                Expanded(
                  child: _RestartDateField(
                    value: _formatDate(_endDate),
                    onTap: () => _pickDate(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '이전 기간 ${_formatDate(_room.startDate)} – '
              '${_formatDate(_room.endDate)}',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.base),
            const Text('방 목표', style: AppTypography.title),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _goal,
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? '목표를 입력해 주세요' : null,
            ),
            const SizedBox(height: AppSpacing.base),
            const Text('목표 상세 설명', style: AppTypography.title),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(controller: _detail, maxLines: 3),
            const SizedBox(height: AppSpacing.sm),
            const Row(
              children: [
                Icon(Icons.group_outlined, size: 18, color: AppColors.muted),
                SizedBox(width: AppSpacing.sm),
                Text('기존 멤버 구성을 유지합니다', style: AppTypography.caption),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.accentDanger,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            ElevatedButton(
              onPressed: _saving ? null : _restart,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text('재시작하기'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.'
      '${date.day.toString().padLeft(2, '0')}';
}

class _RestartDateField extends StatelessWidget {
  const _RestartDateField({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 16),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(value, style: AppTypography.caption)),
          ],
        ),
      ),
    );
  }
}
