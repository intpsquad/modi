import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../auth/auth_service.dart';
import '../settings/settings_screens.dart';

/// S-05 종료된 방 요약 홈.
///
/// 현재 서버가 목록에서 제공하는 최종 완료율/기간은 실제 값으로 표시하고,
/// 아직 집계 계약이 없는 활동·하이라이트 항목은 명시적인 빈 상태로 보여준다.
class EndedRoomSummaryScreen extends StatefulWidget {
  EndedRoomSummaryScreen({
    super.key,
    required this.roomId,
    SettingsApi? api,
    TokenLoader? tokenLoader,
  }) : api = api ?? SettingsApi(),
       tokenLoader = tokenLoader ?? AuthService().getIdToken;

  final int roomId;
  final SettingsApi api;
  final TokenLoader tokenLoader;

  @override
  State<EndedRoomSummaryScreen> createState() => _EndedRoomSummaryScreenState();
}

class _EndedRoomSummaryScreenState extends State<EndedRoomSummaryScreen> {
  PastRoom? _room;
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
      final rooms = await widget.api.fetchPastRooms(token);
      PastRoom? room;
      for (final candidate in rooms) {
        if (candidate.id == widget.roomId) {
          room = candidate;
          break;
        }
      }
      if (room == null) throw StateError('종료된 방을 찾을 수 없어요');
      if (mounted) setState(() => _room = room);
    } catch (_) {
      if (mounted) setState(() => _error = '종료된 방 요약을 불러오지 못했어요');
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    if (room == null) {
      return Scaffold(
        body: _error == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.content),
          children: [
            Row(
              children: [
                Expanded(child: Text(room.name, style: AppTypography.section)),
                OutlinedButton.icon(
                  onPressed: () => context.push('/room/edit/${room.id}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(96, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                  ),
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('재시작'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              '${room.durationDays}일간의 목표가 끝났어요',
              style: AppTypography.display,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${_date(room.startDate)} – ${_date(room.endDate)}',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            _SummaryCard(
              title: '최종 목표 달성 현황',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${room.completionPercent}%',
                    style: AppTypography.displayHero.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LinearProgressIndicator(
                    value: room.completionRate.clamp(0, 1),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _SummaryCard(
              title: '내 활동 요약',
              child: Text('활동 기록이 없어요', style: AppTypography.bodySmall),
            ),
            const SizedBox(height: AppSpacing.md),
            const _SummaryCard(
              title: '팀 하이라이트',
              child: Text('활동 기록이 없어요', style: AppTypography.bodySmall),
            ),
            const SizedBox(height: AppSpacing.md),
            const _SummaryCard(
              title: '아카이브 하이라이트',
              child: Text('등록된 자료가 없어요', style: AppTypography.bodySmall),
            ),
          ],
        ),
      ),
    );
  }

  String _date(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.'
      '${date.day.toString().padLeft(2, '0')}';
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.title)),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Text('읽기전용', style: AppTypography.badge),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
