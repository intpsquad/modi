import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../auth/auth_service.dart';
import '../room/room_session.dart';
import '../settings/settings_screens.dart' show TokenLoader;
import 'notification_router.dart';
import 'notifications_api.dart';

/// S-41 알림 내역 — specs/0017-알림-내역.md. `PastRoomsScreen`과 같은 마이페이지 톤
/// (surfaceSoft 배경 + canvas AppBar + 테두리 없는 흰 카드 리스트)을 재사용한다.
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

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppColors.surfaceSoft,
      appBar: AppBar(
        title: const Text('알림 내역'),
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
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
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.content,
                  AppSpacing.content,
                  AppSpacing.content,
                  AppSpacing.content + MediaQuery.viewPaddingOf(context).bottom,
                ),
                children: [
                  for (final item in items) ...[
                    _NotificationRow(item: item, onTap: () => _onTap(item)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
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
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
