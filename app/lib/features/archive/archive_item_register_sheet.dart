import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../design/option_menu.dart';
import '../../design/tokens.dart';
import 'archive_api.dart';

/// 등록 시트가 열릴 때 어떤 입력을 먼저 보여줄지 — 폴더 목록(S-25-A) ＋ 버튼의 옵션창에서
/// [링크 추가]/[텍스트 추가]/[이미지 추가]를 고르면 그 모드로 시트가 열린다(2026-08-08, 이미지는
/// 2026-08-09 후속 확정 — 폴더 직접 업로드 이미지 자료, V26).
enum ArchiveRegisterMode { link, text, image }

enum _ImageSourceChoice { camera, gallery }

/// S-25-C 자료 등록 바텀시트 — specs/0010-아카이브-탭.md.
/// todo_form_sheet.dart/schedule_form_sheet.dart와 동일 구조: 시트는 API를 모르고, 부모가 주입한
/// [onSubmit] 콜백만 호출한다. 등록은 크롤링+AI 태깅이 끼어들어 수 초 걸릴 수 있어 버튼 스피너 외에
/// 진행 문구를 별도로 보여준다(design.md §6 고정 문구).
class ArchiveItemRegisterSheet extends StatefulWidget {
  const ArchiveItemRegisterSheet({
    super.key,
    required this.folders,
    required this.initialFolderId,
    required this.onSubmit,
    this.initialMode = ArchiveRegisterMode.link,
    this.imagePicker,
    required this.uploadImage,
  });

  final List<ArchiveFolder> folders;
  final int initialFolderId;
  final ArchiveRegisterMode initialMode;
  final Future<void> Function({
    required int folderId,
    String? url,
    String? text,
    String? memo,
    String? imageUrl,
    String? title,
  })
  onSubmit;

  /// 폴더 직접 업로드 이미지(V26) — 고른 파일을 업로드해 공개 URL을 돌려준다. 실제 네트워크
  /// 호출은 항상 부모가 구현한다(roomId·idToken이 시트 바깥에 있음, `todo_form_sheet.dart`의
  /// `uploadImage`와 같은 주입 패턴).
  final Future<String> Function(List<int> bytes) uploadImage;

  /// 테스트에서 갤러리 접근을 대체하기 위한 주입점. 프로덕션은 기본 [ImagePicker].
  @visibleForTesting
  final Future<XFile?> Function()? imagePicker;

  @override
  State<ArchiveItemRegisterSheet> createState() =>
      _ArchiveItemRegisterSheetState();
}

class _ArchiveItemRegisterSheetState extends State<ArchiveItemRegisterSheet> {
  late int _folderId = widget.initialFolderId;
  late ArchiveRegisterMode _mode = widget.initialMode;
  final _urlController = TextEditingController();
  final _textController = TextEditingController();
  // 링크 모드에서만 쓰는 선택 입력(2026-08-06) — 텍스트(메모형) 등록은 입력한 텍스트 자체가
  // 이미 본문이라 별도 메모 칸이 필요 없다.
  final _memoController = TextEditingController();
  // 이미지 모드 전용 선택 입력(제목/캡션, 2026-08-09 후속) — 비우면 서버가 "사진"으로 채운다.
  final _imageTitleController = TextEditingController();
  XFile? _image;
  final _imageBoxKey = GlobalKey();
  bool _loading = false;
  String? _errorText;

