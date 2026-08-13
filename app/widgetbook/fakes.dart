import 'package:app/features/archive/archive_api.dart';
import 'package:app/features/auth/auth_service.dart';
import 'package:app/features/home/home_api.dart';
import 'package:app/features/member/member_todos_screen.dart';
import 'package:app/features/room/room_api.dart';
import 'package:app/features/room/room_session.dart';
import 'package:app/features/schedule/schedule_api.dart';
import 'package:app/features/settings/my_activity_card.dart';
import 'package:app/features/settings/settings_screens.dart';
import 'package:app/features/todos/todos_api.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Widgetbook에서 화면을 독립적으로 확인하기 위한 인증 어댑터.
/// 실제 Firebase 세션이나 네트워크 토큰을 사용하지 않는다.
class StoryAuthService extends AuthService {
  StoryAuthService({this.userId = 'story-user'});

  final String userId;

  @override
  Future<User> signInWithGoogle() async {
    throw StateError('Widgetbook에서는 Google 로그인을 사용할 수 없습니다.');
  }

  @override
  Future<User> signInWithKakao() async {
    throw StateError('Widgetbook에서는 카카오 로그인을 사용할 수 없습니다.');
  }

  @override
  String get currentUserId => userId;

  @override
  Future<String> getIdToken() async => 'widgetbook-story-token';

  @override
  Future<void> signUpWithEmail({
    required String email,
    required String nickname,
    required String password,
    String? profileImage,
  }) async {}

  @override
  Future<void> signOut() async {}
}

final storyActiveRoom = RoomSummary(
  id: 42,
  name: '모디 팀 프로젝트',
  goal: '이번 주 스프린트 목표 달성하기',
  goalDetail: '매주 문제를 풀고 금요일마다 함께 리뷰한다.',
  status: 'ACTIVE',
  startDate: DateTime(2026, 7, 1),
  endDate: DateTime(2026, 8, 31),
);

final storyEndedRoom = RoomSummary(
  id: 43,
  name: '지난 사이드 프로젝트',
  goal: 'MVP 출시',
  status: 'ENDED',
  startDate: DateTime(2026, 5, 1),
  endDate: DateTime(2026, 6, 30),
);

/// 각 화면이 같은 "현재 방"을 바라보도록 만드는 고정 세션.
class StoryRoomSession extends RoomSession {
  StoryRoomSession({this.roomId = 42});

  final int roomId;

  @override
  Future<void> loadRooms(String idToken) async {
    rooms = [
      RoomSummary(
        id: roomId,
        name: '모디 팀 프로젝트',
        goal: '이번 주 스프린트 목표 달성하기',
        status: 'ACTIVE',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 8, 31),
      ),
      RoomSummary(
        id: roomId + 1,
        name: '지난 사이드 프로젝트',
        goal: 'MVP 출시',
        status: 'ENDED',
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 6, 30),
      ),
    ];
  }

  @override
  Future<RoomResolution> resolveCurrentRoom() async {
    currentRoomId = roomId;
    return const RoomResolution(roomId: 42, switchedFromEnded: false);
  }

  @override
  Future<void> switchRoom(int nextRoomId) async {
    currentRoomId = nextRoomId;
    notifyListeners();
  }
}

class StoryHomeApi extends HomeApi {
  StoryHomeApi();

