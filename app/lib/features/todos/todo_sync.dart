import 'package:flutter/foundation.dart';

/// 투두 완료 상태 변경을 화면 간에 전파하는 경량 신호.
///
/// 앱이 `StatefulShellRoute.indexedStack`으로 탭 상태를 살려두기 때문에, 홈에서
/// 투두를 체크해도 이미 살아있는 투두 탭은 리로드되지 않는다(반대도 마찬가지).
/// 완료 상태를 바꾼 화면이 [markChanged]를 부르면, 이 노티파이어를 구독하는 다른
/// 화면이 목록을 다시 불러와 즉시 반영한다. `RoomSession`(ChangeNotifier)을
/// addListener로 구독하는 기존 패턴과 동일하게 쓴다.
class TodoSync extends ChangeNotifier {
  void markChanged() => notifyListeners();
}

/// 앱 전역 공용 인스턴스(앱 생명주기 동안 유지). 화면은 자기 리스너만 add/remove한다.
final appTodoSync = TodoSync();
