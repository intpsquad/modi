import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../../routing/app_session.dart';
import '../auth/auth_service.dart';
import 'room_api.dart';
import 'room_session.dart';

/// S-11 초대코드 입력 — specs/0004-방-생성-참여.md.
/// 코드는 6자 영숫자(소문자는 자동 대문자 변환). 6칸이 다 차면 "참여하기"가 활성화되고,
/// 성공 시 방 정보를 보여주는 확인 모달을 거쳐 참여를 확정한다.
class JoinRoomScreen extends StatefulWidget {
  JoinRoomScreen({
    super.key,
    RoomApi? api,
    AuthService? authService,
    RoomSession? roomSession,
    this.initialInviteCode,
  }) : api = api ?? RoomApi(),
       authService = authService ?? AuthService(),
       roomSession = roomSession ?? appRoomSession;

  final RoomApi api;
  final AuthService authService;
  final RoomSession roomSession;
  final String? initialInviteCode;

  static const codeLength = 6;

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _codeController.text = _normalizeCode(widget.initialInviteCode);
    // 코드 길이·포커스가 바뀌면 입력 박스와 하단 CTA 활성 상태를 다시 그린다.
    _codeController.addListener(_onCodeChanged);
    _codeFocusNode.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeFocusNode.removeListener(_onCodeChanged);
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  void _onCodeChanged() => setState(() {});

  bool get _codeComplete =>
      _codeController.text.length == JoinRoomScreen.codeLength;

