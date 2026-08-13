import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/todo_checkbox.dart';
import '../../design/tokens.dart';
import 'default_cover.dart';
import 'room_session.dart';

/// S-07 시트를 열고, 사용자가 고른 방으로 컨텍스트를 전환한다 — specs/0008-방-전환.md.
/// 홈 상단 "방이름▾" 탭과 하단 네비 홈 버튼 롱프레스가 이 함수를 공유한다.
Future<void> showRoomSwitcher(BuildContext context, RoomSession session) async {
  final selectedRoomId = await showModalBottomSheet<int>(
    context: context,
    useRootNavigator: true, // 바텀시트는 하단 네비(GNB) 위, 항상 최상단.
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (context) => RoomSwitcherSheet(
      rooms: session.rooms,
      currentRoomId: session.currentRoomId,
    ),
  );
  if (selectedRoomId != null && selectedRoomId != session.currentRoomId) {
    // switchRoom()이 notifyListeners()를 호출해 각 탭 화면이 새 방으로 재조회한다.
    await session.switchRoom(selectedRoomId);
  }
}

/// S-07 방 전환 바텀시트 — specs/0008-방-전환.md.
/// 카드 컨테이너 안에 진행중 방(현재 방엔 체크) → 종료된 방 최대 3개(S-05 진입) →
/// "방 만들기" 액션 → 카드 밖 "초대코드로 입장하기"(방 참여) 순으로 쌓는다.
class RoomSwitcherSheet extends StatelessWidget {
  const RoomSwitcherSheet({super.key, required this.rooms, this.currentRoomId});

  final List<RoomSummary> rooms;

  /// 현재 보고 있는 방 — 목록에서 체크 표시 대상. null이면 아무것도 선택 표시 안 함.
  final int? currentRoomId;

  @override
  Widget build(BuildContext context) {
    final activeRooms = rooms.where((r) => r.isActive).toList();
    final hasEndedRooms = rooms.any((r) => !r.isActive);

    // 카드 안: 활동중 방 전부 + "방 만들기"(2026-08-07: 종료방은 헤더 '종료된 방 보기'로 분리).
    final tiles = <Widget>[
      for (final room in activeRooms)
        _RoomTile(
          key: ValueKey('room-switch-${room.id}'),
          room: room,
          selected: room.id == currentRoomId,
          onTap: () => Navigator.of(context).pop(room.id),
        ),
      _CreateRoomTile(
        onTap: () {
          Navigator.of(context).pop();
          context.push('/room/create');
        },
      ),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.content,
          AppSpacing.md,
          AppSpacing.content,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 드래그 핸들.
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            // 헤더: 제목 + (종료된 방 있을 때만) "종료된 방 보기 ›" → S-40-D(2026-08-07).
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('방 전환', style: AppTypography.section),
                if (hasEndedRooms)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/mypage/past-rooms');
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.muted,
                      // 시각은 작지만 히트박스는 44×44 이상(design.md §접근성).
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('종료된 방 보기', style: AppTypography.bodySmall),
                        const SizedBox(width: AppSpacing.xs),
                        Image.asset(
                          'assets/icons/angle_bracket.png',
                          width: 7,
                          height: 11,
                          fit: BoxFit.contain,
                          color: AppColors.mutedSoft,
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.base),
            // 방 목록 카드.
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Column(
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          color: AppColors.borderSoft,
                        ),
                      tiles[i],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            // 초대코드로 입장하기 → 방 참여(S-11). 2026-08-07: 기존 '방 전체 보기'(종료된
            // 방 보기)를 대체 — 종료된 방 보기는 설정(S-40-D)에서 접근.
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/room/join');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.foreground,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                child: const Text('초대코드로 입장하기', style: AppTypography.title),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 방 한 칸 — 아바타 + 이름/부제 + (현재 방)체크 / (종료)뱃지.
class _RoomTile extends StatelessWidget {
  const _RoomTile({
    super.key,
    required this.room,
    required this.onTap,
    this.selected = false,
  });

  final RoomSummary room;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            _RoomAvatar(coverImage: room.coverImage, roomId: room.id),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.name, style: AppTypography.title),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(_ddayLabel(room.endDate), style: AppTypography.caption),
                ],
              ),
            ),
            // 현재 방 표시 — 투두 체크와 같은 위젯(읽기전용, 2026-08-07 요청).
            if (selected) const TodoCheckbox(checked: true, size: 24),
          ],
        ),
      ),
    );
  }

  /// 남은 일수를 날짜(시각 무시) 기준으로 계산해 D-day 라벨로 만든다.
  static String _ddayLabel(DateTime endDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final remaining = end.difference(today).inDays;
    return remaining <= 0 ? 'D-DAY' : 'D-$remaining';
  }
}

/// "방 만들기" 액션 아이템 — 카드 마지막 칸.
class _CreateRoomTile extends StatelessWidget {
  const _CreateRoomTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.surfaceStrong,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add,
                color: AppColors.foreground,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Text('방 만들기', style: AppTypography.title),
          ],
        ),
      ),
    );
  }
}

/// 방 대표 이미지 원형 아바타 — 안 올린 방은 홈 히어로와 **같은 기본 배경**을 쓴다(요청 4).
class _RoomAvatar extends StatelessWidget {
  const _RoomAvatar({this.coverImage, required this.roomId});

  final String? coverImage;
  final int roomId;

  @override
  Widget build(BuildContext context) {
    final url = coverImage;
    return Container(
      width: 36,
      height: 36,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.surfaceStrong,
        shape: BoxShape.circle,
      ),
      child: (url == null || url.isEmpty)
          ? Image.asset(
              defaultCoverAsset(roomId),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
    );
  }
}
