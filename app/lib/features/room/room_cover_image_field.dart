import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../design/tokens.dart';

/// 이미지 소스 선택 후 [XFile]을 돌려주는 함수. 기본은 image_picker이며,
/// 테스트는 플랫폼 채널을 건드리지 않도록 가짜를 주입한다.
typedef CoverImagePick = Future<XFile?> Function(ImageSource source);

/// 방 대표 이미지 업로드 필드 — 방 생성/설정 공용(specs/0004·0012, 티켓 ).
///
/// 탭 → 소스 선택(갤러리/카메라) → 피커 → [uploadImage]로 업로드 → 반환 URL을
/// [onChanged]로 상위에 알린다. 업로딩/에러 상태는 위젯이 직접 관리하고, 저장(생성/설정
/// 저장)은 상위 화면이 담당한다.
class RoomCoverImageField extends StatefulWidget {
  const RoomCoverImageField({
    super.key,
    this.initialUrl,
    required this.uploadImage,
    required this.onChanged,
    this.pickImage,
    this.enableCamera = true,
    this.height = 160,
  });

  /// 기존 대표 이미지 URL(설정 화면 진입 시). 없으면 빈 상태.
  final String? initialUrl;

  /// 피커가 고른 파일을 업로드하고 접근 URL을 반환하는 콜백(상위가 토큰+RoomApi로 구현).
  final Future<String> Function(XFile file) uploadImage;

  /// 업로드 성공 URL(또는 삭제 시 null)을 상위에 전달.
  final ValueChanged<String?> onChanged;

  /// 이미지 피커. null이면 image_picker 실제 사용(테스트는 가짜 주입).
  final CoverImagePick? pickImage;

  /// 카메라 촬영 허용 여부(false면 갤러리로 바로 진입).
  final bool enableCamera;

  /// 화면 밀도에 맞춘 미리보기 높이. 생성 화면 기본은 160, 설정 화면은 더 작게 쓸 수 있다.
  final double height;

  static Future<XFile?> _defaultPick(ImageSource source) =>
      ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 1600);

  @override
  State<RoomCoverImageField> createState() => _RoomCoverImageFieldState();
}

class _RoomCoverImageFieldState extends State<RoomCoverImageField> {
  late String? _url = widget.initialUrl;
  bool _uploading = false;
  String? _error;

  Future<void> _onTap() async {
    if (_uploading) return;
    final source = await _chooseSource();
    if (source == null) return;

    final pick = widget.pickImage ?? RoomCoverImageField._defaultPick;
    XFile? file;
    try {
      file = await pick(source);
    } catch (_) {
      if (mounted) setState(() => _error = '이미지를 불러오지 못했어요');
      return;
    }
    if (file == null) return;

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await widget.uploadImage(file);
      if (!mounted) return;
      setState(() {
        _url = url;
        _uploading = false;
      });
      widget.onChanged(url);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = '이미지 업로드에 실패했어요. 다시 시도해 주세요';
      });
    }
  }

  Future<ImageSource?> _chooseSource() {
    if (!widget.enableCamera) return Future.value(ImageSource.gallery);
    return showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  void _remove() {
    setState(() {
      _url = null;
      _error = null;
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: const ValueKey('cover-image-box'),
          onTap: _onTap,
          child: Container(
            height: widget.height,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: _buildContent(url),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.accentDanger,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContent(String? url) {
    if (_uploading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (url != null && url.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            fit: BoxFit.cover,
            // 설정된 이미지의 로드 실패는 "추가" 빈 상태가 아니라 중립 채움으로.
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: AppColors.surfaceStrong),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: Material(
              color: AppColors.scrim,
              shape: const CircleBorder(),
              child: IconButton(
                key: const ValueKey('cover-image-remove'),
                iconSize: 18,
                icon: const Icon(Icons.close, color: AppColors.onPrimary),
                onPressed: _remove,
              ),
            ),
          ),
        ],
      );
    }
    return _empty();
  }

  Widget _empty() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.camera_alt_outlined, color: AppColors.muted),
        SizedBox(height: AppSpacing.xs),
        Text('대표 이미지 추가', style: AppTypography.caption),
      ],
    ),
  );
}
