import 'package:flutter/widgets.dart';

/// 최초 홈 진입 코치마크 2스텝 투어(specs/0008-방-전환.md)가 가리킬 **멤버 아바타 앵커**.
///
/// 코치마크 오버레이는 셸(app_shell)이 띄우지만, 멤버 아바타는 홈 화면(home_screen)이
/// 그리므로 셸이 그 위치를 직접 알 수 없다. 그래서 홈 화면이 첫 번째 비-본인 멤버 아바타에
/// 이 전역 키를 달고, 셸은 이 키의 `currentContext` renderObject로 아바타 중심(글로벌 좌표)을
/// 읽는다. (`appTabActivation`과 같은 결의 얕은 전역 — 테스트에서도 셸/홈을 한 트리에 올리면
/// 그대로 동작한다.)
///
/// 타 멤버가 없는 솔로 방이면 키가 어디에도 부착되지 않아 `currentContext == null`이 되고,
/// 셸은 아바타 스텝을 건너뛴다.
final GlobalKey homeFirstMemberAvatarKey = GlobalKey(
  debugLabel: 'home-first-member-avatar',
);
