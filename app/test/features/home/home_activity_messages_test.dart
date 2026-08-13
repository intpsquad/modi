import 'package:app/features/home/home_api.dart';
import 'package:app/features/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

DashboardData _data({int? done, int? total, required DateTime endDate}) {
  return DashboardData(
    room: RoomInfo(
      id: 1,
      name: '방',
      goal: '목표',
      startDate: DateTime(2026, 1, 1),
      endDate: endDate,
      status: 'ACTIVE',
    ),
    members: const [],
    weekSchedules: const [],
    todayTodos: const [],
    recentArchives: const [],
    todoDone: done,
    todoTotal: total,
  );
}

/// 오늘 자정 기준 [days]일 뒤(daysRemaining가 정확히 [days]가 되도록).
DateTime _todayPlus(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).add(Duration(days: days));
}

DashboardData _dataWithActivities(List<ActivityEvent> activities) {
  return DashboardData(
    room: RoomInfo(
      id: 1,
      name: '방',
      goal: '목표',
      startDate: DateTime(2026, 1, 1),
      endDate: _todayPlus(-1), // 진행률·D-day 메시지를 섞지 않기 위해 마감 지난 방으로 둔다.
      status: 'ACTIVE',
    ),
    members: const [],
    weekSchedules: const [],
    todayTodos: const [],
    recentArchives: const [],
    activities: activities,
  );
}

ActivityEvent _event(
  String type, {
  String? actorNickname,
  String? actorUserId,
  int? count,
  String? targetName,
  int? secondaryCount,
}) {
  return ActivityEvent(
    type: type,
    actorNickname: actorNickname,
    actorUserId: actorUserId,
    count: count,
    targetName: targetName,
    secondaryCount: secondaryCount,
    createdAt: DateTime(2026, 8, 6, 9),
  );
}

