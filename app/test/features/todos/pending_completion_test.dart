import 'package:app/features/todos/pending_completion.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PendingCompletions', () {
    test('예약한 뒤 지연 시간이 지나야 커밋된다', () {
      fakeAsync((async) {
        final pending = PendingCompletions(delay: const Duration(seconds: 2));
        final committed = <int>[];

        pending.schedule(1, () async => committed.add(1));
        expect(pending.isPending(1), isTrue);

        async.elapse(const Duration(milliseconds: 1900));
        expect(committed, isEmpty, reason: '2초 전에는 서버로 보내지 않는다');

        async.elapse(const Duration(milliseconds: 200));
        expect(committed, [1]);
        expect(pending.isPending(1), isFalse);
      });
    });

    test('지연 시간 안에 취소하면 끝까지 커밋되지 않는다', () {
      fakeAsync((async) {
        final pending = PendingCompletions(delay: const Duration(seconds: 2));
        final committed = <int>[];

        pending.schedule(1, () async => committed.add(1));
        async.elapse(const Duration(milliseconds: 500));

        expect(pending.cancel(1), isTrue, reason: '대기 중이었으므로 취소된다');
        async.elapse(const Duration(seconds: 5));
        expect(committed, isEmpty);
        expect(pending.isPending(1), isFalse);
      });
    });

    test('대기 중이 아닌 것을 취소하면 false 를 준다', () {
      final pending = PendingCompletions();
      expect(pending.cancel(42), isFalse);
    });

    test('flushAll 은 대기 중인 것을 지금 전부 보낸다', () {
      fakeAsync((async) {
        final pending = PendingCompletions(delay: const Duration(seconds: 2));
        final committed = <int>[];

        pending.schedule(1, () async => committed.add(1));
        pending.schedule(2, () async => committed.add(2));
        async.elapse(const Duration(milliseconds: 100));

        pending.flushAll();
        expect(committed, [1, 2], reason: '화면을 떠나면 즉시 반영한다(사용자 확정)');

        // 타이머가 남아 두 번 보내지 않아야 한다.
        async.elapse(const Duration(seconds: 5));
        expect(committed, [1, 2]);
      });
    });

    test('같은 id 를 두 번 예약해도 커밋은 한 번뿐이다', () {
      fakeAsync((async) {
        final pending = PendingCompletions(delay: const Duration(seconds: 2));
        var count = 0;

        pending.schedule(1, () async => count++);
        pending.schedule(1, () async => count++);
        async.elapse(const Duration(seconds: 5));

        expect(count, 1);
      });
    });

    test('discardAll 은 커밋하지 않고 타이머만 정리한다', () {
      fakeAsync((async) {
        final pending = PendingCompletions(delay: const Duration(seconds: 2));
        var count = 0;

        pending.schedule(1, () async => count++);
        pending.discardAll();
        async.elapse(const Duration(seconds: 5));

        expect(count, 0);
        expect(pending.pendingIds, isEmpty);
      });
    });
  });
}
