import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../room/default_cover.dart';
import 'home_api.dart';

/// 히어로 펼침 높이(상태바 포함 — SliverAppBar.expandedHeight 규약).
/// 2026-08-07: 300→336, 배너(상단 고정)와 D-day/종료일(하단 고정) 사이 간격을 넓힘.
const double kHomeHeroExpandedHeight = 336;

/// 홈 컬랩싱 히어로 — specs/0005-홈-대시보드.md. 3단계:
/// ① 펼침: 배경 이미지 위 타이틀·D-day·진행률 바가 크고 선명.
/// ② 스크롤 중: **D-day는 스케일 축소 + 페이드**, 진행률·설명은 페이드아웃, 이미지 점점 흰색으로.
/// ③ 접힘: 배경 이미지 완전히 사라지고(흰색), D-day·진행률 opacity 0, **상단 앱바(방이름▾ / ☰)만
///    흰 배경으로 고정(sticky)** — 아래 콘텐츠가 그 밑에서 스크롤.
///
/// 접힘 정도 t(0=펼침, 1=접힘)는 SliverAppBar가 제공하는 [FlexibleSpaceBarSettings]로 계산한다.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.room,
    required this.progress,
    required this.todoDone,
    required this.todoTotal,
    required this.onRoomTap,
    required this.onNotificationsTap,
    this.menuOpen = false,
    this.banner,
    this.unreadNotificationCount = 0,
  });

  final RoomInfo room;
  final double? progress;
  final int? todoDone;
  final int? todoTotal;

  /// 홈 벨 배지에 표시할 안읽은 알림 개수(S-41, specs/0017-알림-내역.md). 0이면 배지 숨김.
  final int unreadNotificationCount;

  /// 상단 바(방이름▾) 바로 아래에 얹는 라이브 활동 배너(2026-08-07 요청). 없으면 null.
  /// 히어로가 접힐수록 D-day·진행률과 함께 페이드한다.
  final Widget? banner;

  /// 방 전환 시트가 열려 있는지 — 열려 있으면 방이름 옆 토글이 180도 돌아간다(2026-08-05 요청).
  final bool menuOpen;

  final VoidCallback onRoomTap;
  final VoidCallback onNotificationsTap;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    double t = 0;
    if (settings != null) {
      final delta = settings.maxExtent - settings.minExtent;
      if (delta > 0) {
        final expanded = ((settings.currentExtent - settings.minExtent) / delta)
            .clamp(0.0, 1.0);
        t = 1 - expanded;
      }
    }

    final topPadding = MediaQuery.of(context).padding.top;
    // 접히면 앱바 아이템은 ink(흰 배경), 펼치면 이미지 위 흰색.
    final barItemColor = Color.lerp(
      AppColors.onPrimary,
      AppColors.foreground,
      t,
    )!;
    final contentOpacity = (1 - t).clamp(0.0, 1.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t < 0.5 ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1) 배경 이미지/그라데이션.
          _HeroBackground(coverImageUrl: room.coverImageUrl, roomId: room.id),
          // 2) 딤 그라데이션(상단 70%→하단 40%) — 접히면 페이드.
          if (contentOpacity > 0)
            IgnorePointer(
              child: Opacity(
                opacity: contentOpacity,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xB3000000), Color(0x66000000)],
                    ),
                  ),
                ),
              ),
            ),
          // 3) 흰색 오버레이 — 접힐수록 이미지를 흰색으로 덮어 최종엔 흰 배경.
          IgnorePointer(
            child: ColoredBox(color: AppColors.canvas.withValues(alpha: t)),
          ),
          // 4) 흰 바디 lip — 히어로 바닥 상단 좌우 라운드로 아래 콘텐츠와 잇는다(항상 불투명).
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: AppRadius.bodySheet,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadius.bodySheet),
                  ),
                ),
              ),
            ),
          ),
          // 5) 히어로 콘텐츠 — 접힐수록 전체 페이드(1-t). (D-day 스케일 애니메이션은 제거됨)
          if (contentOpacity > 0)
            Positioned(
              left: AppSpacing.content,
              right: AppSpacing.content,
              bottom: AppRadius.bodySheet + AppSpacing.sm,
              child: IgnorePointer(
                child: Opacity(
                  opacity: contentOpacity,
                  child: _HeroContent(
                    room: room,
                    progress: progress,
                    todoDone: todoDone,
                    todoTotal: todoTotal,
                  ),
                ),
              ),
            ),
          // 6) 상단 고정 바 — 방이름▾ / ☰.
          Positioned(
            top: topPadding,
            left: 0,
            right: 0,
            height: kToolbarHeight,
            child: _HeroTopBar(
              roomName: room.name,
              itemColor: barItemColor,
              menuOpen: menuOpen,
              onRoomTap: onRoomTap,
              onNotificationsTap: onNotificationsTap,
              unreadNotificationCount: unreadNotificationCount,
            ),
          ),
          // 7) 라이브 활동 배너 — 상단 바 바로 아래(2026-08-07 요청). 접힘 시 함께 페이드.
          if (banner != null && contentOpacity > 0)
            Positioned(
              top: topPadding + kToolbarHeight,
              left: AppSpacing.content,
              right: AppSpacing.content,
              child: Opacity(opacity: contentOpacity, child: banner),
            ),
        ],
      ),
    );
  }
}

