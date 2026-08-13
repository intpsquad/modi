import 'package:shared_preferences/shared_preferences.dart';

/// 투두 "수동 정렬" 순서를 기기에 저장한다.
///
/// 백엔드(todos)에 순서(position) 필드가 없어 서버에 저장할 수 없으므로(백엔드 수정 금지),
/// 방별로 투두 id 순서 리스트를 기기 로컬(shared_preferences)에 보관한다.
/// - 리로드·앱 재시작에도 순서가 유지된다.
/// - 기기 간 동기화는 하지 않는다(로컬 전용).
/// - 카테고리 간 이동은 category_id 변경이라 서버에 저장되고, 이 스토어는 같은 목록 내
///   상대 순서만 담당한다.
class TodoOrderStore {
  static String _key(int roomId) => 'todo_manual_order_$roomId';

  Future<List<int>> load(int roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(roomId)) ?? const <String>[];
    return raw.map(int.tryParse).whereType<int>().toList();
  }

  Future<void> save(int roomId, List<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key(roomId),
      ids.map((id) => id.toString()).toList(),
    );
  }
}