  String _normalizeCode(String? code) {
    final normalized = (code ?? '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toUpperCase();
    return normalized.length <= JoinRoomScreen.codeLength
        ? normalized
        : normalized.substring(0, JoinRoomScreen.codeLength);
  }

  /// 클립보드의 코드를 붙여넣는다 — 정규화(영숫자·대문자·6자)해서 채운다.
  /// PIN 스타일 입력이라 길게 눌러 붙여넣기가 안 돼서 명시적 버튼으로 제공한다.
  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final normalized = _normalizeCode(data?.text);
    if (!mounted) return;
    if (normalized.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('붙여넣을 코드가 없어요')));
      return;
    }
    _codeController.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
    _codeFocusNode.requestFocus();
  }

  Future<void> _handleJoinPressed() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != JoinRoomScreen.codeLength) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    // 실패 시 스피너를 먼저 끈 뒤 알림 팝업을 띄우려고, 에러 내용을 담아 두고 finally 뒤에서 표시한다.
    _JoinNotice? notice;
    try {
      final idToken = await widget.authService.getIdToken();
      final preview = await widget.api.previewInvite(idToken, code);
      if (!mounted) return;
      final confirmed = await _showConfirmDialog(preview);
      if (confirmed != true) return;

      await widget.api.joinRoom(idToken, code);
      if (!mounted) return;
      appSession.markHasRooms();
      // 방금 참여한 방을 "현재 방"으로 전환 — specs/0008-방-전환.md.
      await widget.roomSession.switchRoom(preview.roomId);
      if (!mounted) return;
      context.go('/home');
    } on InviteNotFoundException {
      notice = const _JoinNotice(
        icon: Icons.search_off_rounded,
        title: '코드를 찾을 수 없어요',
        message: '코드가 없거나 만료됐어요.\n방 멤버에게 새 코드를 요청하세요',
      );
    } on RoomEndedException {
      notice = const _JoinNotice(
        icon: Icons.event_busy_rounded,
        title: '종료된 방이에요',
        message: '이미 종료된 방에는 참여할 수 없어요',
      );
    } catch (e) {
      notice = const _JoinNotice(
        icon: Icons.error_outline_rounded,
        title: '참여하지 못했어요',
        message: '잠시 후 다시 시도해 주세요',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    if (notice != null && mounted) await _showNoticeDialog(notice);
  }

  Future<bool?> _showConfirmDialog(InvitePreview preview) {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                '${preview.name}에 참여하시겠습니까?',
                style: AppTypography.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _confirmMeta(preview),
                style: AppTypography.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: '취소',
                      background: AppColors.surfaceStrong,
                      foreground: AppColors.foreground,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _DialogButton(
                      label: '참여하기',
                      background: AppColors.primary,
                      foreground: AppColors.onPrimary,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 참여 실패 알림 팝업 — 확인 모달과 같은 셸에 accentDanger 아이콘 + 단일 "확인" 버튼.
  Future<void> _showNoticeDialog(_JoinNotice notice) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentDanger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  notice.icon,
                  color: AppColors.accentDanger,
                  size: 28,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              Text(
                notice.title,
                style: AppTypography.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                notice.message,
                style: AppTypography.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: _DialogButton(
                  label: '확인',
                  background: AppColors.primary,
                  foreground: AppColors.onPrimary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 모달 메타 — 멤버 수·기간이 오면 "멤버 N명 · 기간", 아직 없으면 목표(goal)로 폴백.
  /// (멤버 수·기간은 preview API 필드 추가 대기 — room_api.dart 참고.)
  String _confirmMeta(InvitePreview preview) {
    final count = preview.memberCount;
    final start = preview.startDate;
    final end = preview.endDate;
    if (count != null && start != null && end != null) {
      return '멤버 $count명 · ${_formatRange(start, end)}';
    }
    return preview.goal;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('초대 코드 입력')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.content,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.xxl),
                    const Center(
                      child: Icon(
                        Icons.vpn_key_rounded,
                        color: AppColors.primary,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const Text(
                      '초대 코드를 입력하세요',
                      style: AppTypography.display,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '팀원에게 받은 6자리 코드를 넣으면\n바로 방에 참여할 수 있어요',
                      style: AppTypography.body.copyWith(
                        color: AppColors.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _CodeInputBoxes(
                      controller: _codeController,
                      focusNode: _codeFocusNode,
                      enabled: !_loading,
                      length: JoinRoomScreen.codeLength,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextButton.icon(
                      onPressed: _loading ? null : _pasteCode,
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      label: const Text('붙여넣기'),
                    ),
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
                  onPressed: (_loading || !_codeComplete)
                      ? null
                      : _handleJoinPressed,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Text('참여하기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "yyyy.MM.dd – MM.dd" (같은 해면 종료는 월·일만, 다른 해면 종료도 연도 포함).
String _formatRange(DateTime start, DateTime end) {
  String fmt(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.'
      '${d.day.toString().padLeft(2, '0')}';
  // 시작·종료 모두 풀 연도로 표기(예: 2026.07.28 – 2026.09.05).
  return '${fmt(start)} – ${fmt(end)}';
}

/// 6칸 영숫자 코드 입력 — 눈에 보이는 박스 위에 투명 [TextField]를 얹어 입력을 받는다.
class _CodeInputBoxes extends StatelessWidget {
  const _CodeInputBoxes({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.length,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final int length;

  @override
  Widget build(BuildContext context) {
    final text = controller.text;
    return Stack(
      children: [
        Row(
          children: [
            for (var i = 0; i < length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(child: _box(i, text)),
            ],
          ],
        ),
        Positioned.fill(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: true,
            maxLength: length,
            showCursor: false,
            enableInteractiveSelection: false,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            textAlignVertical: TextAlignVertical.center,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
              LengthLimitingTextInputFormatter(length),
              UpperCaseTextFormatter(),
            ],
            style: const TextStyle(color: Colors.transparent, height: 0.01),
            cursorColor: Colors.transparent,
            decoration: const InputDecoration(
              counterText: '',
              filled: false,
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  Widget _box(int index, String text) {
    final filled = index < text.length;
    // 현재 입력 위치(다음에 채워질 칸)에 포커스 보더.
    final isCurrent =
        focusNode.hasFocus && index == text.length && text.length < length;
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.borderSoft,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: isCurrent
            ? Border.all(color: AppColors.primary, width: 1.5)
            : null,
      ),
      child: Text(filled ? text[index] : '', style: AppTypography.display),
    );
  }
}

/// 확인 모달의 균등폭 액션 버튼(취소/참여하기).
class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      child: Text(
        label,
        style: AppTypography.button.copyWith(color: foreground),
      ),
    );
  }
}

/// 참여 실패 알림 팝업의 표시 내용(아이콘/제목/메시지).
class _JoinNotice {
  const _JoinNotice({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
