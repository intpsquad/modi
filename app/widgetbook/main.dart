import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:widgetbook/widgetbook.dart';

import 'package:app/design/ai_hint_banner.dart';
import 'package:app/design/ai_sparkle_button.dart';
import 'package:app/design/empty_state.dart';
import 'package:app/design/theme.dart';
import 'package:app/design/tokens.dart';
import 'package:app/features/archive/archive_folder_items_screen.dart';
import 'package:app/features/archive/archive_item_detail_screen.dart';
import 'package:app/features/archive/archive_screen.dart';
import 'package:app/features/auth/email_login_screen.dart';
import 'package:app/features/auth/login_screen.dart';
import 'package:app/features/auth/signup_screen.dart';
import 'package:app/features/home/ended_room_summary_screen.dart';
import 'package:app/features/legal/legal_screen.dart';
import 'package:app/features/home/home_screen.dart';
import 'package:app/features/member/member_todos_screen.dart';
import 'package:app/features/settings/my_activity_card.dart';
import 'package:app/features/onboarding/intro_screen.dart';
import 'package:app/features/room/create_room_screen.dart';
import 'package:app/features/room/invite_share_screen.dart';
import 'package:app/features/room/join_room_screen.dart';
import 'package:app/features/room/restart_room_screen.dart';
import 'package:app/features/room/room_setup_screen.dart';
import 'package:app/features/schedule/schedule_screen.dart';
import 'package:app/features/settings/settings_screens.dart';
import 'package:app/features/splash/splash_screen.dart';
import 'package:app/features/todos/todos_screen.dart';
import 'package:app/features/room/room_session.dart';

import 'fakes.dart';

final _storyAuthService = StoryAuthService();
final _storySettingsApi = StorySettingsApi();
final _storyMemberTodosApi = StoryMemberTodosApi();

