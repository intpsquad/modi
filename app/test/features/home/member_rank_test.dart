import 'package:app/features/home/home_api.dart';
import 'package:app/features/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 멤버 아바타줄 순위 규칙 — `rankMembersByProgress` 순수 함수 검증.
MemberProgress _m(String id, {required int done, required int total}) =>
    MemberProgress(
      userId: id,
      nickname: id,
      assignedTotal: total,
      assignedDone: done,
    );

void main() {
  test('진행률 높은 순으로 정렬하고 등수를 매긴다', () {
    final r = rankMembersByProgress([
      _m('a', done: 1, total: 10), // 10%
      _m('b', done: 9, total: 10), // 90%
      _m('c', done: 5, total: 10), // 50%
    ]);
    expect(r.map((e) => e.member.userId).toList(), ['b', 'c', 'a']);
    expect(r.map((e) => e.rank).toList(), [1, 2, 3]);
  });

  test('같은 %면 완료 개수 많은 사람이 앞선다', () {
    final r = rankMembersByProgress([
      _m('half-small', done: 1, total: 2), // 50%, 완료 1
      _m('half-big', done: 5, total: 10), // 50%, 완료 5
    ]);
    expect(r.map((e) => e.member.userId).toList(), ['half-big', 'half-small']);
    expect(r.map((e) => e.rank).toList(), [1, 2]);
  });

  test('진행률·완료개수까지 같으면 공동 등수(같은 메달), 다음 등수는 건너뛴다', () {
    final r = rankMembersByProgress([
      _m('tie1', done: 3, total: 6), // 50%, 완료 3
      _m('tie2', done: 3, total: 6), // 50%, 완료 3 — tie1과 완전 동률
      _m('third', done: 1, total: 10), // 10%
    ]);
    // 공동 1등 2명 → 다음은 3등(2등 건너뜀, 올림픽식).
    expect(r.map((e) => e.rank).toList(), [1, 1, 3]);
  });

  test('공동 1등 3명이면 모두 1등', () {
    final r = rankMembersByProgress([
      _m('x', done: 2, total: 4),
      _m('y', done: 2, total: 4),
      _m('z', done: 2, total: 4),
    ]);
    expect(r.map((e) => e.rank).toList(), [1, 1, 1]);
  });

  test('진행률 0%(완료 0개)는 상위 등수여도 메달 제외', () {
    final r = rankMembersByProgress([
      _m('worker', done: 3, total: 10), // 30%
      _m('idle1', done: 0, total: 5), // 0%
      _m('idle2', done: 0, total: 0), // 담당 없음 = 0%
    ]);
    // 등수는 매겨지지만(1,2,3) 0%는 메달을 못 받는다.
    final medals = {for (final e in r) e.member.userId: e.medal};
    expect(medals['worker'], isTrue);
    expect(medals['idle1'], isFalse);
    expect(medals['idle2'], isFalse);
  });

  test('전원 0%면 아무도 메달을 받지 않는다', () {
    final r = rankMembersByProgress([
      _m('a', done: 0, total: 4),
      _m('b', done: 0, total: 4),
    ]);
    expect(r.every((e) => !e.medal), isTrue);
  });
}
