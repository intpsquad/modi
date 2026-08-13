import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/env.dart';
import '../../design/confirm_dialog.dart';
import '../../design/tokens.dart';
import '../../routing/app_session.dart';
import '../auth/authenticated_http_client.dart';
import '../auth/auth_service.dart';
import '../auth/share_auth_sync.dart';
import '../onboarding/intro_screen.dart';
import '../room/invite_share.dart';
import '../room/invite_share_options.dart';
import '../room/room_api.dart';
import '../room/room_cover_image_field.dart';
import '../room/room_form_fields.dart';
import '../room/room_session.dart';
import '../shell/app_shell.dart';
import '../shell/tab_activation.dart';
import 'my_activity_card.dart';

typedef TokenLoader = Future<String> Function();
typedef ContactEmailLauncher = Future<bool> Function(Uri uri);

const _supportEmailAddress = 'myeonglyeonghajim@gmail.com';

Future<bool> _launchContactEmail(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

class SettingsApi {
  SettingsApi({
    this.baseUrl = Env.apiBaseUrl,
    AuthenticatedHttpClient? client,
    http.Client? uploadClient,
  }) : _client = client ?? appAuthenticatedHttpClient,
       _uploadClient = uploadClient ?? http.Client();

  final String baseUrl;
  final AuthenticatedHttpClient _client;
  final http.Client _uploadClient;

  Future<UserProfile> fetchProfile(String idToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/me/profile'),
      idToken: idToken,
    );
    _checkOk(response, '프로필 조회');
    return UserProfile.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// 협업 캐릭터(마이 탭). 백엔드 `GET /me/character`(specs/0016) 조회.
  Future<MyActivitySummary> fetchCharacter(String idToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/me/character'),
      idToken: idToken,
    );
    _checkOk(response, '캐릭터 조회');
    return MyActivitySummary.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<UserProfile> updateProfile(
    String idToken, {
    required String nickname,
    String? profileImage,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/me/profile'),
      idToken: idToken,
      body: jsonEncode({'nickname': nickname, 'profileImage': profileImage}),
    );
    _checkOk(response, '프로필 저장');
    return UserProfile.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// 프로필 사진 2단계 업로드: 보호 API에서 presigned PUT URL을 받은 뒤 MinIO에 직접 전송한다.
  Future<String> uploadProfilePhoto(
    String idToken, {
    required List<int> bytes,
  }) async {
    final urlResponse = await _client.post(
      Uri.parse('$baseUrl/me/profile/photo/upload-url'),
      idToken: idToken,
    );
    _checkOk(urlResponse, '프로필 사진 업로드 준비');
    final body = jsonDecode(urlResponse.body) as Map<String, dynamic>;
    final uploadUrl = body['uploadUrl'] as String;
    final publicUrl = body['publicUrl'] as String;

    final uploadResponse = await _uploadClient.put(
      Uri.parse(uploadUrl),
      body: bytes,
    );
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw StateError('프로필 사진 업로드 실패 (${uploadResponse.statusCode})');
    }
    return publicUrl;
  }

  Future<NotificationSettings> fetchNotificationSettings(String idToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/me/notification-settings'),
      idToken: idToken,
    );
    _checkOk(response, '알림 설정 조회');
    return NotificationSettings.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<NotificationSettings> updateNotificationSettings(
    String idToken,
    NotificationSettings settings,
  ) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/me/notification-settings'),
      idToken: idToken,
      body: jsonEncode(settings.toJson()),
    );
    _checkOk(response, '알림 설정 저장');
    return NotificationSettings.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> updateRoom(
    String idToken,
    int roomId, {
    required String name,
    required String goal,
    String? goalDetail,
    required DateTime startDate,
    required DateTime endDate,
    String? coverImage,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl/rooms/$roomId'),
      idToken: idToken,
      body: jsonEncode({
        'name': name,
        'goal': goal,
        'goalDetail': goalDetail,
        'startDate': _date(startDate),
        'endDate': _date(endDate),
        'coverImage': coverImage,
      }),
    );
    _checkOk(response, '방 설정 저장');
  }

  Future<List<SettingsMember>> fetchMembers(String idToken, int roomId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/members/progress'),
      idToken: idToken,
    );
    _checkOk(response, '멤버 목록 조회');
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(SettingsMember.fromJson)
        .toList();
  }

  Future<String> reissueInviteCode(String idToken, int roomId) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/invite-code/reissue'),
      idToken: idToken,
    );
    _checkOk(response, '초대코드 재발급');
    return (jsonDecode(response.body) as Map<String, dynamic>)['inviteCode']
        as String;
  }

  Future<String> fetchInviteCode(String idToken, int roomId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/invite-code'),
      idToken: idToken,
    );
    _checkOk(response, '초대코드 조회');
    return (jsonDecode(response.body) as Map<String, dynamic>)['inviteCode']
        as String;
  }

  Future<void> leaveRoom(String idToken, int roomId) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/rooms/$roomId/members/me'),
      idToken: idToken,
    );
    if (response.statusCode != 204) {
      throw StateError('방 나가기 실패 (${response.statusCode})');
    }
  }

  /// 현재 Firebase 사용자와 연결된 앱 계정·개인 데이터를 영구 삭제한다.
  /// 서버 계약은 `DELETE /me`의 204 No Content다.
  Future<void> withdraw(String idToken) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/me'),
      idToken: idToken,
    );
    if (response.statusCode != 204) {
      throw StateError('회원 탈퇴 실패 (${response.statusCode})');
    }
  }

  Future<List<PastRoom>> fetchPastRooms(String idToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/past'),
      idToken: idToken,
    );
    _checkOk(response, '종료된 방 목록 조회');
    return (jsonDecode(response.body) as List)
        .cast<Map<String, dynamic>>()
        .map(PastRoom.fromJson)
        .toList();
  }

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  void _checkOk(http.Response response, String operation) {
    if (response.statusCode != 200) {
      throw StateError('$operation 실패 (${response.statusCode})');
    }
  }
}

class UserProfile {
  const UserProfile({
    required this.userId,
    required this.nickname,
    this.profileImage,
    this.loginProvider,
    this.createdAt,
  });

  final String userId;
  final String nickname;
  final String? profileImage;

  /// 로그인 수단: 'kakao' | 'google' | 'apple' | 'email'.
  /// 카카오는 Spring 커스텀 토큰이라 Firebase providerData로 프론트에서 알 수 없어
  /// 서버가 내려줘야 한다(docs/backend/my-page-handoff.md). 값이 없으면 배지 대신 placeholder.
  final String? loginProvider;

  /// 가입일(`users.created_at`, ISO-8601). 프로필 헤더 "MODI와 함께한 지 N일차…" 계산에 쓴다.
  /// 백엔드 `/me/profile`이 `createdAt`을 내려주면 자동 연결되고, 없으면 "함께하는 중!" 폴백
  /// (docs/backend/my-page-handoff.md §1).
  final DateTime? createdAt;

  UserProfile copyWith({String? nickname, String? profileImage}) => UserProfile(
    userId: userId,
    nickname: nickname ?? this.nickname,
    profileImage: profileImage ?? this.profileImage,
    loginProvider: loginProvider,
    createdAt: createdAt,
  );

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    userId: json['userId'] as String,
    nickname: json['nickname'] as String,
    profileImage: json['profileImage'] as String?,
    loginProvider: json['loginProvider'] as String?,
    createdAt: switch (json['createdAt']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    },
  );
}

