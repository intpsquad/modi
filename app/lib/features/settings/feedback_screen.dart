import 'dart:io' show Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../design/segmented_toggle.dart';
import '../../design/tokens.dart';
import '../auth/auth_service.dart';
import '../room/room_cover_image_field.dart' show CoverImagePick;
import 'settings_screens.dart';

/// 문의를 받는 팀 주소. 폼 전송이 실패했을 때의 마지막 통로(mailto)로 쓴다.
const supportEmailAddress = 'modi.app.team@gmail.com';

typedef ContactEmailLauncher = Future<bool> Function(Uri uri);

/// 앱 버전·기기 정보를 읽는 경계. 테스트에서 고정값을 끼울 수 있어야 해서 주입 가능하게 둔다.
typedef FeedbackEnvironmentLoader = Future<FeedbackEnvironment> Function();

class FeedbackEnvironment {
  const FeedbackEnvironment({this.appVersion, this.deviceInfo});

  final String? appVersion;
  final String? deviceInfo;

  /// 기본 구현 — 앱 버전은 `package_info_plus`, 기기는 `dart:io`로 읽는다.
  /// `device_info_plus`까지 넣지 않는다: 모델명까지는 필요 없고 OS·버전이면 재현에 충분하다.
  static Future<FeedbackEnvironment> load() async {
    String? version;
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}(${info.buildNumber})';
    } catch (_) {
      // 버전을 못 읽는다고 문의를 막지 않는다 — 나머지 정보만으로도 접수는 된다.
    }
    String? device;
    if (!kIsWeb) {
      try {
        device =
            '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      } catch (_) {
        // 위와 같은 이유.
      }
    }
    return FeedbackEnvironment(appVersion: version, deviceInfo: device);
  }
}

/// 문의 유형 — 서버 `FeedbackType`과 값이 1:1로 대응한다(#70).
enum FeedbackKind {
  bug('BUG', '버그'),
  question('QUESTION', '문의'),
  suggestion('SUGGESTION', '제안');

  const FeedbackKind(this.wireValue, this.label);

  final String wireValue;
  final String label;
}

/// S-40 문의하기 — 이전에는 `mailto:` 딥링크로 OS 메일 앱을 열었다(#70에서 인앱 폼으로 교체).
/// 메일 앱이 없거나 계정 설정이 안 된 기기에서 문의 자체가 막히던 문제를 없앤다.
class FeedbackScreen extends StatefulWidget {
  FeedbackScreen({
    super.key,
    SettingsApi? api,
    TokenLoader? tokenLoader,
    this.photoPicker,
    this.environmentLoader,
    this.contactEmailLauncher,
  }) : api = api ?? SettingsApi(),
       tokenLoader = tokenLoader ?? AuthService().getIdToken;

  final SettingsApi api;
  final TokenLoader tokenLoader;
  final CoverImagePick? photoPicker;
  final FeedbackEnvironmentLoader? environmentLoader;

  /// 전송 실패 시 제시하는 mailto 폴백. null이면 폴백 액션을 숨긴다(테스트 기본값).
  final ContactEmailLauncher? contactEmailLauncher;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _contentController = TextEditingController();
  final _emailController = TextEditingController();

  FeedbackKind _kind = FeedbackKind.bug;
  FeedbackEnvironment _environment = const FeedbackEnvironment();
  List<int>? _imageBytes;
  bool _accountEmailMissing = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEnvironment();
    _prefillReplyEmail();
    // 내용이 비면 전송 버튼이 꺼지므로 타이핑마다 다시 그린다.
    _contentController.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    _contentController.removeListener(_onContentChanged);
    _contentController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _onContentChanged() => setState(() {});

  Future<void> _loadEnvironment() async {
    final loader = widget.environmentLoader ?? FeedbackEnvironment.load;
    try {
      final environment = await loader();
      if (mounted) setState(() => _environment = environment);
    } catch (_) {
      // 보조 정보라 실패해도 폼은 그대로 쓴다.
    }
  }

  /// 회신 주소는 계정 이메일로 채워두되 수정 가능하게 둔다. 소셜 로그인은 제공사가 이메일을
  /// 안 줄 수 있어(카카오 동의항목 등) 비어 있을 수 있고, 그때는 "답변을 받을 수 없다"고 알린다.
  Future<void> _prefillReplyEmail() async {
    try {
      final profile = await widget.api.fetchProfile(await widget.tokenLoader());
      if (!mounted) return;
      final email = profile.email;
      setState(() {
        _accountEmailMissing = email == null || email.isEmpty;
        if (!_accountEmailMissing) _emailController.text = email!;
      });
    } catch (_) {
      // 프로필을 못 읽어도 직접 입력하면 된다.
      if (mounted) setState(() => _accountEmailMissing = true);
    }
  }