  @override
  Future<DashboardData> fetchDashboard(
    String idToken,
    int roomId, {
    required DateTime weekStart,
    required DateTime weekEnd,
  }) async {
    return DashboardData(
      room: RoomInfo(
        id: roomId,
        name: '모디 팀 프로젝트',
        goal: '팀 목표를 한눈에 보고 이번 주 실행으로 연결하기',
        goalDetail: '각자의 투두와 일정을 공유하며 함께 완주해요.',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 8, 31),
        status: 'ACTIVE',
      ),
      members: [
        MemberProgress(
          userId: 'story-user',
          nickname: '정남준',
          assignedTotal: 8,
          assignedDone: 5,
        ),
        MemberProgress(
          userId: 'story-member-1',
          nickname: '김모디',
          assignedTotal: 6,
          assignedDone: 4,
        ),
        MemberProgress(
          userId: 'story-member-2',
          nickname: '이협업',
          assignedTotal: 5,
          assignedDone: 2,
        ),
      ],
      weekSchedules: [
        ScheduleBrief(
          id: 1,
          title: '주간 회고',
          date: weekStart.add(const Duration(days: 2)),
          time: '19:00:00',
        ),
        ScheduleBrief(
          id: 2,
          title: '데모 준비',
          date: weekStart.add(const Duration(days: 4)),
          time: '14:00:00',
        ),
      ],
      todayTodos: [
        TodoBrief(id: 1, title: 'Widgetbook 스토리 초안 만들기', completed: true),
        TodoBrief(id: 2, title: 'Firebase 웹 설정 확인하기', completed: false),
        TodoBrief(id: 3, title: '팀 리뷰 반영하기', completed: false),
      ],
      recentArchives: [
        ArchiveBrief(
          id: 1,
          title: 'Widgetbook 도입 가이드',
          pinned: true,
          likeCount: 7,
        ),
        ArchiveBrief(id: 2, title: '모디 화면 설계 문서', pinned: false, likeCount: 3),
      ],
    );
  }

  @override
  Future<void> setTodoCompleted(
    String idToken,
    int roomId,
    int todoId,
    bool completed,
  ) async {}
}

class StoryTodosApi extends TodosApi {
  StoryTodosApi();

  final _members = [
    MemberBrief(userId: 'story-user', nickname: '정남준'),
    MemberBrief(userId: 'story-member-1', nickname: '김모디'),
  ];

  final _categories = [
    Category(id: 1, name: '기획'),
    Category(id: 2, name: '개발'),
    Category(id: 3, name: '디자인'),
  ];

  final _todos = [
    TodoItem(
      id: 1,
      title: 'Widgetbook 스토리 초안 만들기',
      detail: '주요 페이지의 기본 상태를 먼저 등록한다.',
      completed: false,
      categoryId: 2,
      assignees: [MemberBrief(userId: 'story-user', nickname: '정남준')],
    ),
    TodoItem(
      id: 2,
      title: '온보딩 문구 최종 확인',
      completed: true,
      categoryId: 1,
      assignees: [MemberBrief(userId: 'story-member-1', nickname: '김모디')],
    ),
    TodoItem(
      id: 3,
      title: '빈 상태 화면 카피 정리',
      detail: '사용자가 다음 행동을 바로 이해할 수 있도록 정리한다.',
      completed: false,
      categoryId: null,
      assignees: [],
    ),
    TodoItem(
      id: 4,
      title: '팀 리뷰 반영하기',
      completed: false,
      categoryId: 3,
      assignees: [MemberBrief(userId: 'story-user', nickname: '정남준')],
    ),
  ];

  @override
  Future<List<Category>> fetchCategories(String idToken, int roomId) async =>
      _categories;

  @override
  Future<List<TodoItem>> fetchTodos(String idToken, int roomId) async => _todos;

  @override
  Future<List<MemberBrief>> fetchMembers(String idToken, int roomId) async =>
      _members;

  @override
  Future<Category> createCategory(
    String idToken,
    int roomId,
    String name,
  ) async => Category(id: 99, name: name);

  @override
  Future<Category> renameCategory(
    String idToken,
    int roomId,
    int categoryId,
    String name,
  ) async => Category(id: categoryId, name: name);

  @override
  Future<void> deleteCategory(
    String idToken,
    int roomId,
    int categoryId,
  ) async {}

  @override
  Future<TodoItem> createTodo(
    String idToken,
    int roomId, {
    required String title,
    String? detail,
    int? categoryId,
    List<String>? assigneeUserIds,
    DateTime? dueDate,
    String? imageUrl,
  }) async => TodoItem(
    id: 99,
    title: title,
    detail: detail,
    completed: false,
    categoryId: categoryId,
    assignees: [],
    dueDate: dueDate,
    imageUrl: imageUrl,
  );

  @override
  Future<TodoItem> updateTodo(
    String idToken,
    int roomId,
    int todoId, {
    required String title,
    String? detail,
    int? categoryId,
    List<String>? assigneeUserIds,
    DateTime? dueDate,
    String? imageUrl,
  }) async => TodoItem(
    id: todoId,
    title: title,
    detail: detail,
    completed: false,
    categoryId: categoryId,
    assignees: [],
    dueDate: dueDate,
    imageUrl: imageUrl,
  );

  @override
  Future<String> uploadTodoImage(
    String idToken,
    int roomId, {
    required List<int> bytes,
  }) async => 'https://storage.test/todo-image';