void main() {
  test('진행률과 D-day 메시지를 함께 만든다', () {
    final texts = homeActivityMessages(
      _data(done: 24, total: 40, endDate: _todayPlus(14)),
    ).map((m) => m.plainText).toList();

    expect(texts, contains('🎉 팀 진행률 60% · 완료 24개'));
    expect(texts, contains('⏳ 마감까지 D-14'));
  });

  test('완료 0개면 진행률 축하 메시지를 넣지 않는다', () {
    final texts = homeActivityMessages(
      _data(done: 0, total: 40, endDate: _todayPlus(3)),
    ).map((m) => m.plainText).toList();

    expect(texts.any((t) => t.contains('팀 진행률')), isFalse);
    expect(texts, contains('⏳ 마감까지 D-3'));
  });

  test('마감 당일은 D-day 대신 오늘 문구', () {
    final texts = homeActivityMessages(
      _data(done: 1, total: 2, endDate: _todayPlus(0)),
    ).map((m) => m.plainText).toList();

    expect(texts, contains('🔥 오늘이 마감이에요'));
  });

  test('진행률 근거 없고 마감 지났으면 메시지가 없다(배너 미표시)', () {
    final messages = homeActivityMessages(
      _data(done: null, total: null, endDate: _todayPlus(-1)),
    );

    expect(messages, isEmpty);
  });

  group('활동 피드 이벤트 타입별 문구(docs/backend/home-activity-feed.md §2)', () {
    test('TODO_COMPLETED — 닉네임 굵게 + 완료 개수', () {
      final messages = homeActivityMessages(
        _dataWithActivities([
          _event('TODO_COMPLETED', actorNickname: '지훈', count: 3),
        ]),
      );

      expect(messages.single.plainText, '지훈님이 투두 3개를 완료했어요 🔥');
      expect(messages.single.segments.first.bold, isTrue);
      expect(messages.single.segments.first.text, '지훈');
    });

    test('TODO_COMPLETED_SHARED — 대표닉 굵게 + 담당자 외 N명', () {
      final messages = homeActivityMessages(
        _dataWithActivities([
          _event('TODO_COMPLETED_SHARED', targetName: '민', count: 3),
        ]),
      );

      expect(messages.single.plainText, '민 외 2명이 함께 맡은 투두를 끝냈어요 🎉');
      expect(messages.single.segments.first.bold, isTrue);
      expect(messages.single.segments.first.text, '민');
    });

    test('TODO_COMPLETED_SHARED — 대표닉 없으면 건너뛴다', () {
      final messages = homeActivityMessages(
        _dataWithActivities([_event('TODO_COMPLETED_SHARED', count: 2)]),
      );

      expect(messages, isEmpty);
    });

    test('TODO_ALL_DONE', () {
      final texts = homeActivityMessages(
        _dataWithActivities([_event('TODO_ALL_DONE', actorNickname: '서연')]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['서연님이 맡은 투두를 다 끝냈어요 🎉']);
    });

    test('TODO_ADDED', () {
      final texts = homeActivityMessages(
        _dataWithActivities([_event('TODO_ADDED', actorNickname: '민재')]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['민재님이 투두를 추가했어요']);
    });

    test('SCHEDULE_ADDED', () {
      final texts = homeActivityMessages(
        _dataWithActivities([_event('SCHEDULE_ADDED', actorNickname: '지훈')]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['지훈님이 새로운 일정을 등록했어요']);
    });

    test('SCHEDULE_SOON — actor 없이 단문', () {
      final texts = homeActivityMessages(
        _dataWithActivities([_event('SCHEDULE_SOON')]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['곧 시작되는 일정이 있어요']);
    });

    test('ARCHIVE_ADDED — targetName은 폴더 이름', () {
      final texts = homeActivityMessages(
        _dataWithActivities([
          _event('ARCHIVE_ADDED', actorNickname: '서연', targetName: 'DP 정리 영상'),
        ]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['서연님이 DP 정리 영상에 자료를 추가했어요']);
    });

    test('ARCHIVE_LIKE_MILESTONE', () {
      final texts = homeActivityMessages(
        _dataWithActivities([
          _event('ARCHIVE_LIKE_MILESTONE', actorNickname: '지훈', count: 5),
        ]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['지훈님 자료에 좋아요 5개 달성! ❤️']);
    });

    test('POKE — targetName은 대상 닉네임', () {
      final texts = homeActivityMessages(
        _dataWithActivities([
          _event('POKE', actorNickname: '민재', targetName: '서연'),
        ]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['민재님이 서연님을 콕 찔렀어요 👋']);
    });

    test('POKE_ACCUMULATED', () {
      final texts = homeActivityMessages(
        _dataWithActivities([
          _event('POKE_ACCUMULATED', actorNickname: '서연', count: 10),
        ]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['서연님 콕이 10개 쌓였어요']);
    });

    test('MEMBER_JOINED', () {
      final texts = homeActivityMessages(
        _dataWithActivities([_event('MEMBER_JOINED', actorNickname: '지훈')]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['지훈님이 방에 들어왔어요']);
    });

    test('WEEKLY_SUMMARY — 지난주 대비 양수는 +기호', () {
      final texts = homeActivityMessages(
        _dataWithActivities([
          _event('WEEKLY_SUMMARY', count: 8, secondaryCount: 3),
        ]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['이번 주 완료 8개 (지난주 +3) 📈']);
    });

    test('WEEKLY_SUMMARY — 지난주 대비 음수는 부호 그대로', () {
      final texts = homeActivityMessages(
        _dataWithActivities([
          _event('WEEKLY_SUMMARY', count: 1, secondaryCount: -2),
        ]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['이번 주 완료 1개 (지난주 -2) 📈']);
    });

    test('NUDGE_NONE_TODAY — actor 없이 단문', () {
      final texts = homeActivityMessages(
        _dataWithActivities([_event('NUDGE_NONE_TODAY')]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['오늘 아직 아무도 완료한 사람이 없어요 🥹']);
    });

    test('NUDGE_QUIET_MEMBER — count는 조용한 일수', () {
      final texts = homeActivityMessages(
        _dataWithActivities([
          _event('NUDGE_QUIET_MEMBER', actorNickname: '민재', count: 4),
        ]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['민재님이 4일째 조용해요.. 😓']);
    });

    test('NUDGE_UNASSIGNED — 미지정 투두 수', () {
      final texts = homeActivityMessages(
        _dataWithActivities([_event('NUDGE_UNASSIGNED', count: 3)]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['3개의 투두가 주인을 찾고 있어요! 🙋']);
    });

    test('actor가 필요한데 닉네임이 없으면 그 항목만 조용히 건너뛴다', () {
      final messages = homeActivityMessages(
        _dataWithActivities([_event('TODO_COMPLETED', count: 1)]),
      );

      expect(messages, isEmpty);
    });

    test('MILESTONE_PROGRESS·DDAY는 프론트 파생과 중복되지 않게 무시한다', () {
      final messages = homeActivityMessages(
        _dataWithActivities([_event('MILESTONE_PROGRESS'), _event('DDAY')]),
      );

      expect(messages, isEmpty);
    });

    test('모르는 타입은 조용히 무시한다', () {
      final messages = homeActivityMessages(
        _dataWithActivities([_event('SOME_FUTURE_TYPE')]),
      );

      expect(messages, isEmpty);
    });

    test('여러 이벤트가 서버가 준 순서 그대로 이어진다', () {
      final texts = homeActivityMessages(
        _dataWithActivities([
          _event('MEMBER_JOINED', actorNickname: '지훈'),
          _event('POKE', actorNickname: '민재', targetName: '서연'),
        ]),
      ).map((m) => m.plainText).toList();

      expect(texts, ['지훈님이 방에 들어왔어요', '민재님이 서연님을 콕 찔렀어요 👋']);
    });
  });
}