  Future<void> _pickScreenshot() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('앨범에서 선택'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('사진 찍기'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final picker =
        widget.photoPicker ??
        (imageSource) => ImagePicker().pickImage(
          source: imageSource,
          imageQuality: 85,
          maxWidth: 1200,
        );
    try {
      final file = await picker(source);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _imageBytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _error = '사진을 불러오지 못했어요');
    }
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.api.submitFeedback(
        await widget.tokenLoader(),
        type: _kind.wireValue,
        content: _contentController.text.trim(),
        replyEmail: _emailController.text.trim(),
        appVersion: _environment.appVersion,
        deviceInfo: _environment.deviceInfo,
        imageBytes: _imageBytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('문의를 보냈어요')));
      Navigator.of(context).pop();
    } catch (error) {
      // 전송이 막혀도 문의 자체를 포기하게 두지 않는다 — mailto가 마지막 통로다(#70).
      // 원인은 화면에 드러내지 않되 로그에는 남긴다 — 옛 `catch (_)` 는 404 인지 인증
      // 실패인지조차 남기지 않아, 서버를 직접 찔러보기 전에는 알 수 없었다(#76).
      debugPrint('문의 전송 실패: $error');
      if (mounted) {
        setState(() => _error = '문의를 보내지 못했어요. 잠시 후 다시 시도해 주세요');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openMailFallback() async {
    final launcher = widget.contactEmailLauncher;
    if (launcher == null) return;
    var opened = false;
    try {
      opened = await launcher(Uri(scheme: 'mailto', path: supportEmailAddress));
    } catch (error) {
      // launchUrl 은 처리할 앱이 없을 때 false 를 돌려주기도 하고 예외를 던지기도 한다.
      // 던지는 쪽에서는 안내조차 못 띄운 채 아무 일도 일어나지 않았다(#76, iOS
      // 시뮬레이터에 메일 앱이 없을 때 실측). 여기서 흡수해 아래 안내로 보낸다.
      debugPrint('mailto 실행 실패: $error');
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('메일 앱을 열 수 없어요. $supportEmailAddress으로 보내 주세요'),
        ),
      );
    }
  }

  bool get _canSubmit => _contentController.text.trim().isNotEmpty && !_sending;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('문의하기')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.content),
              children: [
                const Text('어떤 이야기인가요?', style: AppTypography.title),
                const SizedBox(height: AppSpacing.sm),
                SegmentedToggle(
                  segments: [
                    for (final kind in FeedbackKind.values) kind.label,
                  ],
                  selectedIndex: FeedbackKind.values.indexOf(_kind),
                  onChanged: (index) =>
                      setState(() => _kind = FeedbackKind.values[index]),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text('내용', style: AppTypography.title),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const ValueKey('feedback-content-field'),
                  controller: _contentController,
                  enabled: !_sending,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText: '무엇이 불편했는지 자세히 적어 주시면 도움이 돼요',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _ScreenshotField(
                  bytes: _imageBytes,
                  enabled: !_sending,
                  onPick: _pickScreenshot,
                  onRemove: () => setState(() => _imageBytes = null),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text('회신 받을 이메일 (선택)', style: AppTypography.title),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const ValueKey('feedback-email-field'),
                  controller: _emailController,
                  enabled: !_sending,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'answer@example.com',
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _accountEmailMissing
                      ? '가입 계정에 이메일이 없어요. 비워 두면 답변을 받을 수 없어요'
                      : '비워 두면 답변을 받을 수 없어요',
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppSpacing.lg),
                // 고지 없이 수집하지 않는다 — 무엇이 함께 가는지 값까지 보여준다.
                Text(
                  '문제 확인을 위해 앱 버전(${_environment.appVersion ?? '확인 중'})과 '
                  '기기 정보(${_environment.deviceInfo ?? '확인 중'})가 함께 전송돼요',
                  style: AppTypography.caption,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.accentDanger,
                    ),
                  ),
                  if (widget.contactEmailLauncher != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    TextButton(
                      key: const ValueKey('feedback-mail-fallback'),
                      onPressed: _openMailFallback,
                      child: const Text('이메일로 문의하기'),
                    ),
                  ],
                ],
              ],
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(AppSpacing.content),
            child: ElevatedButton(
              key: const ValueKey('feedback-submit-button'),
              onPressed: _canSubmit ? _submit : null,
              child: _sending
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text('보내기'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 스크린샷 첨부 — 없으면 점선 추가 버튼, 있으면 썸네일 + 삭제.
class _ScreenshotField extends StatelessWidget {
  const _ScreenshotField({
    required this.bytes,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  final List<int>? bytes;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final picked = bytes;
    if (picked == null) {
      return OutlinedButton.icon(
        key: const ValueKey('feedback-add-screenshot'),
        onPressed: enabled ? onPick : null,
        icon: const Icon(Icons.image_outlined, size: AppSpacing.base),
        label: const Text('스크린샷 첨부 (선택)'),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Image.memory(
            Uint8List.fromList(picked),
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.square(
              dimension: 64,
              child: ColoredBox(color: AppColors.surfaceSoft),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(child: Text('스크린샷 1장', style: AppTypography.bodySmall)),
        TextButton(
          key: const ValueKey('feedback-remove-screenshot'),
          onPressed: enabled ? onRemove : null,
          child: const Text('삭제'),
        ),
      ],
    );
  }
}