  @override
  void dispose() {
    _urlController.dispose();
    _textController.dispose();
    _memoController.dispose();
    _imageTitleController.dispose();
    super.dispose();
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

  String get _currentFolderName {
    return widget.folders
        .firstWhere(
          (f) => f.id == _folderId,
          orElse: () => widget.folders.first,
        )
        .name;
  }

  Future<void> _openFolderPicker() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final folder in widget.folders)
              ListTile(
                title: Text(folder.name),
                onTap: () => Navigator.of(context).pop(folder.id),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _folderId = selected);
    }
  }

  Future<void> _submit() async {
    final url = _urlController.text.trim();
    final text = _textController.text.trim();
    if (_mode == ArchiveRegisterMode.image) {
      if (_image == null) {
        setState(() => _errorText = '사진을 선택해 주세요');
        return;
      }
    } else {
      final activeValue = _mode == ArchiveRegisterMode.link ? url : text;
      if (activeValue.isEmpty) {
        setState(() {
          _errorText = _mode == ArchiveRegisterMode.link
              ? '링크를 입력해 주세요'
              : '텍스트를 입력해 주세요';
        });
        return;
      }
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final memo = _memoController.text.trim();
      String? imageUrl;
      if (_mode == ArchiveRegisterMode.image) {
        imageUrl = await widget.uploadImage(await _image!.readAsBytes());
      }
      final imageTitle = _imageTitleController.text.trim();
      await widget.onSubmit(
        folderId: _folderId,
        url: _mode == ArchiveRegisterMode.link ? url : null,
        text: _mode == ArchiveRegisterMode.text ? text : null,
        memo: _mode == ArchiveRegisterMode.link && memo.isNotEmpty
            ? memo
            : null,
        imageUrl: imageUrl,
        title: _mode == ArchiveRegisterMode.image && imageTitle.isNotEmpty
            ? imageTitle
            : null,
      );
      if (!mounted) return;
      // **등록했음을 true로 알린다** — 호출부가 이걸 보고 목록을 다시 부른다. 바깥 탭으로
      // 닫으면 null이 와서 아무 일도 하지 않는다(예전에는 구분이 없어 그냥 닫아도 재조회가
      // 돌고, 그 조회가 실패하면 에러까지 떴다 — 2026-08-05 신고).
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = '등록하지 못했어요. 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // `SafeArea`로 시스템 내비게이션 바(제스처 바·삼성 3버튼 내비 등) 안전영역을 피한다 —
    // 아래 `viewInsets.bottom`은 키보드만 보정해 시스템 바와는 무관하다(2026-08-08, 삼성
    // 기본 하단 버튼과 겹치는 신고로 추가).
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.content,
          right: AppSpacing.content,
          top: AppSpacing.content,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.content,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('자료 등록', style: AppTypography.section),
              const SizedBox(height: AppSpacing.content),
              const Text('폴더', style: AppTypography.title),
              const SizedBox(height: AppSpacing.sm),
              InkWell(
                onTap: _loading ? null : _openFolderPicker,
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.content,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _currentFolderName,
                          style: AppTypography.body,
                        ),
                      ),
                      Text(
                        '변경',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.cardGap),
              Row(
                children: [
                  _buildModeChip(label: '링크', mode: ArchiveRegisterMode.link),
                  const SizedBox(width: AppSpacing.cardGap),
                  _buildModeChip(label: '텍스트', mode: ArchiveRegisterMode.text),
                  const SizedBox(width: AppSpacing.cardGap),
                  _buildModeChip(label: '이미지', mode: ArchiveRegisterMode.image),
                ],
              ),
              const SizedBox(height: AppSpacing.cardGap),
              if (_mode == ArchiveRegisterMode.link) ...[
                _softField(
                  child: TextField(
                    controller: _urlController,
                    enabled: !_loading,
                    keyboardType: TextInputType.url,
                    style: AppTypography.body,
                    decoration: _bareInput('https://...'),
                  ),
                ),
                const SizedBox(height: AppSpacing.cardGap),
                _softField(
                  child: TextField(
                    controller: _memoController,
                    enabled: !_loading,
                    maxLength: 500,
                    style: AppTypography.body,
                    decoration: _bareInput('메모(선택)'),
                  ),
                ),
              ] else if (_mode == ArchiveRegisterMode.text)
                _softField(
                  child: TextField(
                    controller: _textController,
                    enabled: !_loading,
                    maxLines: 5,
                    style: AppTypography.body,
                    decoration: _bareInput('내용을 입력해 주세요'),
                  ),
                )
              else ...[
                _ImageAddBox(
                  anchorKey: _imageBoxKey,
                  hasImage: _image != null,
                  onTap: _loading ? null : _pickImage,
                ),
                const SizedBox(height: AppSpacing.cardGap),
                _softField(
                  child: TextField(
                    controller: _imageTitleController,
                    enabled: !_loading,
                    maxLength: 255,
                    style: AppTypography.body,
                    decoration: _bareInput('제목(선택, 비우면 "사진"으로 등록돼요)'),
                  ),
                ),
              ],
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
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(64, 48),
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
                        : const Text('등록'),
                  ),
                ],
              ),
              if (_loading) ...[
                const SizedBox(height: AppSpacing.cardGap),
                Text(
                  // 이미지는 AI 분석 대상이 아니다(V26) — 업로드 중이라는 문구로 갈아끼운다.
                  _mode == ArchiveRegisterMode.image
                      ? '사진을 업로드하고 있어요'
                      : '자료를 분석해 태그를 만들고 있어요',
                  style: AppTypography.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 투두 추가 시트와 동일한 입력 룩(2026-08-09) — `surface-soft` 라운드 블록 + 무테·투명 입력.
  Widget _softField({required Widget child}) => Container(
    decoration: BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: child,
  );

  InputDecoration _bareInput(String hint) => InputDecoration(
    isCollapsed: true,
    filled: false,
    contentPadding: EdgeInsets.zero,
    counterText: '',
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.mutedSoft),
  );

  // design.md §1/§2: 화면당 강조색은 primary 하나만 — 선택 상태 배경을 시드 컬러스킴이
  // 임의로 계산한 secondaryContainer가 아니라 명시적으로 primary로 고정한다.
  Widget _buildModeChip({
    required String label,
    required ArchiveRegisterMode mode,
  }) {
    final selected = _mode == mode;
    return ChoiceChip(
      label: Text(
        label,
        style: AppTypography.bodySmall.copyWith(
          color: selected ? AppColors.onPrimary : AppColors.muted,
        ),
      ),
      selected: selected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceSoft,
      side: const BorderSide(color: AppColors.border),
      onSelected: _loading ? null : (_) => setState(() => _mode = mode),
    );
  }
}

// 이미지 추가 — 아웃라인 박스, `todo_form_sheet.dart`의 `_ImageAddBox`와 같은 모양.
// 탭 리플 없음(GestureDetector) — 그쪽과 통일.
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
              hasImage ? '이미지 1장 선택됨' : '이미지 선택',
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
