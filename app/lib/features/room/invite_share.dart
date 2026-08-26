import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/env.dart';
import 'default_cover.dart';

/// 초대코드 공유·복사 유틸 (QA / 리디자인).
///
/// 초대코드를 OS 공유 시트(카톡·인스타 DM 등)로 보내거나, 클립보드에 복사하거나,
/// 특정 앱을 딥링크로 여는 동작을 담는다. 실제 공유 시트/클립보드/앱 실행은 위젯
/// 테스트에서 띄울 수 없으므로, 화면은 이 함수 타입들을 주입받아 테스트에서 스파이로
/// 대체한다(회원가입 image_picker 주입과 같은 패턴).
typedef ShareInviteFn =
    Future<void> Function(String text, {Rect? sharePositionOrigin});
typedef CopyFn = Future<void> Function(String text);
typedef LaunchAppFn = Future<bool> Function(String url);
typedef KakaoInviteShareFn = Future<void> Function(InviteShareData invite);

/// 공유 채널에서 공통으로 사용하는 방 초대 정보.
///
/// 카카오 템플릿에는 방 이름과 대표 이미지를, 인스타·OS 공유에는 [code]와 [roomName]을
/// 쓴다. 대표 이미지가 없으면 [roomId]로 정해진 기본 커버를 카카오 이미지 서버에 올린다.
class InviteShareData {
  const InviteShareData({
    required this.roomId,
    required this.code,
    this.roomName,
    this.coverImage,
  });

  final int roomId;
  final String code;
  final String? roomName;
  final String? coverImage;

  String get message => buildInviteMessage(code: code, roomName: roomName);
}

/// 초대 공유 문구. 방 이름이 있으면 함께 넣는다.
String buildInviteMessage({required String code, String? roomName}) {
  final trimmed = roomName?.trim();
  final where = (trimmed != null && trimmed.isNotEmpty)
      ? "'$trimmed' 방"
      : '우리 방';
  return 'MODI에서 함께해요!\n'
      '$where 초대코드: $code\n'
      '앱에서 초대코드를 입력하면 참여할 수 있어요.';
}

/// 기본 구현 — OS 공유 시트를 띄운다.
/// 주의: [sharePositionOrigin]이 비어 있으면(`CGRectZero`) iOS 네이티브가 팝오버 앵커를
/// 잡지 못해 시트를 아예 띄우지 않고 에러를 돌려준다 — **iPad 전용이 아니라 iPhone도
/// 해당**(`UIActivityViewController.popoverPresentationController`는 기기 종류와 무관하게
/// non-nil이다). 호출부는 항상 [inviteShareOrigin]으로 구한 rect를 넘겨야 한다
/// (2026-08-07 iOS에서 공유하기 안 열리던 문제 대응 — 그때 S-10-A 화면 경로만 고치고
/// 설정 시트(더보기) 경로를 빠뜨려 2026-08-26 같은 증상이 재발했다).
/// OS 네이티브 공유 시트. share_plus 10.x API.
Future<void> shareInviteText(String text, {Rect? sharePositionOrigin}) =>
    Share.share(text, sharePositionOrigin: sharePositionOrigin);

/// [shareInviteText] 팝오버 앵커. [context]의 렌더 박스를 화면 좌표로 변환해 넘기고,
/// 아직 레이아웃이 안 잡혀 있으면(드물게 시트 pop 직후 등) 화면 전체 rect로 대신한다 —
/// `null`이나 빈 rect를 넘기면 iOS에서 시트가 아예 안 뜨므로(위 [shareInviteText] 참고)
/// 항상 비어 있지 않은 값을 돌려준다.
Rect? inviteShareOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  final mediaSize = MediaQuery.maybeSizeOf(context);
  if (mediaSize != null && mediaSize.width > 0 && mediaSize.height > 0) {
    return Offset.zero & mediaSize;
  }
  return null;
}

/// 기본 구현 — 클립보드에 복사한다.
Future<void> copyToClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

/// 기본 구현 — 외부 앱을 딥링크로 연다. 앱이 없거나 스킴을 못 열면 false.
///
/// `canLaunchUrl`은 iOS의 `LSApplicationQueriesSchemes`·Android package visibility
/// 설정에 따라 false negative가 날 수 있어, 실제 실행 결과를 바로 사용한다.
Future<bool> launchExternalApp(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } on PlatformException {
    return false;
  }
}

