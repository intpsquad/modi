import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/confirm_dialog.dart';
import '../../design/swipe_action_row.dart';
import '../../design/tokens.dart';
import '../auth/auth_service.dart';
import '../room/room_session.dart';
import '../settings/settings_screens.dart' show TokenLoader;
import 'notification_router.dart';
import 'notifications_api.dart';

/// S-41 알림 내역 — specs/0017-알림-내역.md. `PastRoomsScreen`과 같은 마이페이지 톤
/// (surfaceSoft 배경 + canvas AppBar + 테두리 없는 흰 카드 리스트)을 재사용한다.
///
/// 삭제(#111): 행을 왼쪽으로 밀면 휴지통 버튼이 나오고 누르거나 끝까지 밀면 **확인 없이 바로**
/// 지운다(투두와 같은 낙관적 삭제 — design.md 확인 모달 예외). 앱바의 [전체 삭제]는 확인
/// 모달을 거친다.
class NotificationHistoryScreen extends StatefulWidget {
  NotificationHistoryScreen({
    super.key,
    NotificationsApi? api,
    TokenLoader? tokenLoader,
    RoomSession? roomSession,
  }) : api = api ?? NotificationsApi(),
       tokenLoader = tokenLoader ?? AuthService().getIdToken,
       roomSession = roomSession ?? appRoomSession;

  final NotificationsApi api;
  final TokenLoader tokenLoader;
  final RoomSession roomSession;

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  List<NotificationHistoryItem>? _items;
  String? _error;
  final SlidableGroup _slidableGroup = SlidableGroup();

  /// 삭제가 실패해 되살린 행의 세대 — 행 키에 섞는다. 끝까지 밀어 지운 행은 "밀려 사라진"
  /// 상태를 들고 있어서, 같은 키로 되살리면 그 상태가 그대로 재사용돼 보이지 않는다.
  final Map<int, int> _restoredGeneration = {};

  static const _deleteFailedMessage = '삭제에 실패했어요. 다시 시도해 주세요';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final token = await widget.tokenLoader();
      final items = await widget.api.fetchHistory(token);
      if (mounted) setState(() => _items = items);
      // 진입 순간 전체 읽음 처리 — 홈 벨 배지는 다음 진입 때 소거된 상태로 보인다.
      // 실패해도 목록 자체는 이미 보여줬으므로 조용히 무시.
      unawaited(widget.api.markAllRead(token));
    } catch (_) {
      if (mounted) setState(() => _error = '알림 내역을 불러오지 못했어요');
    }
  }

  Future<void> _onTap(NotificationHistoryItem item) async {
    final roomId = item.roomId;
    if (roomId != null &&
        !widget.roomSession.rooms.any((room) => room.id == roomId)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미 없어진 방이에요')));
      return;
    }
    await handleNotificationData({
      'type': item.type,
      if (roomId != null) 'roomId': roomId.toString(),
    }, roomSession: widget.roomSession);
  }

  /// 한 건 삭제 — 먼저 목록에서 빼고(낙관적), 서버가 실패하면 제자리에 되살린다.
  Future<void> _delete(NotificationHistoryItem item) async {
    final items = _items;
    if (items == null) return;
    final index = items.indexWhere((e) => e.id == item.id);
    if (index < 0) return;
    setState(() => _items = [...items]..removeAt(index));
    try {
      final token = await widget.tokenLoader();
      await widget.api.deleteNotification(token, item.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final current = [...?_items];
        current.insert(index.clamp(0, current.length), item);
        _items = current;
        _restoredGeneration[item.id] = (_restoredGeneration[item.id] ?? 0) + 1;
      });
      _showDeleteFailed();
    }
  }

  /// 전체 삭제 — 되돌릴 수 없어 확인 모달을 거친다(CLAUDE.md 파괴적 액션 규칙).
  Future<void> _confirmDeleteAll() async {
    _slidableGroup.closeAll();
    final confirmed = await showActionConfirmDialog(
      context: context,
      title: '알림을 모두 삭제할까요?',
      message: '삭제하면 되돌릴 수 없어요.',
      confirmLabel: '삭제',
      confirmColor: AppColors.accentDanger,
      confirmKey: const Key('notification-delete-all-confirm'),
      cancelKey: const Key('notification-delete-all-cancel'),
    );
    if (confirmed != true || !mounted) return;
    final previous = _items;
    setState(() => _items = const []);
    try {
      final token = await widget.tokenLoader();
      await widget.api.deleteAll(token);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = previous);
      _showDeleteFailed();
    }
  }

  void _showDeleteFailed() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(_deleteFailedMessage)));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppColors.surfaceSoft,
      appBar: AppBar(
        title: const Text('알림 내역'),
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (items != null && items.isNotEmpty)
            TextButton(
              key: const Key('notification-delete-all'),
              onPressed: _confirmDeleteAll,
              style: TextButton.styleFrom(foregroundColor: AppColors.muted),
              child: const Text('전체 삭제'),
            ),
        ],
      ),
      body: items == null
          ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : _HistoryErrorState(message: _error!, onRetry: _load)
          : items.isEmpty
          ? const Center(child: Text('아직 받은 알림이 없어요'))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              // 목록을 스크롤하기 시작하면 열려 있던 삭제 버튼을 닫는다(투두와 같다).
              child: NotificationListener<ScrollStartNotification>(
                onNotification: (_) {
                  _slidableGroup.closeAll();
                  return false;
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.content,
                    AppSpacing.content,
                    AppSpacing.content,
                    AppSpacing.content +
                        MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  children: [
                    for (final item in items) ...[
                      SwipeActionRow(
                        key: ValueKey(
                          'notification-slidable-${item.id}'
                          '-${_restoredGeneration[item.id] ?? 0}',
                        ),
                        group: _slidableGroup,
                        onDismissed: () => _delete(item),
                        actions: [
                          SwipeActionButton(
                            key: ValueKey('notification-delete-${item.id}'),
                            label: '삭제',
                            icon: Icons.delete_outline,
                            background: AppColors.accentDanger,
                            foreground: AppColors.onPrimary,
                            onPressed: () => _delete(item),
                          ),
                        ],
                        child: _NotificationRow(
                          item: item,
                          onTap: () => _onTap(item),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item, required this.onTap});

  final NotificationHistoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 밀어서 지우는 행이라 리플(InkWell) 대신 눌림 배경을 직접 그린다 — 리플은 밀리는 동안
    // 배경이 남는다(design.md §8, 투두 행과 같다).
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: PressableBox(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: AppSpacing.xxl,
                height: AppSpacing.xxl,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: const Icon(
                  Icons.notifications_none,
                  color: AppColors.mutedSoft,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (!item.read) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.accentDanger,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Expanded(
                          child: Text(item.title, style: AppTypography.title),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.body,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _relativeTime(item.createdAt),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relativeTime(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${createdAt.year}.${createdAt.month.toString().padLeft(2, '0')}.'
      '${createdAt.day.toString().padLeft(2, '0')}';
}

class _HistoryErrorState extends StatelessWidget {
  const _HistoryErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.content),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: AppTypography.bodySmall),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
