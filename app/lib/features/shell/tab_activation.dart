import 'package:flutter/foundation.dart';

/// 지금 어느 하단 탭이 켜져 있는지를 화면들에 알리는 경량 신호.
///
/// 앱이 탭 상태를 살려두기 때문에(`StatefulShellRoute`), 탭을 다시 눌러도 이미 만들어진
/// 화면은 `initState`를 다시 타지 않는다 → 다른 탭에서 바뀐 내용이 반영되지 않는다.
/// [AppShell]이 탭이 바뀔 때마다 [index]를 갱신하고, 각 탭 화면은 **자기 인덱스로
/// 바뀌는 순간** 조용히(스피너 없이) 다시 불러온다.
///
/// `TodoSync`(`features/todos/todo_sync.dart`)와 같은 패턴 — 전역 인스턴스 하나를
/// 화면이 addListener/removeListener 로만 쓴다.
class TabActivation extends ChangeNotifier {
  TabActivation({int index = 0})
    : _index = index; // ignore: prefer_initializing_formals

  int _index;

  /// 현재 활성 탭 인덱스(홈 0 · 투두 1 · 일정 2 · 모아보기 3 — `AppShell.tabs` 순서).
  int get index => _index;

  set index(int value) {
    if (_index == value) return;
    _index = value;
    notifyListeners();
  }

  /// 알림 없이 현재 값만 맞춘다 — 셸이 처음 뜰 때(딥링크로 다른 탭에서 시작하는 경우 포함)
  /// 쓴다. 알리면 방금 initState 에서 첫 조회를 시작한 화면이 곧바로 한 번 더 부른다.
  void syncInitial(int value) => _index = value;

  /// **하단 탭을 누를 때마다**(전환·재탭 모두) 그 인덱스로 울리는 신호 — 각 탭 화면이 이걸 듣고
  /// **맨 위로 스크롤**한다(2026-08-09: 탭 이동 시 하위페이지는 pop + 스크롤 초기화). [index]와
  /// 분리한 이유: index는 전환 때만 바뀌어 재탭을 못 잡고, index에 합치면 화면 재조회(무거움)와
  /// 스크롤 리셋(가벼움)이 뒤섞인다.
  final TabReselect reselect = TabReselect();

  /// 홈의 "투두 추가하기"가 투두 탭으로 보내면서 **추가 시트를 바로 띄워달라**고 남기는
  /// 일회성 요청(2026-08-09). 투두 탭이 활성화되며 [consumeOpenTodoComposer]로 한 번 소비한다.
  bool _openTodoComposerRequested = false;

  void requestOpenTodoComposer() => _openTodoComposerRequested = true;

  bool consumeOpenTodoComposer() {
    final requested = _openTodoComposerRequested;
    _openTodoComposerRequested = false;
    return requested;
  }
}

/// 재탭 신호 전용의 얇은 노티파이어 — [TabActivation.reselect].
class TabReselect extends ChangeNotifier {
  int _index = -1;

  /// 마지막으로 재탭된 탭 인덱스.
  int get index => _index;

  void notify(int value) {
    _index = value;
    notifyListeners();
  }
}

/// 앱 전역 공용 인스턴스(앱 생명주기 동안 유지). 테스트는 자체 인스턴스를 주입한다.
final appTabActivation = TabActivation();