/// 인스타그램 DM은 외부 앱이 본문을 미리 채울 수 없으므로 코드만 복사한 뒤 앱을 연다.
/// 반환값은 Instagram 앱 전환 성공 여부다. 복사 실패는 호출자에게 전달한다.
Future<bool> shareInviteToInstagram({
  required String code,
  CopyFn copy = copyToClipboard,
  LaunchAppFn launchApp = launchExternalApp,
}) async {
  await copy(code);
  return launchApp('instagram://');
}

/// 카카오톡 피드 템플릿.
///
/// 템플릿의 링크와 "참여하기" 버튼에는 같은 실행 파라미터를 넣어, 설치된
/// Android/iOS 앱이 카카오 커스텀 URL scheme으로 방 참여 화면을 연다.
FeedTemplate buildKakaoInviteTemplate(
  InviteShareData invite, {
  required Uri imageUrl,
  required Uri webUrl,
}) {
  final roomName = invite.roomName?.trim();
  final title = roomName == null || roomName.isEmpty
      ? 'MODI 방에 초대합니다'
      : '$roomName에 초대합니다';
  final link = Link(
    webUrl: webUrl,
    mobileWebUrl: webUrl,
    androidExecutionParams: {'route': 'room/join', 'inviteCode': invite.code},
    iosExecutionParams: {'route': 'room/join', 'inviteCode': invite.code},
  );
  return FeedTemplate(
    content: Content(
      title: title,
      description: 'MODI에서 초대 코드를 입력하고 함께 시작해요.',
      imageUrl: imageUrl,
      link: link,
    ),
    buttons: [Button(title: '참여하기', link: link)],
  );
}

/// 카카오 기본 템플릿이 요구하는 웹 URL. 앱이 설치된 경우에는 템플릿의
/// execution parameters가 우선해 해당 URL scheme의 방 참여 화면으로 연결된다.
Uri buildInviteWebUrl(String code) {
  final base = Uri.parse(Env.apiBaseUrl);
  return base.replace(
    path: '/room/join',
    queryParameters: {'inviteCode': code},
  );
}

/// 카카오톡 SDK로 방 썸네일·제목·참여 버튼이 있는 기본 피드 템플릿을 공유한다.
/// 카카오톡이 설치되지 않은 기기에서는 카카오 웹 공유 URL을 외부 브라우저로 연다.
Future<void> shareInviteToKakao(InviteShareData invite) async {
  if (kIsWeb) {
    throw UnsupportedError('카카오톡 템플릿 공유는 모바일 앱에서만 사용할 수 있어요.');
  }
  if (Env.kakaoNativeAppKey.isEmpty) {
    throw StateError('카카오 앱 키가 설정되지 않았어요.');
  }

  final template = buildKakaoInviteTemplate(
    invite,
    imageUrl: await _resolveKakaoImageUrl(invite),
    webUrl: buildInviteWebUrl(invite.code),
  );
  final client = ShareClient.instance;
  if (await client.isKakaoTalkSharingAvailable()) {
    await client.shareDefault(template: template);
    return;
  }

  final webShareUrl = await WebSharerClient.instance.makeDefaultUrl(
    template: template,
  );
  final opened = await launchUrl(
    webShareUrl,
    mode: LaunchMode.externalApplication,
  );
  if (!opened) {
    throw StateError('카카오톡 공유를 열 수 없어요.');
  }
}

Future<Uri> _resolveKakaoImageUrl(InviteShareData invite) async {
  final coverUri = Uri.tryParse(invite.coverImage?.trim() ?? '');
  if (coverUri != null &&
      coverUri.hasAuthority &&
      (coverUri.scheme == 'https' || coverUri.scheme == 'http')) {
    return coverUri;
  }

  final data = await rootBundle.load(defaultCoverAsset(invite.roomId));
  final bytes = Uint8List.sublistView(data);
  final result = await ShareClient.instance.uploadImage(byteData: bytes);
  return Uri.parse(result.infos.original.url);
}

/// 카카오 실행 URL에서 유효한 6자리 초대 코드를 읽어 방 참여 경로로 바꾼다.
/// 카카오 SDK execution parameters는 `route=room/join`으로 전달된다.
String? inviteJoinLocation(Uri uri) {
  final route = uri.queryParameters['route'];
  final isJoinRoute =
      route == 'room/join' ||
      uri.path == '/room/join' ||
      uri.host == 'kakaolink';
  if (!isJoinRoute) return null;

  final rawCode = uri.queryParameters['inviteCode'];
  if (rawCode == null) return null;
  final normalized = rawCode
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .toUpperCase();
  if (normalized.length != 6) return null;
  return Uri(
    path: '/room/join',
    queryParameters: {'inviteCode': normalized},
  ).toString();
}