  @override
  Future<void> setTodoCompleted(
    String idToken,
    int roomId,
    int todoId,
    bool completed,
  ) async {}

  @override
  Future<List<TodoSuggestionCandidate>> fetchAiSuggestions(
    String idToken,
    int roomId,
  ) async => [
    TodoSuggestionCandidate(title: '리뷰 의견을 반영한 화면 정리', category: '개발'),
    TodoSuggestionCandidate(title: '다음 스프린트 회의 준비', category: '기획'),
  ];

  @override
  Future<void> deleteTodo(String idToken, int roomId, int todoId) async {}
}

class StoryScheduleApi extends ScheduleApi {
  StoryScheduleApi();

  @override
  Future<List<ScheduleItem>> fetchSchedules(
    String idToken,
    int roomId, {
    required DateTime start,
    required DateTime end,
  }) async {
    final today = DateTime.now();
    // 선택 기본값(오늘)에 일정이 보이도록 today 항목을 넣는다(같은 달일 때만).
    final todayInRange = !today.isBefore(start) && !today.isAfter(end);
    return [
      if (todayInRange) ...[
        ScheduleItem(
          id: 10,
          title: '스터디 정기 모임',
          date: DateTime(today.year, today.month, today.day),
          time: '10:00:00',
          place: '중앙도서관 3층 스터디룸',
        ),
        ScheduleItem(
          id: 11,
          title: '저녁 운동',
          date: DateTime(today.year, today.month, today.day),
          time: '19:30:00',
        ),
      ],
      ScheduleItem(
        id: 1,
        title: '주간 회고',
        date: DateTime(start.year, start.month, 7),
        time: '19:00:00',
        detail: '이번 주에 잘한 점과 다음 액션을 정리해요.',
        place: '온라인',
      ),
      ScheduleItem(
        id: 2,
        title: '데모 준비',
        date: DateTime(start.year, start.month, 14),
        time: '14:00:00',
      ),
      ScheduleItem(
        id: 3,
        title: '스프린트 마감',
        date: DateTime(start.year, start.month, 21),
        time: '18:00:00',
      ),
    ];
  }

  @override
  Future<ScheduleItem> createSchedule(
    String idToken,
    int roomId, {
    required String title,
    required DateTime date,
    String? time,
    DateTime? endDate,
    String? endTime,
    String? detail,
    String? place,
  }) async => ScheduleItem(
    id: 99,
    title: title,
    date: date,
    time: time,
    endDate: endDate,
    endTime: endTime,
    detail: detail,
    place: place,
  );

  @override
  Future<ScheduleItem> updateSchedule(
    String idToken,
    int roomId,
    int scheduleId, {
    required String title,
    required DateTime date,
    String? time,
    DateTime? endDate,
    String? endTime,
    String? detail,
    String? place,
  }) async => ScheduleItem(
    id: scheduleId,
    title: title,
    date: date,
    time: time,
    endDate: endDate,
    endTime: endTime,
    detail: detail,
    place: place,
  );

  @override
  Future<void> deleteSchedule(
    String idToken,
    int roomId,
    int scheduleId,
  ) async {}
}

class StoryArchiveApi extends ArchiveApi {
  StoryArchiveApi();

  final _folders = [
    ArchiveFolder(id: 1, name: '레퍼런스', itemCount: 12),
    ArchiveFolder(id: 2, name: '회의 기록', itemCount: 5),
    ArchiveFolder(id: 3, name: '개발 문서', itemCount: 8),
  ];

  final _items = [
    ArchiveItem(
      id: 101,
      title: 'Widgetbook 공식 문서',
      url: 'https://pub.dev/packages/widgetbook',
      source: 'pub.dev',
      thumbnail: null,
      imageUrl: null,
      pinned: true,
      createdAt: DateTime(2026, 7, 28),
      tags: ['Flutter', 'UI'],
      likeCount: 7,
      crawlStatus: 'DONE',
    ),
    ArchiveItem(
      id: 102,
      title: '모디 디자인 원칙',
      url: null,
      source: '팀 문서',
      thumbnail: null,
      imageUrl: null,
      pinned: false,
      createdAt: DateTime(2026, 7, 27),
      tags: ['디자인', '협업'],
      likeCount: 3,
      crawlStatus: 'DONE',
    ),
  ];