class _HeroBackground extends StatelessWidget {
  const _HeroBackground({this.coverImageUrl, required this.roomId});

  final String? coverImageUrl;

  /// 대표 이미지를 안 올린 방의 기본 배경을 정하는 값(요청 4) — 방마다 고정이다.
  final int roomId;

  static const _fallbackGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.primaryActive],
  );

  @override
  Widget build(BuildContext context) {
    final url = coverImageUrl;
    // 그라데이션은 이미지가 뜨기 전/실패했을 때의 바닥으로 항상 깔아둔다.
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: _fallbackGradient),
        ),
        if (url == null || url.isEmpty)
          Image.asset(
            defaultCoverAsset(roomId),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          )
        else
          Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
      ],
    );
  }
}

class _HeroTopBar extends StatelessWidget {
  const _HeroTopBar({
    required this.roomName,
    required this.itemColor,
    required this.menuOpen,
    required this.onRoomTap,
    required this.onNotificationsTap,
    this.unreadNotificationCount = 0,
  });

  final String roomName;
  final Color itemColor;
  final bool menuOpen;
  final VoidCallback onRoomTap;
  final VoidCallback onNotificationsTap;
  final int unreadNotificationCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.content,
        right: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onRoomTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      roomName,
                      style: AppTypography.section.copyWith(color: itemColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 시트가 열리면 180도 돌고 닫히면 되돌아온다(2026-08-05 요청) —
                  // 아이콘이 "지금 열려 있음"을 알려준다.
                  AnimatedRotation(
                    turns: menuOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: Icon(Icons.expand_more, color: itemColor, size: 20),
                  ),
                ],
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: onNotificationsTap,
                icon: Icon(Icons.notifications_none, color: itemColor),
              ),
              // 안읽은 알림 배지(S-41, specs/0017-알림-내역.md). 9개 넘으면 "9+"로 캡.
              if (unreadNotificationCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.accentDanger,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        unreadNotificationCount > 9
                            ? '9+'
                            : '$unreadNotificationCount',
                        style: AppTypography.badge.copyWith(
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({
    required this.room,
    required this.progress,
    required this.todoDone,
    required this.todoTotal,
  });

  final RoomInfo room;
  final double? progress;
  final int? todoDone;
  final int? todoTotal;

  @override
  Widget build(BuildContext context) {
    final remaining = room.daysRemaining;
    final ddayLabel = remaining <= 0 ? 'D-DAY' : 'D-$remaining';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 종료일 (D-day 위) — "YYYY.MM.DD 종료"(2026-08-07 요청: '디데이' 라벨 대신 날짜 뒤 '종료').
        Text(
          '${_formatDate(room.endDate)} 종료',
          key: const ValueKey('hero-dday-label'),
          style: AppTypography.bodySmall.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: AppSpacing.xs),
        // D-day. 접힘 시 부모 Opacity로 페이드된다(스케일 애니메이션 없음).
        Text(
          ddayLabel,
          style: AppTypography.displayDday.copyWith(color: AppColors.onPrimary),
        ),
        if (progress != null) ...[
          const SizedBox(height: AppSpacing.md),
          _HeroProgressBar(progress: progress!),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                // B안(2026-08-08): 개수(N/M)는 빼고 라벨만 — 진행 정도는 우측 %와 바로 전달.
                '함께 달성한 투두',
                style: AppTypography.bodySmall.copyWith(color: Colors.white70),
              ),
              const Spacer(),
              Text(
                '${(progress! * 100).round()}%',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }
}

/// 히어로 진행률 바 — 이미지 위라 트랙·채움을 흰색 계열로(design.md §6).
class _HeroProgressBar extends StatelessWidget {
  const _HeroProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 6,
        backgroundColor: Colors.white24,
        valueColor: const AlwaysStoppedAnimation(AppColors.onPrimary),
      ),
    );
  }
}
