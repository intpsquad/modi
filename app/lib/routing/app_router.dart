import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/archive/archive_folder_items_screen.dart';
import '../features/archive/archive_item_detail_screen.dart';
import '../features/archive/archive_screen.dart';
import '../features/auth/email_login_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/ended_room_summary_screen.dart';
import '../features/legal/legal_content.dart';
import '../features/legal/legal_screen.dart';
import '../features/member/member_todos_screen.dart';
import '../features/notifications/notification_history_screen.dart';
import '../features/onboarding/intro_screen.dart';
import '../features/room/create_room_screen.dart';
import '../features/room/invite_share.dart';
import '../features/room/invite_share_screen.dart';
import '../features/room/join_room_screen.dart';
import '../features/room/restart_room_screen.dart';
import '../features/room/room_setup_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/settings/feedback_screen.dart';
import '../features/settings/settings_screens.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/branch_container.dart';
import '../features/splash/splash_screen.dart';
import '../features/todos/todo_detail_screen.dart';
import '../features/todos/todos_screen.dart';
import 'app_session.dart';

String? _inviteCodeFromUri(Uri uri) {
  final location = inviteJoinLocation(uri);
  if (location == null) return null;
  return Uri.parse(location).queryParameters['inviteCode'];
}

String _joinLocation(String inviteCode) => Uri(
  path: '/room/join',
  queryParameters: {'inviteCode': inviteCode},
).toString();

/// 페이드 전환 페이지. 스플래시→온보딩처럼 "윽!" 하고 넘어가지 않고 대상 화면이
/// 천천히 나타나도록 쓴다. 진입(enter)은 길게, 이탈(reverse)은 짧게(다음 화면으로의
/// 이동까지 느려지지 않도록).
CustomTransitionPage<void> _fadePage(
  Widget child,
  LocalKey key, {
  int enterMs = 1500,
  int exitMs = 300,
}) {
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: Duration(milliseconds: enterMs),
    reverseTransitionDuration: Duration(milliseconds: exitMs),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
    child: child,
  );
}