  ArchiveItemDetail get _detail => ArchiveItemDetail(
    id: 101,
    folderId: 1,
    title: 'Widgetbook 공식 문서',
    url: 'https://pub.dev/packages/widgetbook',
    source: 'pub.dev',
    thumbnail: null,
    summary: '위젯을 독립적인 상태와 여러 화면 크기에서 확인할 수 있어요.',
    bodyText: '위젯을 독립적인 상태로 확인하고 여러 화면 크기에서 검증할 수 있어요.',
    pinned: true,
    tags: ['Flutter', 'UI'],
    likeCount: 7,
    likedByMe: true,
    createdAt: DateTime(2026, 7, 28),
    crawlStatus: 'DONE',
    memo: '컴포넌트 스토리 정리할 때 자주 참고하는 문서.',
  );

  @override
  Future<List<ArchiveFolder>> fetchFolders(String idToken, int roomId) async =>
      _folders;

  @override
  Future<ArchiveFolder> createFolder(
    String idToken,
    int roomId,
    String name,
  ) async => ArchiveFolder(id: 99, name: name, itemCount: 0);

  @override
  Future<ArchiveFolder> renameFolder(
    String idToken,
    int roomId,
    int folderId,
    String name,
  ) async => ArchiveFolder(id: folderId, name: name, itemCount: 0);

  @override
  Future<void> deleteFolder(String idToken, int roomId, int folderId) async {}

  @override
  Future<ArchiveFolderItems> fetchFolderItems(
    String idToken,
    int roomId,
    int folderId,
  ) async =>
      ArchiveFolderItems(folderId: folderId, folderName: '레퍼런스', items: _items);

  @override
  Future<ArchiveItemDetail> fetchItemDetail(
    String idToken,
    int roomId,
    int itemId,
  ) async => _detail;

  @override
  Future<ArchiveItemDetail> setItemPinned(
    String idToken,
    int roomId,
    int itemId,
    bool pinned,
  ) async => _detail.copyWith(pinned: pinned);

  @override
  Future<ArchiveItemDetail> setItemLiked(
    String idToken,
    int roomId,
    int itemId,
    bool liked,
  ) async => _detail.copyWith(likedByMe: liked, likeCount: liked ? 8 : 7);

  @override
  Future<ArchiveItemDetail> moveItemToFolder(
    String idToken,
    int roomId,
    int itemId,
    int folderId,
  ) async => _detail;

  @override
  Future<ArchiveItemDetail> updateItemTags(
    String idToken,
    int roomId,
    int itemId,
    List<String> tags,
  ) async => _detail;

  @override
  Future<void> deleteItem(String idToken, int roomId, int itemId) async {}

  @override
  Future<ArchiveItemDetail> createItem(
    String idToken,
    int roomId,
    int folderId, {
    String? url,
    String? text,
    String? memo,
    String? imageUrl,
    String? title,
  }) async => _detail;
}

class StoryRoomApi extends RoomApi {
  StoryRoomApi();

  @override
  Future<CreatedRoom> createRoom(
    String idToken, {
    required String name,
    required String goal,
    String? goalDetail,
    required DateTime startDate,
    required DateTime endDate,
    String? coverImage,
  }) async => CreatedRoom(id: 42, name: name, inviteCode: 'MODI42');

  @override
  Future<InvitePreview> previewInvite(String idToken, String code) async =>
      InvitePreview(
        roomId: 42,
        name: '여름 알고리즘 스터디',
        goal: '팀 목표를 한눈에 보고 이번 주 실행으로 연결하기',
        status: 'ACTIVE',
        memberCount: 5,
        startDate: DateTime(2026, 7, 28),
        endDate: DateTime(2026, 9, 5),
      );

  @override
  Future<void> joinRoom(String idToken, String code) async {}

  @override
  Future<List<Map<String, dynamic>>> listMyRooms(String idToken) async => [
    {
      'id': 42,
      'name': '모디 팀 프로젝트',
      'goal': '팀 목표를 한눈에 보고 이번 주 실행으로 연결하기',
      'status': 'ACTIVE',
      'startDate': '2026-07-01',
      'endDate': '2026-08-31',
    },
  ];
}

/// 무효/만료 코드 흐름 확인용 — previewInvite가 항상 실패한다(알림 팝업 스토리).
class StoryInvalidInviteApi extends StoryRoomApi {
  @override
  Future<InvitePreview> previewInvite(String idToken, String code) async =>
      throw InviteNotFoundException();
}