class NotificationSettings {
  const NotificationSettings({
    required this.allEnabled,
    required this.pokeEnabled,
    this.scheduleDayBeforeEnabled = true,
    this.scheduleDdayEnabled = true,
    this.roomMemberJoinedEnabled = true,
    this.roomMemberLeftEnabled = true,
    this.assignedTodoAddedEnabled = true,
    this.archiveAnalysisDoneEnabled = true,
  });

  final bool allEnabled;
  final bool pokeEnabled;
  final bool scheduleDayBeforeEnabled;
  final bool scheduleDdayEnabled;
  final bool roomMemberJoinedEnabled;
  final bool roomMemberLeftEnabled;
  final bool assignedTodoAddedEnabled;
  final bool archiveAnalysisDoneEnabled;

  NotificationSettings copyWith({
    bool? allEnabled,
    bool? pokeEnabled,
    bool? scheduleDayBeforeEnabled,
    bool? scheduleDdayEnabled,
    bool? roomMemberJoinedEnabled,
    bool? roomMemberLeftEnabled,
    bool? assignedTodoAddedEnabled,
    bool? archiveAnalysisDoneEnabled,
  }) => NotificationSettings(
    allEnabled: allEnabled ?? this.allEnabled,
    pokeEnabled: pokeEnabled ?? this.pokeEnabled,
    scheduleDayBeforeEnabled:
        scheduleDayBeforeEnabled ?? this.scheduleDayBeforeEnabled,
    scheduleDdayEnabled: scheduleDdayEnabled ?? this.scheduleDdayEnabled,
    roomMemberJoinedEnabled:
        roomMemberJoinedEnabled ?? this.roomMemberJoinedEnabled,
    roomMemberLeftEnabled: roomMemberLeftEnabled ?? this.roomMemberLeftEnabled,
    assignedTodoAddedEnabled:
        assignedTodoAddedEnabled ?? this.assignedTodoAddedEnabled,
    archiveAnalysisDoneEnabled:
        archiveAnalysisDoneEnabled ?? this.archiveAnalysisDoneEnabled,
  );

  Map<String, dynamic> toJson() => {
    'allEnabled': allEnabled,
    'pokeEnabled': pokeEnabled,
    'scheduleDayBeforeEnabled': scheduleDayBeforeEnabled,
    'scheduleDdayEnabled': scheduleDdayEnabled,
    'roomMemberJoinedEnabled': roomMemberJoinedEnabled,
    'roomMemberLeftEnabled': roomMemberLeftEnabled,
    'assignedTodoAddedEnabled': assignedTodoAddedEnabled,
    'archiveAnalysisDoneEnabled': archiveAnalysisDoneEnabled,
  };

  factory NotificationSettings.fromJson(
    Map<String, dynamic> json,
  ) => NotificationSettings(
    allEnabled: json['allEnabled'] as bool,
    pokeEnabled: json['pokeEnabled'] as bool,
    scheduleDayBeforeEnabled: json['scheduleDayBeforeEnabled'] as bool? ?? true,
    scheduleDdayEnabled: json['scheduleDdayEnabled'] as bool? ?? true,
    roomMemberJoinedEnabled: json['roomMemberJoinedEnabled'] as bool? ?? true,
    roomMemberLeftEnabled: json['roomMemberLeftEnabled'] as bool? ?? true,
    assignedTodoAddedEnabled: json['assignedTodoAddedEnabled'] as bool? ?? true,
    archiveAnalysisDoneEnabled:
        json['archiveAnalysisDoneEnabled'] as bool? ?? true,
  );
}

class SettingsMember {
  const SettingsMember({
    required this.userId,
    required this.nickname,
    this.profileImage,
    required this.assignedTotal,
    required this.assignedDone,
  });

  final String userId;
  final String nickname;
  final String? profileImage;
  final int assignedTotal;
  final int assignedDone;

  int get progressPercent =>
      assignedTotal == 0 ? 0 : (assignedDone * 100 / assignedTotal).round();

  factory SettingsMember.fromJson(Map<String, dynamic> json) => SettingsMember(
    userId: json['userId'] as String,
    nickname: json['nickname'] as String,
    profileImage: json['profileImage'] as String?,
    assignedTotal: json['assignedTotal'] as int,
    assignedDone: json['assignedDone'] as int,
  );
}

class PastRoom {
  const PastRoom({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.completionRate,
  });

  final int id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final double completionRate;

  int get durationDays => endDate.difference(startDate).inDays + 1;
  int get completionPercent => (completionRate * 100).round();

  factory PastRoom.fromJson(Map<String, dynamic> json) => PastRoom(
    id: json['id'] as int,
    name: json['name'] as String,
    startDate: DateTime.parse(json['startDate'] as String),
    endDate: DateTime.parse(json['endDate'] as String),
    completionRate: (json['completionRate'] as num).toDouble(),
  );
}

/// S-40 설정 메인.
class SettingsScreen extends StatefulWidget {
  SettingsScreen({
    super.key,
    RoomSummary? currentRoom,
    AuthService? authService,
    SettingsApi? api,
    AppSession? session,
    RoomSession? roomSession,
    TabActivation? tabActivation,
    ContactEmailLauncher? contactEmailLauncher,
    this.tokenLoader,
  }) : currentRoom = currentRoom ?? _currentRoom(roomSession ?? appRoomSession),
       authService = authService ?? AuthService(),
       api = api ?? SettingsApi(),
       session = session ?? appSession,
       roomSession = roomSession ?? appRoomSession,
       tabActivation = tabActivation ?? appTabActivation,
       contactEmailLauncher = contactEmailLauncher ?? _launchContactEmail;

  final RoomSummary? currentRoom;
  final AuthService authService;
  final SettingsApi api;
  final AppSession session;
  final RoomSession roomSession;
  final TabActivation tabActivation;
  final ContactEmailLauncher contactEmailLauncher;
  final TokenLoader? tokenLoader;

  static RoomSummary? _currentRoom([RoomSession? roomSession]) {
    final activeSession = roomSession ?? appRoomSession;
    final id = activeSession.currentRoomId;
    if (id == null) return null;
    for (final room in activeSession.rooms) {
      if (room.id == id) return room;
    }
    return null;
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  RoomSummary? _currentRoom;
  UserProfile? _profile;
  int? _memberCount;
  MyActivitySummary? _character;
  bool _withdrawing = false;

  /// 마이 탭 재탭 시 맨 위로 스크롤(2026-08-09 QA, 홈과 같은 패턴)용 컨트롤러.
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _currentRoom = widget.currentRoom;
    widget.tabActivation.reselect.addListener(_onTabReselected);
    widget.roomSession.addListener(_onRoomSessionChanged);
    _loadProfileSummary();
    _loadMemberCount();
    _loadCharacter();
  }