/// 셸(탭 네비바) 바깥 최상위 네비게이터. **하위 페이지는 여기에 push한다** —
/// 탭 브랜치 안에 push하면 네비바가 같이 보인다(2026-08-05 요청: "다른 페이지니까 네비바
/// 같은 거 보이면 안 돼"). 브랜치 안에 둬야 하는 건 탭 루트 화면뿐이다.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// 라우트 트리 — 단일 진실: specs/0003-navigation.md.
/// 임의로 라우트를 추가하지 말고, 새 화면이 필요하면 먼저 해당 스펙을 갱신한다.
final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/splash',
  refreshListenable: appSession,
  redirect: (context, state) {
    final path = state.matchedLocation;
    final incomingInviteCode = _inviteCodeFromUri(state.uri);
    if (incomingInviteCode != null) {
      appSession.rememberPendingInviteCode(incomingInviteCode);
    }
    final pendingInviteCode =
        incomingInviteCode ?? appSession.pendingInviteCode;
    final joinLocation = pendingInviteCode == null
        ? null
        : _joinLocation(pendingInviteCode);
    // 약관·정책은 로그인 여부와 무관한 공개 페이지 — 회원가입(비로그인)과 설정(로그인)
    // 양쪽에서 열 수 있어야 하므로 인증 리다이렉트에서 제외한다.
    // matchedLocation은 쿼리스트링을 제거하므로 정확 일치로 충분하다(?doc=privacy 포함).
    // startsWith가 아닌 정확 일치라 장래 다른 라우트가 접두를 공유해도 우회되지 않는다.
    if (path == '/legal') return null;
    final isSplash = path == '/splash';
    final isOnboarding = path.startsWith('/onboarding');
    final isRoomFlow =
        path.startsWith('/room/create') || path.startsWith('/room/join');

    if (!appSession.splashMinimumElapsed) {
      return isSplash ? null : '/splash';
    }

    if (!appSession.authKnown || !appSession.introKnown) {
      return isSplash ? null : '/splash';
    }

    if (!appSession.isSignedIn) {
      if (!appSession.introCompleted) {
        return path == '/onboarding/intro' ? null : '/onboarding/intro';
      }
      return isOnboarding && path != '/onboarding/intro'
          ? null
          : '/onboarding/login';
    }

    if (appSession.membership == MembershipStatus.loading) {
      return isSplash ? null : '/splash';
    }

    if (appSession.membership == MembershipStatus.error) {
      return isSplash ? null : '/splash';
    }

    if (appSession.membership == MembershipStatus.none) {
      if (joinLocation != null) {
        if (path == '/room/join') {
          appSession.clearPendingInviteCode();
          return null;
        }
        return joinLocation;
      }
      return (isRoomFlow || path == '/onboarding/room-setup')
          ? null
          : '/onboarding/room-setup';
    }

    // membership == has
    if (joinLocation != null) {
      if (path == '/room/join') {
        appSession.clearPendingInviteCode();
        return null;
      }
      return joinLocation;
    }
    if (isSplash || isOnboarding) {
      return '/home';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', redirect: (context, state) => '/splash'),
    // 스플래시는 이탈 시 은은하게 페이드아웃되며 다음 화면과 오버랩된다(디자인 지시서
    // 2026-08-05). 진입 페이드인은 SplashScreen 내부 로고 애니메이션이 맡는다.
    GoRoute(
      path: '/splash',
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        transitionDuration: const Duration(milliseconds: 900),
        reverseTransitionDuration: const Duration(milliseconds: 900),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        child: const SplashScreen(),
      ),
    ),
    // 스플래시에서 넘어올 때 페이드인(스플래시 fade-out 900ms과 자연스럽게 겹침).
    // 2026-08-09 QA: 1500→1000ms로 조금 단축.
    GoRoute(
      path: '/onboarding/intro',
      pageBuilder: (context, state) =>
          _fadePage(const IntroScreen(), state.pageKey, enterMs: 1000),
    ),
    // 시작하기 → 로그인 진입 페이드인. 2026-08-09 QA: 1500→800ms로 단축.
    GoRoute(
      path: '/onboarding/login',
      pageBuilder: (context, state) =>
          _fadePage(const LoginScreen(), state.pageKey, enterMs: 800),
    ),
    GoRoute(
      path: '/onboarding/login/email',
      builder: (context, state) => const EmailLoginScreen(),
    ),
    GoRoute(
      path: '/onboarding/signup',
      builder: (context, state) => const SignupScreen(),
    ),
    GoRoute(
      path: '/onboarding/room-setup',
      builder: (context, state) => RoomSetupScreen(),
    ),
    // indexedStack이 아니라 직접 컨테이너를 그린다 — 탭 전환을 옆으로 미끄러지게 하기 위해서다
    // (요청 2). 탭 상태 보존은 AnimatedBranchContainer가 모든 브랜치를 트리에 유지해 지킨다.
    StatefulShellRoute(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      navigatorContainerBuilder: (context, navigationShell, children) =>
          AnimatedBranchContainer(
            currentIndex: navigationShell.currentIndex,
            children: children,
          ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) {
                final endedRoomId = int.tryParse(
                  state.uri.queryParameters['endedRoomId'] ?? '',
                );
                return endedRoomId == null
                    ? HomeScreen()
                    : EndedRoomSummaryScreen(roomId: endedRoomId);
              },
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/todos',
              builder: (context, state) => TodosScreen(),
              // 상세/수정은 탭이 아니라 **하위 페이지**다 — 루트 네비게이터에 push해
              // 네비바를 덮고 전체 화면으로 뜨게 한다(/archive/item/:id와 동일 근거).
              routes: [
                GoRoute(
                  path: 'item/:id',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => TodoDetailScreen(
                    todoId: int.parse(state.pathParameters['id']!),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/schedule',
              builder: (context, state) => ScheduleScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/archive',
              builder: (context, state) => ArchiveScreen(),
              // 폴더 자료 목록(folder/:id)은 **탭 브랜치 안**에 두어 하단 네비바를 유지한다
              // (2026-08-08 요청 — 폴더 선택·자료 선택 화면까지는 네비바 노출). 반면 자료 본문
              // (item/:id)은 몰입 위해 **루트 네비게이터에 push**해 네비바를 덮는다. 경로는 둘 다
              // /archive/... 그대로.
              routes: [
                GoRoute(
                  path: 'folder/:id',
                  builder: (context, state) => ArchiveFolderItemsScreen(
                    folderId: int.parse(state.pathParameters['id']!),
                  ),
                ),
                GoRoute(
                  path: 'item/:id',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => ArchiveItemDetailScreen(
                    itemId: int.parse(state.pathParameters['id']!),
                  ),
                ),
              ],
            ),
          ],
        ),
        // 마이페이지 — 맨 오른쪽 탭. 설정(S-40)을 이 탭 루트로 옮겼다(2026-08-07 요청:
        // "마이탭으로 내용을 옮겨줘"). 하위 페이지(프로필·알림·방·멤버·종료된 방)는 탭이 아니라
        // **하위 페이지**라 rootNavigatorKey로 push해 네비바를 덮고 전체 화면으로 뜬다
        // (/todos/item/:id·/archive/... 와 동일 패턴).
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/mypage',
              builder: (context, state) => SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'profile',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => ProfileSettingsScreen(),
                ),
                GoRoute(
                  path: 'notifications',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => NotificationSettingsScreen(),
                ),
                GoRoute(
                  path: 'room',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => RoomSettingsScreen(),
                ),
                GoRoute(
                  path: 'members',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => MembersSettingsScreen(),
                ),
                GoRoute(
                  path: 'past-rooms',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => PastRoomsScreen(),
                ),
                // 문의하기(#70) — 예전에는 mailto: 딥링크라 라우트가 없었다.
                GoRoute(
                  path: 'contact',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => FeedbackScreen(
                    contactEmailLauncher: (uri) =>
                        launchUrl(uri, mode: LaunchMode.externalApplication),
                  ),
                ),
                GoRoute(
                  path: 'notification-history',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => NotificationHistoryScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/room/create',
      builder: (context, state) => CreateRoomScreen(),
      routes: [
        GoRoute(
          path: 'invite',
          builder: (context, state) {
            final extra = state.extra as InviteShareArgs?;
            return InviteShareScreen(
              roomId: extra?.roomId ?? 0,
              inviteCode: extra?.inviteCode ?? '',
              roomName: extra?.roomName,
              coverImage: extra?.coverImage,
            );
          },
        ),
      ],
    ),
    GoRoute(
      path: '/legal',
      builder: (context, state) {
        final doc = state.uri.queryParameters['doc'] == 'privacy'
            ? LegalDoc.privacy
            : LegalDoc.terms;
        return LegalScreen(initialDoc: doc);
      },
    ),
    GoRoute(
      path: '/room/join',
      builder: (context, state) =>
          JoinRoomScreen(initialInviteCode: _inviteCodeFromUri(state.uri)),
    ),
    GoRoute(
      path: '/room/edit/:id',
      builder: (context, state) =>
          RestartRoomScreen(roomId: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/member/:userId',
      builder: (context, state) =>
          MemberTodosScreen(userId: state.pathParameters['userId']!),
    ),
  ],
);
