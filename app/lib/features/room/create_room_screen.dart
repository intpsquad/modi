import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../design/tokens.dart';
import '../auth/auth_service.dart';
import 'invite_share_screen.dart';
import 'room_api.dart';
import 'room_cover_image_field.dart';
import 'room_form_fields.dart';

/// S-10 방 만들기 — 토스 스타일 미니멀 폼(specs/0004-방-생성-참여.md).
/// 필수: 이름(1~30자)·목표. **시작일은 자동으로 오늘**, 종료일은 기본 오늘+4주(변경 가능).
/// 대표 이미지는 선택. 테두리 없는 소프트필 입력 + 하단 고정 CTA(리디자인).
class CreateRoomScreen extends StatefulWidget {
  CreateRoomScreen({
    super.key,
    RoomApi? api,
    AuthService? authService,
    this.coverPicker,
  }) : api = api ?? RoomApi(),
       authService = authService ?? AuthService();

  final RoomApi api;
  final AuthService authService;

  /// 테스트용 이미지 피커 주입(기본 null = image_picker 실제 사용).
  final CoverImagePick? coverPicker;

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _nameController = TextEditingController();
  final _goalController = TextEditingController();

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // 시작일은 화면에 없고 자동으로 오늘. 종료일 기본값은 오늘+4주(사용자 변경 가능).
  late DateTime _endDate = _today().add(const Duration(days: 28));
  String? _coverImage;
  bool _loading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    // 이름·목표가 채워지면 하단 CTA가 활성화되도록 다시 그린다.
    _nameController.addListener(_onChanged);
    _goalController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _goalController.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _canSubmit =>
      _nameController.text.trim().isNotEmpty &&
      _goalController.text.trim().isNotEmpty;

  Future<String> _uploadCover(XFile file) async {
    final idToken = await widget.authService.getIdToken();
    final bytes = await file.readAsBytes();
    return widget.api.uploadCoverImage(
      idToken,
      bytes: bytes,
      filename: file.name,
    );
  }

  Future<void> _pickEndDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: today, // 종료일은 오늘 이후.
      lastDate: DateTime(today.year + 5),
      // 이 화면(풀스크린 push)의 로컬 네비게이터에 띄운다 — 앱 로케일(한국어)이 그대로
      // 적용되고, 위젯북처럼 루트가 다른 앱에서도 한국어로 표시된다.
      useRootNavigator: false,
    );
    if (picked == null) return;
    setState(() => _endDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.length > 30) {
      setState(() => _errorText = '방 이름은 30자 이내로 입력해 주세요');
      return;
    }
    setState(() {
      _errorText = null;
      _loading = true;
    });
    try {
      final idToken = await widget.authService.getIdToken();
      final created = await widget.api.createRoom(
        idToken,
        name: name,
        goal: _goalController.text.trim(),
        startDate: _today(),
        endDate: _endDate,
        coverImage: _coverImage,
      );
      if (!mounted) return;
      context.push(
        '/room/create/invite',
        extra: InviteShareArgs(
          roomId: created.id,
          inviteCode: created.inviteCode,
          roomName: name,
          coverImage: _coverImage,
        ),
      );
    } catch (e) {
      setState(() => _errorText = '방을 만들지 못했어요. 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('방 만들기')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.content,
                  AppSpacing.lg,
                  AppSpacing.content,
                  AppSpacing.content,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('어떤 방을\n만들어볼까요?', style: AppTypography.display),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      '대표 이미지 (선택)',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    RoomCoverImageField(
                      uploadImage: _uploadCover,
                      onChanged: (url) => setState(() => _coverImage = url),
                      pickImage: widget.coverPicker,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    RoomSoftField(
                      label: '방 이름',
                      controller: _nameController,
                      hint: '방 이름을 입력해 주세요',
                      enabled: !_loading,
                      maxLength: 30,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    RoomSoftField(
                      label: '방 목표',
                      controller: _goalController,
                      hint: '팀원들과 함께 달성할 목표를 적어주세요',
                      enabled: !_loading,
                      maxLines: 3,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    RoomDateField(
                      label: '종료 날짜',
                      value: _formatDate(_endDate),
                      onTap: _loading ? null : _pickEndDate,
                      helperText: '기한이 지나면 방이 자동으로 종료 상태로 전환돼요',
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _errorText!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.accentDanger,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.content,
                AppSpacing.sm,
                AppSpacing.content,
                AppSpacing.content,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_loading || !_canSubmit) ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Text('만들기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 입력 컴포넌트(RoomSoftField·RoomDateField)는 room_form_fields.dart로 공용화 —
// 현재 방 설정(S-40-A)과 동일한 디자인을 공유한다.
