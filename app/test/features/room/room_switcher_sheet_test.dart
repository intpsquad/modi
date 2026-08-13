import 'package:app/design/todo_checkbox.dart';
import 'package:app/features/room/room_session.dart';
import 'package:app/features/room/room_switcher_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RoomSummary _room({
  required int id,
  required String name,
  required String status,
  DateTime? endDate,
}) => RoomSummary(
  id: id,
  name: name,
  goal: '목표-$id',
  status: status,
  startDate: DateTime(2026, 1, 1),
  endDate: endDate ?? DateTime(2026, 12, 31),
);

Future<int?> _openSheet(
  WidgetTester tester,
  List<RoomSummary> rooms, {
  int? currentRoomId,
}) async {
  int? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            result = await showModalBottomSheet<int>(
              context: context,
              builder: (context) =>
                  RoomSwitcherSheet(rooms: rooms, currentRoomId: currentRoomId),
            );
          },
          child: const Text('열기'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('진행중 방 전체가 목록에 보인다', (tester) async {
    await _openSheet(tester, [
      _room(id: 1, name: '방1', status: 'ACTIVE'),
      _room(id: 2, name: '방2', status: 'ACTIVE'),
    ]);

    expect(find.text('방1'), findsOneWidget);
    expect(find.text('방2'), findsOneWidget);
  });

  testWidgets('진행중 방을 탭하면 해당 roomId로 pop된다', (tester) async {
    late int? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showModalBottomSheet<int>(
                context: context,
                builder: (context) => RoomSwitcherSheet(
                  rooms: [
                    _room(id: 1, name: '방1', status: 'ACTIVE'),
                    _room(id: 2, name: '방2', status: 'ACTIVE'),
                  ],
                ),
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('room-switch-2')));
    await tester.pumpAndSettle();

    expect(result, 2);
  });

  testWidgets('현재 방에는 체크(투두 체크 위젯) 표시가 하나만 붙는다', (tester) async {
    await _openSheet(tester, [
      _room(id: 1, name: '방1', status: 'ACTIVE'),
      _room(id: 2, name: '방2', status: 'ACTIVE'),
    ], currentRoomId: 2);

    expect(find.byType(TodoCheckbox), findsOneWidget);
  });

  testWidgets('"방 만들기" 아이템과 "초대코드로 입장하기" 버튼은 항상 보인다', (tester) async {
    await _openSheet(tester, [_room(id: 1, name: '방1', status: 'ACTIVE')]);

    expect(find.text('방 만들기'), findsOneWidget);
    expect(find.text('초대코드로 입장하기'), findsOneWidget);
    expect(find.text('방 전체 보기'), findsNothing);
  });

  testWidgets('방이 하나도 없으면 "방 만들기"만 남고 카드 내부 divider가 없다', (tester) async {
    await _openSheet(tester, []);

    expect(find.text('방 만들기'), findsOneWidget);
    expect(find.text('초대코드로 입장하기'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('종료된 방은 목록에 안 뜨고 종료된 방 보기 링크로 분리된다', (tester) async {
    await _openSheet(tester, [
      _room(id: 1, name: '진행방', status: 'ACTIVE'),
      _room(
        id: 2,
        name: '종료방A',
        status: 'ENDED',
        endDate: DateTime(2026, 3, 1),
      ),
      _room(
        id: 3,
        name: '종료방B',
        status: 'ENDED',
        endDate: DateTime(2026, 2, 1),
      ),
    ]);

    expect(find.text('진행방'), findsOneWidget); // 활동중 방은 목록에
    expect(find.text('종료방A'), findsNothing); // 종료방은 목록에서 제외
    expect(find.text('종료방B'), findsNothing);
    expect(find.text('종료됨'), findsNothing);
    expect(find.text('종료된 방 보기'), findsOneWidget); // 헤더 링크로 분리
  });

  testWidgets('currentRoomId가 종료방을 가리켜도 체크는 뜨지 않는다(종료방은 목록에서 제외)', (
    tester,
  ) async {
    await _openSheet(tester, [
      _room(id: 5, name: '종료방', status: 'ENDED', endDate: DateTime(2026, 1, 1)),
    ], currentRoomId: 5);

    expect(find.text('종료방'), findsNothing);
    expect(find.byType(TodoCheckbox), findsNothing);
    expect(find.text('종료된 방 보기'), findsOneWidget);
  });

  testWidgets('종료된 방이 없으면 헤더에 종료된 방 보기가 안 뜬다', (tester) async {
    await _openSheet(tester, [_room(id: 1, name: '진행방', status: 'ACTIVE')]);

    expect(find.text('종료된 방 보기'), findsNothing);
    expect(find.text('초대코드로 입장하기'), findsOneWidget);
  });
}
