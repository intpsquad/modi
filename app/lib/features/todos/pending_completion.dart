import 'dart:async';

/// 완료 체크를 **바로 서버에 보내지 않고 잠깐 붙잡아 두는** 대기열.
///
/// 체크는 화면에 즉시 반영하되(낙관적), 실제 반영은 [delay] 뒤에 한다 — 그 사이에 다시
/// 누르면 없던 일이 된다(요청 3: "바로 취소할 수도 있으니까"). 홈(S-04)과 투두 탭(S-15)이
/// 같은 규칙을 써야 해서 별도 클래스로 뺐다.
///
/// 화면을 떠나거나 탭을 옮기면 [flushAll]로 **즉시 반영**한다(2026-08-05 사용자 확정) —
/// 취소하지 않은 체크를 조용히 버리면 사용자가 체크한 것이 사라져 보이기 때문이다.
class PendingCompletions {
  PendingCompletions({this.delay = const Duration(seconds: 2)});

  /// 체크 후 서버로 보내기까지 기다리는 시간.
  final Duration delay;

  final Map<int, _Pending> _pending = {};

  /// [id]가 지금 대기 중인가(화면에는 체크됐지만 아직 서버에 안 간 상태).
  bool isPending(int id) => _pending.containsKey(id);

  /// 대기 중인 id 전체.
  Iterable<int> get pendingIds => _pending.keys;

  /// [id]의 커밋을 [delay] 뒤로 예약한다. 이미 대기 중이면 아무것도 하지 않는다
  /// (같은 항목을 다시 누르는 건 [cancel]이 처리한다).
  void schedule(int id, Future<void> Function() commit) {
    if (_pending.containsKey(id)) return;
    final entry = _Pending(commit);
    entry.timer = Timer(delay, () {
      _pending.remove(id);
      entry.commit();
    });
    _pending[id] = entry;
  }

  /// 대기 중이던 [id]를 취소한다(서버로 보내지 않는다). 취소했으면 true.
  bool cancel(int id) {
    final entry = _pending.remove(id);
    if (entry == null) return false;
    entry.timer?.cancel();
    return true;
  }

  /// 대기 중인 것을 전부 지금 보낸다(화면 이탈·탭 전환).
  void flushAll() {
    final entries = List.of(_pending.values);
    _pending.clear();
    for (final entry in entries) {
      entry.timer?.cancel();
      entry.commit();
    }
  }

  /// 타이머만 정리하고 커밋은 하지 않는다(테스트 정리용).
  void discardAll() {
    for (final entry in _pending.values) {
      entry.timer?.cancel();
    }
    _pending.clear();
  }
}

class _Pending {
  _Pending(this.commit);

  final Future<void> Function() commit;
  Timer? timer;
}