void main() {
  // 브라우저 리뷰/코멘트가 Flutter 전체 캔버스가 아니라 하위 컨트롤을
  // 인식할 수 있도록 Widgetbook에서만 semantics DOM을 활성화한다.
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  appRoomSession
    ..rooms = [storyActiveRoom, storyEndedRoom]
    ..currentRoomId = storyActiveRoom.id;

  runApp(
    Widgetbook.material(
      initialRoute: '/?path=페이지/s-00-스플래시/기본',
      themeMode: ThemeMode.light,
      directories: [
        WidgetbookCategory(
          name: '페이지',
          children: [
            _component('S-00 스플래시', const SplashScreen()),
            _component('S-01 서비스 소개', const IntroScreen()),
            _component('S-02 로그인', LoginScreen(authService: _storyAuthService)),
            // 두 번째 소셜 버튼은 플랫폼별(iOS 애플/안드로이드 구글)이라, 안드로이드 변형도
            // 볼 수 있게 플랫폼을 강제한 스토리를 따로 둔다.
            _component(
              'S-02 로그인 (안드로이드)',
              Theme(
                data: ThemeData(platform: TargetPlatform.android),
                child: LoginScreen(authService: _storyAuthService),
              ),
            ),
            _component(
              'S-02 이메일 로그인',
              EmailLoginScreen(authService: _storyAuthService),
            ),
            _component(
              'S-02-A 자체가입',
              SignupScreen(authService: _storyAuthService),
            ),
            _component('S-03 방 설정', RoomSetupScreen()),
            _component(
              'S-04 홈',
              HomeScreen(
                api: StoryHomeApi(),
                authService: _storyAuthService,
                roomSession: StoryRoomSession(),
              ),
            ),
            _component(
              'S-05 종료된 방 요약',
              EndedRoomSummaryScreen(
                roomId: storyEndedRoom.id,
                api: _storySettingsApi,
                tokenLoader: _storyAuthService.getIdToken,
              ),
            ),
            _component(
              'S-10 방 만들기',
              CreateRoomScreen(
                api: StoryRoomApi(),
                authService: _storyAuthService,
              ),
            ),
            _component(
              'S-10-A 초대코드 공유',
              InviteShareScreen(
                roomId: 42,
                inviteCode: 'MODI42',
                roomSession: StoryRoomSession(),
              ),
            ),
            _component(
              'S-12 종료된 방 재시작',
              RestartRoomScreen(
                roomId: storyEndedRoom.id,
                api: _storySettingsApi,
                authService: _storyAuthService,
              ),
            ),
            _component(
              'S-11 방 참여',
              JoinRoomScreen(
                api: StoryRoomApi(),
                authService: _storyAuthService,
                roomSession: StoryRoomSession(),
              ),
            ),
            _component(
              'S-11 방 참여 (무효 코드)',
              JoinRoomScreen(
                api: StoryInvalidInviteApi(),
                authService: _storyAuthService,
                roomSession: StoryRoomSession(),
              ),
            ),
            WidgetbookComponent(
              name: 'S-30-M 멤버 투두',
              useCases: [
                WidgetbookUseCase(
                  name: '기본',
                  // 캐릭터별 카드 모양과 "본인 페이지(찌르기 버튼 없음)"를 knob으로
                  // 바로 바꿔가며 확인한다(#68로 캐릭터가 이 화면으로 옮겨왔다).
                  builder: (context) {
                    final characterId = context.knobs.object.dropdown<String>(
                      label: '캐릭터',
                      options: _kCharacterIds,
                      initialOption: _kCharacterIds.first,
                    );
                    final isSelf = context.knobs.boolean(
                      label: '본인 페이지',
                      initialValue: false,
                    );
                    _storyMemberTodosApi.characterId = characterId;
                    return MemberTodosScreen(
                      key: ValueKey('$characterId-$isSelf'),
                      userId: 'story-member-1',
                      roomId: storyActiveRoom.id,
                      api: _storyMemberTodosApi,
                      tokenLoader: _storyAuthService.getIdToken,
                      currentUserId: () =>
                          isSelf ? 'story-member-1' : 'story-me',
                    );
                  },
                ),
              ],
            ),
            _component(
              'S-15 투두',
              TodosScreen(
                api: StoryTodosApi(),
                authService: _storyAuthService,
                roomSession: StoryRoomSession(),
              ),
            ),
            _component(
              'S-20 일정',
              ScheduleScreen(
                api: StoryScheduleApi(),
                authService: _storyAuthService,
                roomSession: StoryRoomSession(),
              ),
            ),
            _component(
              'S-25 아카이브',
              ArchiveScreen(
                api: StoryArchiveApi(),
                authService: _storyAuthService,
                roomSession: StoryRoomSession(),
              ),
            ),
            _component(
              'S-25-A 폴더 내 항목',
              ArchiveFolderItemsScreen(
                folderId: 1,
                api: StoryArchiveApi(),
                authService: _storyAuthService,
                roomSession: StoryRoomSession(),
              ),
            ),
            _component(
              'S-25-B 항목 상세',
              ArchiveItemDetailScreen(
                itemId: 101,
                api: StoryArchiveApi(),
                authService: _storyAuthService,
                roomSession: StoryRoomSession(),
              ),
            ),
          ],
        ),
        WidgetbookCategory(
          name: '설정',
          children: [
            // 캐릭터 knob은 S-30-M 스토리로 옮겼다(#68 — 마이페이지에 카드가 없다).
            _component(
              'S-40 설정',
              SettingsScreen(
                currentRoom: storyActiveRoom,
                authService: _storyAuthService,
                api: _storySettingsApi,
                tokenLoader: _storyAuthService.getIdToken,
              ),
            ),
            _component(
              'S-40 프로필 수정',
              ProfileSettingsScreen(
                api: _storySettingsApi,
                tokenLoader: _storyAuthService.getIdToken,
              ),
            ),
            _component(
              'S-40 알림 설정',
              NotificationSettingsScreen(
                api: _storySettingsApi,
                tokenLoader: _storyAuthService.getIdToken,
              ),
            ),
            _component(
              'S-40-A 현재 방 설정',
              RoomSettingsScreen(
                room: storyActiveRoom,
                api: _storySettingsApi,
                tokenLoader: _storyAuthService.getIdToken,
              ),
            ),
            _component(
              'S-40-B 멤버 관리',
              MembersSettingsScreen(
                room: storyActiveRoom,
                api: _storySettingsApi,
                tokenLoader: _storyAuthService.getIdToken,
                currentUserId: 'story-user',
              ),
            ),
            _component(
              'S-40-D 종료된 방',
              PastRoomsScreen(
                api: _storySettingsApi,
                tokenLoader: _storyAuthService.getIdToken,
              ),
            ),
            _component('약관 · 정책', const LegalScreen()),
          ],
        ),
        WidgetbookCategory(
          name: '컴포넌트',
          children: [
            _component(
              'AI 버튼 (AiSparkleButton)',
              Center(child: AiSparkleButton(onTap: _noop)),
            ),
            _component(
              'AI 안내 배너 (AiHintBanner)',
              ListView(
                padding: const EdgeInsets.all(AppSpacing.content),
                children: [
                  AiHintBanner(
                    text: 'MODI가 추천해준 투두에 담당자를 지정해주세요!',
                    onTap: _noop,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // 문구·아이콘을 갈아끼워 다른 화면에서도 쓰는 예.
                  const AiHintBanner(text: 'AI가 이 자료를 요약하고 있어요'),
                  const SizedBox(height: AppSpacing.md),
                  const AiHintBanner(
                    text: '아주 긴 문구는 한 줄로 잘린다 — 배너 높이는 40으로 유지된다 정말로 그런지 보자',
                  ),
                ],
              ),
            ),
            _component(
              '캐릭터 갤러리 (마이페이지 일러스트)',
              // 배경 제거 결과를 한눈에 훑어보기 위한 스토리 — 실제 MyActivityCard와
              // 동일한 표시 크기(200×214)·배경색(surfaceSoft)으로 10종 전부 렌더한다.
              SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.content),
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: _kCharacterIds.map((id) {
                    return Container(
                      width: 200,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 200,
                            height: 214,
                            child: Image.asset(
                              characterAssetPath(id),
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(id, style: AppTypography.caption),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            _component(
              '빈 상태 (EmptyState)',
              ListView(
                padding: const EdgeInsets.all(AppSpacing.content),
                children: const [
                  EmptyState(
                    icon: Icons.checklist_rounded,
                    message: '오늘 할 일이 없어요',
                    actionLabel: '투두 추가하기',
                    onAction: _noop,
                  ),
                  Divider(color: AppColors.borderSoft),
                  EmptyState(
                    icon: Icons.folder_outlined,
                    message: '아직 폴더가 없어요',
                    actionLabel: '폴더 추가하기',
                    onAction: _noop,
                  ),
                  Divider(color: AppColors.borderSoft),
                  EmptyState(
                    icon: Icons.search_off_rounded,
                    message: '검색 결과가 없어요',
                  ),
                  Divider(color: AppColors.borderSoft),
                  // 액션-only(홈): 아이콘·문구 없이 `+ 추가하기` 버튼만 중앙.
                  EmptyState(actionLabel: '투두 추가하기', onAction: _noop),
                  Divider(color: AppColors.borderSoft),
                  // 문구-only(일정탭): 추가 버튼이 우상단에 따로 있어 안내만.
                  EmptyState(message: '일정이 없어요'),
                ],
              ),
            ),
          ],
        ),
      ],
      lightTheme: AppTheme.light,
      header: const _WidgetbookHeader(),
      addons: [
        AlignmentAddon(initialAlignment: Alignment.topCenter),
        ViewportAddon([IosViewports.iPhone12, IosViewports.iPad]),
      ],
      appBuilder: (context, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: child,
      ),
    ),
  );
}

void _noop() {}

// 캐릭터 갤러리 스토리용 — MyActivityCard의 characterAssetPath가 매핑하는 id 전체.
const _kCharacterIds = [
  'PROCRASTINATOR',
  'GHOST',
  'LURKER',
  'TURTLE',
  'STEADY',
  'SPRINTER',
  'EARLYBIRD',
  'THE_J',
  'CHEERLEADER',
  'WARMING_UP',
];

WidgetbookComponent _component(String name, Widget child) {
  return WidgetbookComponent(
    name: name,
    useCases: [WidgetbookUseCase.child(name: '기본', child: child)],
  );
}

class _WidgetbookHeader extends StatelessWidget {
  const _WidgetbookHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
        SizedBox(width: 8),
        Text('모디 화면 카탈로그'),
      ],
    );
  }
}