class StorySettingsApi extends SettingsApi {
  StorySettingsApi();

  /// 캐릭터 갤러리 스토리(S-40 설정)에서 knob으로 바꿔가며 확인할 수 있도록
  /// 노출한 필드 — 실제 서버 응답 대신 이 id로 [fetchCharacter] 결과를 만든다.
  String characterId = 'PROCRASTINATOR';

  NotificationSettings _notificationSettings = const NotificationSettings(
    allEnabled: true,
    pokeEnabled: true,
  );

  @override
  Future<MyActivitySummary> fetchCharacter(String idToken) async {
    return MyActivitySummary(
      characterId: characterId,
      characterName: characterId,
      characterQuote: '"곧 정체가 드러나요"',
      characterDetail: '투두를 완료할수록 더 정확해져요',
      deadlineKeptPercent: 82,
      bestStreakDays: 12,
      sharedCount: 4,
      completedCount: 37,
    );
  }

  @override
  Future<UserProfile> fetchProfile(String idToken) async =>
      const UserProfile(userId: 'story-user', nickname: '정남준');

  @override
  Future<UserProfile> updateProfile(
    String idToken, {
    required String nickname,
    String? profileImage,
  }) async => UserProfile(
    userId: 'story-user',
    nickname: nickname,
    profileImage: profileImage,
  );

  @override
  Future<NotificationSettings> fetchNotificationSettings(
    String idToken,
  ) async => _notificationSettings;

  @override
  Future<NotificationSettings> updateNotificationSettings(
    String idToken,
    NotificationSettings settings,
  ) async {
    _notificationSettings = settings;
    return settings;
  }

  @override
  Future<void> updateRoom(
    String idToken,
    int roomId, {
    required String name,
    required String goal,
    String? goalDetail,
    required DateTime startDate,
    required DateTime endDate,
    String? coverImage,
  }) async {}

  @override
  Future<List<SettingsMember>> fetchMembers(String idToken, int roomId) async =>
      const [
        SettingsMember(
          userId: 'story-user',
          nickname: '정남준',
          assignedTotal: 8,
          assignedDone: 5,
        ),
        SettingsMember(
          userId: 'story-member-1',
          nickname: '김모디',
          assignedTotal: 6,
          assignedDone: 4,
        ),
        SettingsMember(
          userId: 'story-member-2',
          nickname: '이협업',
          assignedTotal: 5,
          assignedDone: 2,
        ),
      ];

  @override
  Future<String> reissueInviteCode(String idToken, int roomId) async =>
      'MODI43';

  @override
  Future<String> fetchInviteCode(String idToken, int roomId) async =>
      'K7QP-2M9X';

  @override
  Future<void> leaveRoom(String idToken, int roomId) async {}

  @override
  Future<List<PastRoom>> fetchPastRooms(String idToken) async => [
    PastRoom(
      id: 43,
      name: '지난 사이드 프로젝트',
      startDate: DateTime(2026, 5, 1),
      endDate: DateTime(2026, 6, 30),
      completionRate: 0.78,
    ),
  ];
}

class StoryMemberTodosApi extends MemberTodosApi {
  StoryMemberTodosApi();

  @override
  Future<MemberTodosData> fetchMemberTodos(
    String idToken,
    int roomId,
    String userId,
  ) async => MemberTodosData(
    memberName: '김모디',
    assignedTotal: 6,
    assignedDone: 4,
    categories: const {1: '기획', 2: '개발', 3: '디자인'},
    todos: [
      TodoItem(
        id: 11,
        title: '온보딩 문구 최종 확인',
        detail: '첫 방문 사용자가 다음 행동을 바로 이해하는지 확인해요.',
        completed: true,
        categoryId: 1,
        assignees: const [],
      ),
      TodoItem(
        id: 12,
        title: 'Widgetbook 페이지 리뷰',
        detail: '주요 상태와 작은 화면에서의 레이아웃을 점검해요.',
        completed: true,
        categoryId: 2,
        assignees: const [],
      ),
      TodoItem(
        id: 13,
        title: '팀 리뷰 반영하기',
        completed: false,
        categoryId: 3,
        assignees: const [],
      ),
    ],
  );

  @override
  Future<void> poke(String idToken, int roomId, String userId) async {}
}