  @override
  void dispose() {
    widget.tabActivation.reselect.removeListener(_onTabReselected);
    widget.roomSession.removeListener(_onRoomSessionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  /// 방 나가기·전환 등으로 전역 [RoomSession]이 바뀌면 이 화면의 "현재 방" 스냅샷도
  /// 함께 갱신한다 — 그렇지 않으면 stale한 방으로 다음 액션(예: 연속 방 나가기)이
  /// 잘못 나간다.
  void _onRoomSessionChanged() {
    if (!mounted) return;
    final resolved = SettingsScreen._currentRoom(widget.roomSession);
    if (resolved?.id == _currentRoom?.id) return;
    setState(() {
      _currentRoom = resolved;
      _memberCount = null;
    });
    _loadMemberCount();
  }

  /// 마이 탭을 **다시** 누르면(이미 마이인 상태) 맨 위로 부드럽게 스크롤한다.
  void _onTabReselected() {
    if (!mounted) return;
    if (widget.tabActivation.reselect.index != AppShell.mypageIndex) return;
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<String> _token() =>
      widget.tokenLoader?.call() ?? widget.authService.getIdToken();

  Future<void> _loadProfileSummary() async {
    try {
      final profile = await widget.api.fetchProfile(await _token());
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      // 프로필 보조 정보가 실패해도 설정 메뉴 자체는 계속 사용할 수 있어야 한다.
    }
  }

  Future<void> _loadMemberCount() async {
    final room = _currentRoom;
    if (room == null) return;
    try {
      final members = await widget.api.fetchMembers(await _token(), room.id);
      if (mounted) setState(() => _memberCount = members.length);
    } catch (_) {
      // 설정 메인은 멤버 수 보조 정보가 실패해도 나머지 메뉴를 계속 사용할 수 있어야 한다.
    }
  }

  Future<void> _loadCharacter() async {
    try {
      final character = await widget.api.fetchCharacter(await _token());
      if (mounted) setState(() => _character = character);
    } catch (_) {
      // 캐릭터는 보조 정보라 실패해도 카드가 placeholder로 남고 나머지는 계속 쓸 수 있다.
    }
  }

  /// 당겨서 새로고침 — 화면에 보이는 세 가지 비동기 정보(프로필·멤버 수·캐릭터)를 한꺼번에
  /// 다시 불러온다. 각 로더가 이미 자기 실패를 알아서 삼키므로(보조 정보라 개별 실패해도
  /// 나머지는 계속 쓸 수 있어야 한다는 기존 원칙) 여기서 별도 에러 처리를 하지 않는다.
  Future<void> _refresh() {
    return Future.wait([
      _loadProfileSummary(),
      _loadMemberCount(),
      _loadCharacter(),
    ]);
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showActionConfirmDialog(
      context: context,
      title: '로그아웃하시겠습니까?',
      message: '언제든 다시 로그인할 수 있어요.',
      confirmLabel: '로그아웃',
    );
    if (confirmed != true) return;
    await widget.authService.signOut();
    if (context.mounted) context.go('/onboarding/login');
  }

  Future<void> _withdraw(BuildContext context) async {
    if (_withdrawing) return;
    final confirmed = await showActionConfirmDialog(
      context: context,
      title: '정말 회원탈퇴하시겠습니까?',
      message: '탈퇴하면 계정과 활동 기록이 전부 삭제되고,\n이 작업은 절대 되돌릴 수 없어요.',
      confirmLabel: '회원탈퇴',
      confirmColor: AppColors.accentDanger,
      confirmKey: const ValueKey('confirm-withdrawal-button'),
      cancelKey: const ValueKey('cancel-withdrawal-button'),
    );
    if (confirmed != true || !context.mounted || _withdrawing) return;

    setState(() => _withdrawing = true);
    try {
      await widget.api.withdraw(await _token());
    } catch (_) {
      if (!mounted) return;
      setState(() => _withdrawing = false);
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(content: Text('회원 탈퇴를 완료하지 못했어요. 다시 시도해 주세요.')),
      );
      return;
    }

    // 서버가 204를 반환한 순간 계정 삭제는 완료됐다. Firebase Admin 삭제 또는
    // 로컬 signOut이 일시적으로 실패해도 기존 세션과 방 캐시로 재진입하지 못하게 한다.
    widget.session.setIntroStatus(completed: false);
    widget.session.markAccountWithdrawn();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(onboardingIntroCompletedKey);
    } catch (_) {
      // 메모리 게이트는 이미 초기화됐으므로 다음 화면으로는 안전하게 이동할 수 있다.
    }
    try {
      await widget.roomSession.clear();
    } catch (_) {
      // 메모리 캐시는 clear()에서 먼저 비워지고, 영속 키 제거 실패만 남을 수 있다.
    }
    try {
      await widget.authService.signOut();
    } catch (_) {
      // 서버 탈퇴가 성공한 뒤 signOut 오류로 사용자를 기존 화면에 남기지 않는다.
    }
    await ShareAuthSync.clearSharedSession();
    if (mounted) this.context.go('/onboarding/intro');
  }

  Future<void> _contact() async {
    final recipient = Uri(scheme: 'mailto', path: _supportEmailAddress);
    try {
      final opened = await widget.contactEmailLauncher(recipient);
      if (!opened && mounted) _showContactFallback();
    } catch (_) {
      if (mounted) _showContactFallback();
    }
  }

  void _showContactFallback() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '메일 앱을 열 수 없어요. myeonglyeonghajim@gmail.com으로 직접 문의해 주세요.',
        ),
      ),
    );
  }

  Future<void> _openProfile() async {
    await context.push('/mypage/profile');
    if (mounted) await _loadProfileSummary();
  }

  Future<void> _openRoomSettings() async {
    await context.push('/mypage/room');
    if (!mounted) return;

    final roomId = _currentRoom?.id;
    RoomSummary? refreshed;
    if (roomId != null) {
      for (final room in widget.roomSession.rooms) {
        if (room.id == roomId) {
          refreshed = room;
          break;
        }
      }
    }
    if (refreshed != null) setState(() => _currentRoom = refreshed);
  }

  @override
  Widget build(BuildContext context) {
    // 두 톤 배경(2026-08-07): 상단 흰색(프로필+활동 카드) / 하단 #F7F7F7(설정 그룹, 흰 카드).
    return Scaffold(
      backgroundColor: AppColors.surfaceSoft,
      appBar: AppBar(
        title: const Text('마이페이지'),
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      // 두 존만 있는 짧은 페이지 — 스크롤은 SingleChildScrollView(전부 빌드).
      // 당겨서 새로고침(2026-08-08) — 프로필·멤버 수·캐릭터 세 정보를 한꺼번에 다시 불러온다.
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: SingleChildScrollView(
          controller: _scrollController,
          // 콘텐츠가 화면을 다 못 채워도 당겨서 새로고침이 항상 동작하게.
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // ── 상단 흰색 존: 프로필 헤더 + 활동 카드 ──
              ColoredBox(
                color: AppColors.canvas,
                child: Padding(
                  // 좌우 20(디자이너 지정), 아래 22 후 회색 존 시작.
                  padding: const EdgeInsets.fromLTRB(20, AppSpacing.sm, 20, 22),
                  child: Column(
                    children: [
                      _ProfileHeaderRow(profile: _profile, onTap: _openProfile),
                      const SizedBox(height: 20),
                      MyActivityCard(
                        nickname: _profile?.nickname ?? '나',
                        summary: _character,
                        // 마이페이지는 이미 전체 맥락 — "모든 방 활동" 캡션 불필요(2026-08-09).
                        showScopeCaption: false,
                      ),
                    ],
                  ),
                ),
              ),
              // ── 하단 회색 존: 도메인별 그룹 카드 ──
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.content,
                  AppSpacing.content,
                  AppSpacing.content,
                  AppSpacing.content + MediaQuery.viewPaddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingsGroup(
                      title: '계정',
                      bordered: false,
                      dividers: false,
                      children: [
                        _SettingsTile(
                          title: '로그인 계정 정보',
                          // 로그인 수단 배지(카카오/구글/애플/이메일)만 표기 — 탭해도
                          // 하위 화면으로 넘어가지 않는다(onTap 없음). 서버 loginProvider가
                          // 오기 전엔 '연결됨' placeholder(docs/backend/my-page-handoff.md).
                          trailingWidget: _LoginProviderBadge.tryFrom(
                            _profile?.loginProvider,
                          ),
                          trailing: _profile?.loginProvider == null
                              ? '연결됨'
                              : null,
                        ),
                        _SettingsTile(
                          title: '알림 설정',
                          onTap: () => context.push('/mypage/notifications'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _SettingsGroup(
                      title: '방 관리',
                      bordered: false,
                      dividers: false,
                      children: [
                        _SettingsTile(
                          title: '현재 방 설정',
                          trailing: _currentRoom?.name ?? '선택된 방 없음',
                          onTap: _currentRoom == null
                              ? null
                              : _openRoomSettings,
                        ),
                        _SettingsTile(
                          title: '멤버 · 초대',
                          trailing: _memberCount == null
                              ? null
                              : '$_memberCount명',
                          onTap: _currentRoom == null
                              ? null
                              : () => context.push('/mypage/members'),
                        ),
                        _SettingsTile(
                          title: '종료된 방',
                          onTap: () => context.push('/mypage/past-rooms'),
                        ),
                        _SettingsTile(
                          title: '방 나가기',
                          danger: true,
                          onTap: _currentRoom == null
                              ? null
                              : () => _showLeaveDialog(context, _currentRoom!),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.base),
                    _SettingsGroup(
                      title: '정보 · 지원',
                      bordered: false,
                      dividers: false,
                      children: [
                        _SettingsTile(
                          title: '약관 · 정책',
                          onTap: () => context.push('/legal'),
                        ),
                        _SettingsTile(title: '문의하기', onTap: _contact),
                        const _SettingsTile(title: '버전 정보', trailing: '1.0.0'),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.base),
                    // 4번째 그룹(로그아웃·탈퇴)은 제목 없음(사용자 확정 2026-08-07).
                    _SettingsGroup(
                      bordered: false,
                      dividers: false,
                      children: [
                        _SettingsTile(
                          title: '로그아웃',
                          onTap: () => _logout(context),
                        ),
                        _SettingsTile(
                          title: '회원 탈퇴',
                          trailing: _withdrawing ? '처리 중...' : null,
                          danger: true,
                          onTap: _withdrawing ? null : () => _withdraw(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLeaveDialog(BuildContext context, RoomSummary room) async {
    final confirmed = await showActionConfirmDialog(
      context: context,
      title: '정말 이 방에서 나가시겠습니까?',
      message: '${room.name} 방의 모든 기록을 볼 수 없게 돼요.',
      confirmLabel: '방 나가기',
      confirmColor: AppColors.accentDanger,
      warning: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '마지막 멤버가 나가면 방 기록이 전부 삭제됩니다.',
          style: AppTypography.bodySmall.copyWith(
            fontSize: 13,
            color: AppColors.accentDanger,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final token = await _token();
      await widget.api.leaveRoom(token, room.id);
      await widget.roomSession.loadRooms(token);
      await widget.roomSession.resolveCurrentRoom();
      // resolveCurrentRoom은 알림을 안 보내므로(홈 _load 재귀 방지), 여기서 명시적으로 알려
      // 홈·탭들이 바뀐 "현재 방"으로 즉시 재조회하게 한다(방이 남은 경우). 방이 0개면
      // refreshMembership이 membership=none으로 만들어 라우터가 온보딩 허브로 보낸다.
      widget.roomSession.notifyCurrentRoomDataChanged();
      await widget.session.refreshMembership();
      if (context.mounted) context.go('/home');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('방에서 나가지 못했어요. 다시 시도해 주세요')),
        );
      }
    }
  }
}

class ProfileSettingsScreen extends StatefulWidget {
  ProfileSettingsScreen({
    super.key,
    SettingsApi? api,
    TokenLoader? tokenLoader,
    this.photoPicker,
  }) : api = api ?? SettingsApi(),
       tokenLoader = tokenLoader ?? AuthService().getIdToken;

  final SettingsApi api;
  final TokenLoader tokenLoader;
  final CoverImagePick? photoPicker;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  final _controller = TextEditingController();
  UserProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final token = await widget.tokenLoader();
      final profile = await widget.api.fetchProfile(token);
      if (!mounted) return;
      _controller.text = profile.nickname;
      setState(() => _profile = profile);
    } catch (_) {
      if (mounted) setState(() => _error = '프로필을 불러오지 못했어요');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final nickname = _controller.text.trim();
    if (nickname.isEmpty) {
      setState(() => _error = '닉네임을 입력해 주세요');
      return;
    }
    if (nickname.length > 10) {
      setState(() => _error = '닉네임은 10자 이내로 입력해 주세요');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final token = await widget.tokenLoader();
      final saved = await widget.api.updateProfile(
        token,
        nickname: nickname,
        profileImage: _profile?.profileImage,
      );
      if (!mounted) return;
      setState(() => _profile = saved);
      appRoomSession.notifyCurrentRoomDataChanged();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('프로필을 저장했어요')));
    } catch (_) {
      if (mounted) setState(() => _error = '프로필을 저장하지 못했어요');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    if (_uploadingPhoto || _saving) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final CoverImagePick picker =
          widget.photoPicker ??
          (imageSource) => ImagePicker().pickImage(
            source: imageSource,
            imageQuality: 85,
            maxWidth: 1200,
          );
      final file = await picker(source);
      if (file == null || !mounted) return;
      setState(() {
        _uploadingPhoto = true;
        _error = null;
      });
      final token = await widget.tokenLoader();
      final publicUrl = await widget.api.uploadProfilePhoto(
        token,
        bytes: await file.readAsBytes(),
      );
      if (!mounted) return;
      setState(() => _profile = _profile?.copyWith(profileImage: publicUrl));
    } catch (_) {
      if (mounted) setState(() => _error = '프로필 사진을 올리지 못했어요');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('프로필 수정')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.content),
                    children: [
                      Center(
                        child: _ProfilePhoto(
                          imageUrl: _profile?.profileImage,
                          fallback: _controller.text.isEmpty
                              ? '?'
                              : _controller.text[0],
                          uploading: _uploadingPhoto,
                          onTap: _pickPhoto,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Center(
                        child: Text(
                          '프로필 사진은 멤버 아바타로도 쓰여요',
                          style: AppTypography.caption,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const Text('닉네임', style: AppTypography.title),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        key: const ValueKey('profile-nickname-field'),
                        controller: _controller,
                        maxLength: 10,
                        enabled: !_saving && !_uploadingPhoto,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Text('아이디', style: AppTypography.title),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        key: const ValueKey('profile-user-id-field'),
                        initialValue: _profile?.userId ?? '',
                        enabled: false,
                        decoration: const InputDecoration(
                          filled: true,
                          fillColor: AppColors.surfaceSoft,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const Text(
                        '아이디는 변경할 수 없어요',
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
                      ],
                    ],
                  ),
                ),
                SafeArea(
                  minimum: const EdgeInsets.all(AppSpacing.content),
                  child: ElevatedButton(
                    onPressed: _saving || _uploadingPhoto ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : const Text('저장'),
                  ),
                ),
              ],
            ),
    );
  }
}

/// 화면에 노출되는 개별 알림 7종이 모두 켜져 있으면 true. "전체 알림" 토글의 파생 표시값.
/// (knockEnabled는 2026-08-09 모델에서 완전히 제거됐다 — 서버 정리와 같은 커밋.)
bool _notiVisibleAllOn(NotificationSettings s) =>
    s.pokeEnabled &&
    s.scheduleDayBeforeEnabled &&
    s.scheduleDdayEnabled &&
    s.roomMemberJoinedEnabled &&
    s.roomMemberLeftEnabled &&
    s.assignedTodoAddedEnabled &&
    s.archiveAnalysisDoneEnabled;

/// "전체 알림"을 켜고/끌 때 화면에 노출되는 개별 7종을 한 번에 [value]로 맞춘다(일괄 스위치).
NotificationSettings _notiSetAllVisible(NotificationSettings s, bool value) =>
    s.copyWith(
      pokeEnabled: value,
      scheduleDayBeforeEnabled: value,
      scheduleDdayEnabled: value,
      roomMemberJoinedEnabled: value,
      roomMemberLeftEnabled: value,
      assignedTodoAddedEnabled: value,
      archiveAnalysisDoneEnabled: value,
    );

class NotificationSettingsScreen extends StatefulWidget {
  NotificationSettingsScreen({
    super.key,
    SettingsApi? api,
    TokenLoader? tokenLoader,
  }) : api = api ?? SettingsApi(),
       tokenLoader = tokenLoader ?? AuthService().getIdToken;

  final SettingsApi api;
  final TokenLoader tokenLoader;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  NotificationSettings? _settings;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await widget.tokenLoader();
      final settings = await widget.api.fetchNotificationSettings(token);
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      if (mounted) setState(() => _error = '알림 설정을 불러오지 못했어요');
    }
  }

  Future<void> _save(NotificationSettings raw) async {
    // "전체 알림"은 개별을 막는 마스터 스위치가 아니라 **파생 상태**(개별이 전부 켜졌나)다.
    // 저장 직전 allEnabled를 개별 전체 ON 여부로 맞춰, 서버엔 항상 일관된 값이 간다.
    final next = raw.copyWith(allEnabled: _notiVisibleAllOn(raw));
    final previous = _settings;
    setState(() {
      _settings = next;
      _saving = true;
      _error = null;
    });
    try {
      final token = await widget.tokenLoader();
      final saved = await widget.api.updateNotificationSettings(token, next);
      if (mounted) setState(() => _settings = saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _settings = previous;
          _error = '알림 설정을 저장하지 못했어요';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      backgroundColor: AppColors.surfaceSoft,
      appBar: AppBar(
        title: const Text('알림 설정'),
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
      ),
      body: settings == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _ErrorState(message: _error!, onRetry: _load)
          : ListView(
              // 하단 시스템 제스처/네비 바에 마지막 항목이 가리지 않도록 inset 가산.
              padding: EdgeInsets.fromLTRB(
                AppSpacing.content,
                AppSpacing.content,
                AppSpacing.content,
                AppSpacing.content + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                _SettingsGroup(
                  bordered: false,
                  dividers: false,
                  children: [
                    SwitchListTile(
                      key: const ValueKey('all-notifications-switch'),
                      title: const Text('전체 알림'),
                      subtitle: const Text('한 번에 모두 켜고 끌 수 있어요'),
                      value: _notiVisibleAllOn(settings),
                      onChanged: _saving
                          ? null
                          : (value) =>
                                _save(_notiSetAllVisible(settings, value)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.base),
                _SettingsGroup(
                  title: '활동 알림',
                  bordered: false,
                  dividers: false,
                  children: [
                    SwitchListTile(
                      key: const ValueKey('poke-notifications-switch'),
                      title: const Text('콕 찌르기'),
                      subtitle: const Text('팀원이 콕 찌르면 알려드려요'),
                      value: settings.pokeEnabled,
                      onChanged: _saving
                          ? null
                          : (value) =>
                                _save(settings.copyWith(pokeEnabled: value)),
                    ),
                    // 🔴 「재촉 (노크)」 토글을 지웠다(2026-08-06). 끌 수 있는데 **아무것도 막지
                    // 않는 스위치**였다 — 콕찌르기와 재촉은 2026-07-29 에 같은 기능으로 통일됐고
                    // (specs/OPEN.md) 서버는 항상 type=POKE 로만 기록한다. knock_enabled 를
                    // 읽는 코드가 어디에도 없어서, 사용자가 꺼도 콕찌르기 알림은 그대로 왔었다.
                    //
                    // 2026-08-09: 모델·API 필드(knockEnabled)·서버 컬럼·DTO·PokeType.KNOCK을
                    // 전부 제거했다(specs/OPEN.md, V27__drop_knock_enabled.sql).
                  ],
                ),
                const SizedBox(height: AppSpacing.base),
                _SettingsGroup(
                  title: '일정 알림',
                  bordered: false,
                  dividers: false,
                  children: [
                    SwitchListTile(
                      key: const ValueKey(
                        'schedule-day-before-notifications-switch',
                      ),
                      title: const Text('일정 전날'),
                      subtitle: const Text('내일 일정이 있으면 알려드려요'),
                      value: settings.scheduleDayBeforeEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => _save(
                              settings.copyWith(
                                scheduleDayBeforeEnabled: value,
                              ),
                            ),
                    ),
                    SwitchListTile(
                      key: const ValueKey('schedule-dday-notifications-switch'),
                      title: const Text('일정 당일'),
                      subtitle: const Text('오늘 일정이 있으면 알려드려요'),
                      value: settings.scheduleDdayEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => _save(
                              settings.copyWith(scheduleDdayEnabled: value),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.base),
                _SettingsGroup(
                  title: '방 활동 알림',
                  bordered: false,
                  dividers: false,
                  children: [
                    SwitchListTile(
                      key: const ValueKey(
                        'room-member-joined-notifications-switch',
                      ),
                      title: const Text('새 멤버 참여'),
                      subtitle: const Text('새 멤버가 방에 참여하면 알려드려요'),
                      value: settings.roomMemberJoinedEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => _save(
                              settings.copyWith(roomMemberJoinedEnabled: value),
                            ),
                    ),
                    SwitchListTile(
                      key: const ValueKey(
                        'room-member-left-notifications-switch',
                      ),
                      title: const Text('멤버 방 나가기'),
                      subtitle: const Text('멤버가 방을 나가면 알려드려요'),
                      value: settings.roomMemberLeftEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => _save(
                              settings.copyWith(roomMemberLeftEnabled: value),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.base),
                _SettingsGroup(
                  title: '투두 알림',
                  bordered: false,
                  dividers: false,
                  children: [
                    SwitchListTile(
                      key: const ValueKey(
                        'assigned-todo-added-notifications-switch',
                      ),
                      title: const Text('담당 투두 추가'),
                      subtitle: const Text('다른 멤버가 내 담당 투두를 추가하면 알려드려요'),
                      value: settings.assignedTodoAddedEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => _save(
                              settings.copyWith(
                                assignedTodoAddedEnabled: value,
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.base),
                _SettingsGroup(
                  title: '모아보기 알림',
                  bordered: false,
                  dividers: false,
                  children: [
                    SwitchListTile(
                      key: const ValueKey(
                        'archive-analysis-done-notifications-switch',
                      ),
                      title: const Text('자료 분석 결과'),
                      // 문구가 "완료"만 말하지 않는 이유: 실패했을 때도 이 스위치로 알린다.
                      subtitle: const Text('내가 올린 자료의 분석이 끝나거나 실패하면 알려드려요'),
                      value: settings.archiveAnalysisDoneEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => _save(
                              settings.copyWith(
                                archiveAnalysisDoneEnabled: value,
                              ),
                            ),
                    ),
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
              ],
            ),
    );
  }
}

class RoomSettingsScreen extends StatefulWidget {
  RoomSettingsScreen({
    super.key,
    RoomSummary? room,
    SettingsApi? api,
    TokenLoader? tokenLoader,
    RoomApi? roomApi,
    this.coverPicker,
  }) : room = room ?? SettingsScreen._currentRoom(),
       api = api ?? SettingsApi(),
       tokenLoader = tokenLoader ?? AuthService().getIdToken,
       roomApi = roomApi ?? RoomApi();

  final RoomSummary? room;
  final SettingsApi api;
  final TokenLoader tokenLoader;

  /// 대표 이미지 업로드용(범용 `/rooms/cover-image`). SettingsApi와 별개.
  final RoomApi roomApi;

  /// 테스트용 이미지 피커 주입(기본 null = image_picker 실제 사용).
  final CoverImagePick? coverPicker;

  @override
  State<RoomSettingsScreen> createState() => _RoomSettingsScreenState();
}

class _RoomSettingsScreenState extends State<RoomSettingsScreen> {
  late final TextEditingController _name;
  late final TextEditingController _goal;

  /// 시작일은 방이 이미 시작했으므로 화면에 노출/편집하지 않고 기존 값을 그대로 유지한다
  /// (방 만들기 화면과 동일하게 "종료일만" 노출 — 2026-08-07 확정). 저장 시 그대로 전송.
  late DateTime _startDate;
  late DateTime _endDate;
  String? _coverImage;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    _name = TextEditingController(text: room?.name ?? '')
      ..addListener(_onChanged);
    _goal = TextEditingController(text: room?.goal ?? '')
      ..addListener(_onChanged);
    _startDate = room?.startDate ?? DateTime.now();
    _endDate = room?.endDate ?? DateTime.now();
    _coverImage = room?.coverImage;
  }

  void _onChanged() => setState(() {});

  bool get _canSubmit =>
      _name.text.trim().isNotEmpty && _goal.text.trim().isNotEmpty;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<String> _uploadCover(XFile file) async {
    final token = await widget.tokenLoader();
    final bytes = await file.readAsBytes();
    return widget.roomApi.uploadCoverImage(
      token,
      bytes: bytes,
      filename: file.name,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _pickEndDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(today) ? today : _endDate,
      firstDate: today,
      lastDate: DateTime(today.year + 5),
      useRootNavigator: false,
    );
    if (picked == null) return;
    setState(() => _endDate = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _save() async {
    final room = widget.room;
    if (room == null || !_canSubmit) return;
    if (_name.text.trim().length > 30) {
      setState(() => _error = '방 이름은 30자 이내로 입력해 주세요');
      return;
    }
    if (_endDate.isBefore(_startDate)) {
      setState(() => _error = '종료일은 시작일보다 빠를 수 없어요');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final token = await widget.tokenLoader();
      await widget.api.updateRoom(
        token,
        room.id,
        name: _name.text.trim(),
        goal: _goal.text.trim(),
        goalDetail: room.goalDetail,
        startDate: _startDate,
        endDate: _endDate,
        coverImage: _coverImage,
      );
      await appRoomSession.loadRooms(token);
      appRoomSession.notifyCurrentRoomDataChanged();
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) setState(() => _error = '방 설정을 저장하지 못했어요');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.room == null) {
      return const Scaffold(body: Center(child: Text('현재 선택된 방이 없어요')));
    }
    // 방 만들기(S-10)와 동일한 토스풍 소프트필 폼 — 현재 방 값이 프리필된 상태.
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('현재 방 설정')),
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
                    const Text('방 설정을\n바꿔볼까요?', style: AppTypography.display),
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
                      initialUrl: _coverImage,
                      uploadImage: _uploadCover,
                      onChanged: (url) => setState(() => _coverImage = url),
                      pickImage: widget.coverPicker,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    RoomSoftField(
                      fieldKey: const ValueKey('room-name-field'),
                      label: '방 이름',
                      controller: _name,
                      hint: '방 이름을 입력해 주세요',
                      enabled: !_saving,
                      maxLength: 30,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    RoomSoftField(
                      fieldKey: const ValueKey('room-goal-field'),
                      label: '방 목표',
                      controller: _goal,
                      hint: '팀원들과 함께 달성할 목표를 적어주세요',
                      enabled: !_saving,
                      maxLines: 3,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    RoomDateField(
                      label: '종료 날짜',
                      value: _formatDate(_endDate),
                      onTap: _saving ? null : _pickEndDate,
                      helperText: '기한이 지나면 방이 자동으로 종료 상태로 전환돼요',
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
                  onPressed: (_saving || !_canSubmit) ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
                          ),
                        )
                      : const Text('저장'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MembersSettingsScreen extends StatefulWidget {
  MembersSettingsScreen({
    super.key,
    RoomSummary? room,
    SettingsApi? api,
    TokenLoader? tokenLoader,
    String? currentUserId,
    ShareInviteFn? shareInvite,
    KakaoInviteShareFn? shareKakao,
    CopyFn? copy,
    LaunchAppFn? launchApp,
  }) : room = room ?? SettingsScreen._currentRoom(),
       api = api ?? SettingsApi(),
       tokenLoader = tokenLoader ?? AuthService().getIdToken,
       currentUserId = currentUserId ?? appSession.currentUserId,
       shareInvite = shareInvite ?? shareInviteText,
       shareKakao = shareKakao ?? shareInviteToKakao,
       copy = copy ?? copyToClipboard,
       launchApp = launchApp ?? launchExternalApp;

  final RoomSummary? room;
  final SettingsApi api;
  final TokenLoader tokenLoader;
  final String? currentUserId;
  final ShareInviteFn shareInvite;
  final KakaoInviteShareFn shareKakao;
  final CopyFn copy;
  final LaunchAppFn launchApp;

  @override
  State<MembersSettingsScreen> createState() => _MembersSettingsScreenState();
}

class _MembersSettingsScreenState extends State<MembersSettingsScreen> {
  List<SettingsMember>? _members;
  String? _inviteCode;
  String? _error;
  bool _reissuing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final room = widget.room;
    if (room == null) return;
    try {
      final token = await widget.tokenLoader();
      final members = await widget.api.fetchMembers(token, room.id);
      final inviteCode = await widget.api.fetchInviteCode(token, room.id);
      if (mounted) {
        setState(() {
          _members = members;
          _inviteCode = inviteCode;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '멤버를 불러오지 못했어요');
    }
  }

  Future<void> _reissue() async {
    final room = widget.room;
    if (room == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('초대코드를 재발급할까요?'),
        content: const Text('기존 코드는 즉시 무효화돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('재발급'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _reissuing = true);
    try {
      final token = await widget.tokenLoader();
      final code = await widget.api.reissueInviteCode(token, room.id);
      if (mounted) setState(() => _inviteCode = code);
    } catch (_) {
      if (mounted) setState(() => _error = '초대코드를 재발급하지 못했어요');
    } finally {
      if (mounted) setState(() => _reissuing = false);
    }
  }

  Future<void> _shareCode() async {
    final code = _inviteCode;
    final room = widget.room;
    if (code == null || room == null) {
      // 코드가 아직 없으면(만료/미로딩) 먼저 재발급을 유도한다.
      await _reissue();
      return;
    }
    await showInviteShareOptions(
      context,
      invite: InviteShareData(
        roomId: room.id,
        code: code,
        roomName: room.name,
        coverImage: room.coverImage,
      ),
      shareInvite: widget.shareInvite,
      shareKakao: widget.shareKakao,
      copy: widget.copy,
      launchApp: widget.launchApp,
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    // 마이페이지(S-40)와 같은 톤 — 회색 배경 + 흰 그룹 카드(테두리·구분선 없음).
    return Scaffold(
      backgroundColor: AppColors.surfaceSoft,
      appBar: AppBar(
        title: const Text('방 멤버 관리'),
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
      ),
      body: widget.room == null
          ? const Center(child: Text('현재 선택된 방이 없어요'))
          : members == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _ErrorState(message: _error!, onRetry: _load)
          : ListView(
              // 하단 시스템 제스처/네비 바에 공유/재발급 버튼이 가리지 않도록 inset 가산.
              padding: EdgeInsets.fromLTRB(
                AppSpacing.content,
                AppSpacing.content,
                AppSpacing.content,
                AppSpacing.content + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                _SettingsGroup(
                  title: '멤버 ${members.length}명',
                  bordered: false,
                  dividers: false,
                  children: [
                    for (final member in members)
                      ListTile(
                        leading: _MemberProgressAvatar(member: member),
                        title: Text(
                          member.userId == widget.currentUserId
                              ? '${member.nickname} (나)'
                              : member.nickname,
                        ),
                        subtitle: Text('개인 진행률 ${member.progressPercent}%'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.base),
                _SettingsGroup(
                  title: '초대 코드',
                  bordered: false,
                  dividers: false,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.base,
                        0,
                        AppSpacing.base,
                        AppSpacing.base,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _inviteCode ?? '초대코드를 불러오는 중이에요',
                            style: AppTypography.display,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _reissuing ? null : _shareCode,
                                  icon: const Icon(Icons.ios_share, size: 18),
                                  label: const Text('공유'),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _reissuing ? null : _reissue,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: Text(_reissuing ? '재발급 중' : '재발급'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            '재발급하면 기존 코드는 즉시 무효화돼요',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class PastRoomsScreen extends StatefulWidget {
  PastRoomsScreen({super.key, SettingsApi? api, TokenLoader? tokenLoader})
    : api = api ?? SettingsApi(),
      tokenLoader = tokenLoader ?? AuthService().getIdToken;

  final SettingsApi api;
  final TokenLoader tokenLoader;

  @override
  State<PastRoomsScreen> createState() => _PastRoomsScreenState();
}

class _PastRoomsScreenState extends State<PastRoomsScreen> {
  List<PastRoom>? _rooms;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final token = await widget.tokenLoader();
      final rooms = await widget.api.fetchPastRooms(token);
      if (mounted) setState(() => _rooms = rooms);
    } catch (_) {
      if (mounted) setState(() => _error = '종료된 방을 불러오지 못했어요');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    return Scaffold(
      backgroundColor: AppColors.surfaceSoft,
      appBar: AppBar(
        title: const Text('종료된 방'),
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
      ),
      body: rooms == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _ErrorState(message: _error!, onRetry: _load)
          : rooms.isEmpty
          ? const Center(child: Text('아직 종료된 방이 없어요'))
          : ListView(
              // 하단 시스템 제스처/네비 바에 마지막 방 카드가 가리지 않도록 inset 가산.
              padding: EdgeInsets.fromLTRB(
                AppSpacing.content,
                AppSpacing.content,
                AppSpacing.content,
                AppSpacing.content + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                Text(
                  '종료된 방 ${rooms.length}개 · 탭하면 요약 홈으로 이동해요',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final room in rooms) ...[
                  Material(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.push('/home?endedRoomId=${room.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.base),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: AppSpacing.xxl,
                                  height: AppSpacing.xxl,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceSoft,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.small,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.flag_outlined,
                                    color: AppColors.mutedSoft,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        room.name,
                                        style: AppTypography.title,
                                      ),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        '${_formatDate(room.endDate)} 종료 · '
                                        '진행 ${room.durationDays}일',
                                        style: AppTypography.caption,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: AppSpacing.xs,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceSoft,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.pill,
                                    ),
                                  ),
                                  child: const Text(
                                    '종료됨',
                                    style: AppTypography.badge,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            LinearProgressIndicator(
                              value: room.completionRate.clamp(0, 1),
                              minHeight: AppSpacing.xs,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '최종 ${room.completionPercent}%',
                                style: AppTypography.caption,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

class _ProfilePhoto extends StatelessWidget {
  const _ProfilePhoto({
    required this.imageUrl,
    required this.fallback,
    required this.uploading,
    required this.onTap,
  });

  final String? imageUrl;
  final String fallback;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '프로필 사진 변경',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox.square(
            dimension: AppSpacing.xxl * 2,
            child: ClipOval(
              child: ColoredBox(
                color: AppColors.surfaceSoft,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl == null || imageUrl!.isEmpty)
                      Center(
                        child: Text(fallback, style: AppTypography.display),
                      )
                    else
                      Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(
                          child: Text(fallback, style: AppTypography.display),
                        ),
                      ),
                    if (uploading)
                      const ColoredBox(
                        color: AppColors.scrim,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -AppSpacing.xs,
            bottom: -AppSpacing.xs,
            child: Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                key: const ValueKey('profile-photo-button'),
                onTap: uploading ? null : onTap,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Icon(
                    Icons.camera_alt_outlined,
                    size: AppSpacing.base,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberProgressAvatar extends StatelessWidget {
  const _MemberProgressAvatar({required this.member});

  final SettingsMember member;

  @override
  Widget build(BuildContext context) {
    final progress = member.progressPercent / 100;
    return SizedBox.square(
      dimension: AppSpacing.xxl - AppSpacing.xs,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              key: ValueKey('member-progress-${member.userId}'),
              value: progress.clamp(0, 1),
              strokeWidth: 3,
              backgroundColor: AppColors.borderSoft,
              color: AppColors.primary,
            ),
          ),
          SizedBox.square(
            dimension: AppSpacing.xl + AppSpacing.xs,
            child: CircleAvatar(
              backgroundColor: AppColors.surfaceSoft,
              backgroundImage: _networkImage(member.profileImage),
              child: member.profileImage == null || member.profileImage!.isEmpty
                  ? Text(
                      member.nickname.isEmpty ? '?' : member.nickname[0],
                      style: AppTypography.caption.copyWith(
                        color: AppColors.foregroundSoft,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.children,
    this.title,
    this.bordered = true,
    this.dividers = true,
  });

  final List<Widget> children;

  /// 흰 카드 안 맨 위에 놓는 그룹 제목(마이페이지: 계정/방 관리/정보·지원). 16/700 #222222.
  /// null이면 제목 없음(로그아웃·탈퇴 그룹, 하위 화면 그룹).
  final String? title;

  /// 회색 배경(마이 페이지)에서는 테두리 없이 흰 카드만으로 대비를 만든다.
  final bool bordered;

  /// 행 사이 구분선. 마이페이지 카드는 구분선 없음(2026-08-07 요청). 하위 화면은 기본 유지.
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: bordered
            ? const BorderSide(color: AppColors.border)
            : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text(
                title!,
                style: AppTypography.title.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                ),
              ),
            ),
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (dividers && index != children.length - 1)
              const Divider(height: 1, indent: 16),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    this.trailing,
    this.trailingWidget,
    this.danger = false,
    this.onTap,
  });

  // 마이페이지 리디자인(2026-08-07): 행 leading 아이콘을 전부 제거 — 아이콘 없음.
  final String title;
  final String? trailing;

  /// [trailing] 텍스트 대신 임의 위젯을 오른쪽에 놓을 때(예: 로그인 수단 배지). 있으면 우선.
  final Widget? trailingWidget;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 행 라벨 = #6A6A6A 14/medium(2026-08-08: 다른 화면 대비 작아 13→14). 파괴적 액션만 accentDanger.
    final color = danger ? AppColors.accentDanger : AppColors.muted;
    return ListTile(
      visualDensity: const VisualDensity(vertical: -2),
      title: Text(
        title,
        style: AppTypography.bodySmall.copyWith(
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingWidget != null)
            trailingWidget!
          else if (trailing != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                trailing!,
                style: AppTypography.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (onTap != null)
            const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
      enabled: onTap != null || trailing != null || trailingWidget != null,
      onTap: onTap,
    );
  }
}

/// 로그인 수단 배지 — '로그인 계정 정보' 행 오른쪽. 브랜드 지정 색이라 design.md 토큰 밖
/// (specs/OPEN.md 드리프트 참고). 글씨는 전부 12/700, 색 #222222(애플만 #FFFFFF).
class _LoginProviderBadge extends StatelessWidget {
  const _LoginProviderBadge._(
    this.label,
    this.background,
    this.foreground, {
    this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? border;

  /// 알 수 없는/없는 값이면 null → 호출부가 '연결됨' placeholder로 대체.
  /// 서버가 대문자('KAKAO')로 줘도 받도록 소문자로 정규화한다.
  static Widget? tryFrom(String? provider) {
    switch (provider?.toLowerCase()) {
      case 'kakao':
        return const _LoginProviderBadge._(
          '카카오 로그인',
          Color(0xFFFEE500),
          Color(0xFF222222),
        );
      case 'google':
        return const _LoginProviderBadge._(
          '구글 로그인',
          Color(0xFFF2F2F2),
          Color(0xFF222222),
        );
      case 'apple':
        return const _LoginProviderBadge._(
          '애플 로그인',
          Color(0xFF000000),
          Color(0xFFFFFFFF),
        );
      case 'email':
        return const _LoginProviderBadge._(
          '이메일 로그인',
          Color(0x00000000),
          Color(0xFF222222),
          border: Color(0xFFDDDDDD),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

/// 하위 화면(알림·멤버)에서 카드 밖에 두는 작은 섹션 라벨. 마이페이지는 카드 안 제목
/// (`_SettingsGroup.title`)을 쓰므로 이 위젯을 쓰지 않는다.
/// 마이페이지 상단 프로필 행 — 아바타 60 + 닉네임 + 'MODI와 함께한 지 …' 캡션 + 꺽쇠.
/// 흰색 상단 존 위에 카드 없이 얹는다. 탭하면 프로필 편집.
class _ProfileHeaderRow extends StatelessWidget {
  const _ProfileHeaderRow({required this.profile, required this.onTap});

  final UserProfile? profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nickname = profile?.nickname ?? '내 정보';
    final imageUrl = profile?.profileImage;
    final initial = nickname.isEmpty ? '?' : nickname[0];

    return Semantics(
      button: true,
      label: '프로필 수정',
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            // 아바타 60×60 (디자이너 지정 = xxl 48 + md 12).
            SizedBox.square(
              dimension: AppSpacing.xxl + AppSpacing.md,
              child: ClipOval(
                child: ColoredBox(
                  color: AppColors.surfaceSoft,
                  child: (imageUrl == null || imageUrl.isEmpty)
                      ? Center(
                          child: Text(initial, style: AppTypography.section),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Center(
                            child: Text(initial, style: AppTypography.section),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nickname,
                    style: AppTypography.section,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text.rich(
                    TextSpan(children: _modiTogetherSpans(profile?.createdAt)),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.foreground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Image.asset(
              'assets/icons/angle_bracket.png',
              height: AppSpacing.base,
              color: AppColors.mutedSoft,
              errorBuilder: (_, _, _) => const Icon(
                Icons.chevron_right,
                size: AppSpacing.base,
                color: AppColors.mutedSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "MODI와 함께한 지 N일차/N달째/N년차" 문구 스팬. MODI·기간 단위는 볼드(w700), 나머지 레귤러.
/// [joinDate]는 `UserProfile.createdAt`이 연결된다. null(백엔드가 `/me/profile`에 아직
/// `createdAt`을 안 내려줌)이면 "MODI와 함께하는 중!" 폴백 (docs/backend/my-page-handoff.md §1).
List<InlineSpan> _modiTogetherSpans(DateTime? joinDate) {
  const bold = TextStyle(fontWeight: FontWeight.w700);
  const fallback = [
    TextSpan(text: 'MODI', style: bold),
    TextSpan(text: '와 함께하는 중!'),
  ];
  if (joinDate == null) return fallback;
  final today = DateTime.now();
  final days =
      DateTime(today.year, today.month, today.day)
          .difference(DateTime(joinDate.year, joinDate.month, joinDate.day))
          .inDays +
      1;
  // 미래/시계 오차로 days<=0이면 '0일차'/'-3일차'를 렌더하지 않고 폴백(백엔드 createdAt 대기).
  if (days < 1) return fallback;
  final String unit;
  if (days <= 30) {
    unit = '$days일차';
  } else if (days <= 364) {
    unit = '${(days / 30).floor().clamp(1, 12)}달째';
  } else {
    unit = '${(days / 365).floor()}년차';
  }
  return [
    const TextSpan(text: 'MODI', style: bold),
    const TextSpan(text: '와 함께한 지 '),
    TextSpan(text: unit, style: bold),
    const TextSpan(text: '!'),
  ];
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.content),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: AppTypography.bodySmall),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.'
    '${date.day.toString().padLeft(2, '0')}';

ImageProvider? _networkImage(String? value) {
  if (value == null || value.isEmpty) return null;
  return NetworkImage(value);
}
