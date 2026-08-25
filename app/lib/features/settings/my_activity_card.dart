import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// 마이페이지 활동 카드 데이터. 백엔드 `GET /me/character`(specs/0016-협업-캐릭터.md,
/// docs/backend/character-handoff.md)가 붙으면 채워진다. 지금은 목업으로 채우며,
/// 값이 없으면 [MyActivityCard]가 placeholder 상태로 렌더한다.
class MyActivitySummary {
  const MyActivitySummary({
    this.characterId,
    this.characterName,
    this.characterQuote,
    this.characterDetail,
    this.deadlineKeptPercent,
    this.bestStreakDays,
    this.sharedCount,
    this.completedCount,
  });

  /// 서버 응답 스키마(§4.3) 그대로 파싱. 지표는 계약의 비율(0~1)/개수를 카드 표시 단위로 변환.
  factory MyActivitySummary.fromJson(Map<String, dynamic> json) {
    final stats = json['activityStats'] as Map<String, dynamic>?;
    final keptRate = (stats?['deadlineKeptRate'] as num?)?.toDouble();
    // 마감일 있는 완료 투두가 하나도 없으면 서버가 deadlineKeptRate=0.0을 보내는데, 이건 "0%
    // 준수"가 아니라 "잴 데이터 없음"이다 — dueDateCompletedCount로 그 경우를 구분해 칩 자체를
    // 숨긴다(2026-08-09, 마감 없는 투두만 있어도 "마감 준수 0%"로 보이던 오표시 수정).
    final dueDateCompletedCount =
        (stats?['dueDateCompletedCount'] as num?)?.toInt() ?? 0;
    return MyActivitySummary(
      characterId: json['characterId'] as String?,
      characterName: json['name'] as String?,
      characterQuote: json['copy'] as String?,
      characterDetail: json['why'] as String?,
      deadlineKeptPercent: (keptRate == null || dueDateCompletedCount == 0)
          ? null
          : (keptRate * 100).round(),
      bestStreakDays: (stats?['streak'] as num?)?.toInt(),
      sharedCount: (stats?['shared'] as num?)?.toInt(),
      completedCount: (stats?['completed'] as num?)?.toInt(),
    );
  }

  /// 서버가 주는 캐릭터 식별자(`PROCRASTINATOR` 등). 로컬 일러스트 매핑에 쓴다.
  final String? characterId;
  final String? characterName;
  final String? characterQuote;
  final String? characterDetail;
  final int? deadlineKeptPercent;
  final int? bestStreakDays;
  final int? sharedCount;
  final int? completedCount;
}

/// 캐릭터 id → 로컬 일러스트 파일명. 서버는 URL이 아니라 id만 주므로(specs/0016) 앱이 매핑한다.
const _characterImageFiles = <String, String>{
  'PROCRASTINATOR': 'procrastinator.png',
  'GHOST': 'ghost.png',
  'LURKER': 'lurker.png',
  'TURTLE': 'turtle.png',
  'STEADY': 'steady.png',
  'SPRINTER': 'sprinter.png',
  'EARLYBIRD': 'earlybird.png',
  'THE_J': 'the_j.png',
  'CHEERLEADER': 'cheerleader.png',
  'WARMING_UP': 'warming_up.png',
};

/// [characterId]에 대응하는 로컬 에셋 경로. 미지정·미지 id는 `warming_up`(분석 중)으로 폴백.
String characterAssetPath(String? characterId) {
  final file = _characterImageFiles[characterId] ?? 'warming_up.png';
  return 'assets/images/characters/$file';
}

/// S-40 마이페이지 중앙 활동 상태 카드 — specs/0012-설정.md.
///
/// ⚠️ 디자이너 지정 픽셀·색이 design.md 토큰 스케일 밖인 값이 있다(off-scale 간격 20/34/10,
/// 칩 테두리 #D1D1D6, 칩 텍스트 12/500). design.md 반영 전까지 이 컴포넌트 예외 —
/// specs/OPEN.md 드리프트 항목 참고.
class MyActivityCard extends StatelessWidget {
  const MyActivityCard({super.key, required this.nickname, this.summary});

  final String nickname;

  /// null이면 캐릭터 판정 데이터가 아직 없는 placeholder 상태(A안, 2026-08-07).
  final MyActivitySummary? summary;

  // `showScopeCaption`(마이페이지에서 스코프 캡션 끄기)은 2026-08-25(#68)에 제거했다 —
  // 마이페이지에 카드가 없어지면서 캡션을 끌 호출자가 남지 않았다.

  // 칩 테두리(디자이너 지정, 토큰 밖).
  static const _chipBorder = Color(0xFFD1D1D6);

  @override
  Widget build(BuildContext context) {
    final s = summary;
    // 서버 미로드/실패 시 fallback. 서버 WARMING_UP 캐릭터(정체불명/곧 정체가 드러나요)와 톤 통일
    // — 서버 CharacterCatalog의 WARMING_UP 문구 변경 요청과 짝(2026-08-07, 사용자 확정).
    final title = s?.characterName ?? '정체불명';
    final quote = s?.characterQuote ?? '곧 정체가 드러나요';
    final detail = s?.characterDetail ?? '투두를 완료할수록 더 정확해져요';

    // 분석 전(값 null)에는 해당 칩을 아예 숨긴다(2026-08-07 요청) — placeholder면 4개 모두 사라짐.
    final metricChips = <_MetricChip>[
      if (s?.deadlineKeptPercent != null)
        _MetricChip(
          emoji: '⏳',
          label: '마감 준수',
          value: '${s!.deadlineKeptPercent}%',
        ),
      if (s?.bestStreakDays != null)
        _MetricChip(
          emoji: '🔥',
          label: '누적 달성',
          value: '${s!.bestStreakDays}일',
        ),
      if (s?.sharedCount != null)
        _MetricChip(emoji: '📚', label: '자료 공유', value: '${s!.sharedCount}회'),
      if (s?.completedCount != null)
        _MetricChip(emoji: '✅', label: '완료 항목', value: '${s!.completedCount}개'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('요즘 $nickname님은', style: AppTypography.section),
              const SizedBox(height: 20),
              // Hero 일러스트 자리(200×214, 2026-08-08 확대 요청 전 146×156에서 키움).
              // 캐릭터 id를 로컬 에셋으로 매핑해 그린다.
              // 분석 전(summary null)에는 캐릭터 이미지 없이 아이콘 placeholder.
              //
              // 흰 원 배경 없이 배경을 제거한(투명 PNG) 캐릭터 컷아웃만 보여준다(2026-08-08
              // 요청 — 이전엔 원형으로 크롭+흰 배경을 깔았는데, 그러면 누끼딴 의미가 없다).
              // `BoxFit.contain`으로 잘리지 않고 전체가 들어오게 한다.
              Center(
                child: SizedBox(
                  width: 200,
                  height: 214,
                  child: s != null
                      ? Image.asset(
                          characterAssetPath(s.characterId),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const _IllustrationFallback(),
                        )
                      : const _IllustrationFallback(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: AppTypography.section,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '"$quote"',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.foreground,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
              ),
              // 표시할 지표가 하나라도 있을 때만 간격 + 칩 줄을 그린다(placeholder면 통째로 생략).
              if (metricChips.isNotEmpty) ...[
                const SizedBox(height: 34),
                // flex 안 flex — 한 줄에 2개씩(가운데 정렬), 각 칩은 hug.
                ..._buildMetricRows(metricChips),
              ],
            ],
          ),
        ),
        // 캐릭터가 방이 아니라 전체 활동 기준이라는 걸 카드 밖에 짧게 알려준다(2026-08-09 QA
        // — 멤버 상세(특정 방 맥락)에서 이 카드를 보면 "이 방에서"로 오해하기 쉬웠다). 분석 전
        // (summary null) placeholder에는 아직 합칠 데이터가 없어 표시하지 않는다.
        if (s != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '모든 방 활동을 합친 기록이에요',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: AppColors.mutedSoft),
          ),
        ],
      ],
    );
  }

  /// 지표 칩을 한 줄에 2개씩(가운데 정렬) 쌓는다 — flex 안 flex(Column 안 Row).
  /// 각 칩은 hug(내용폭). 홀수면 마지막 줄은 칩 하나만 가운데.
  List<Widget> _buildMetricRows(List<_MetricChip> chips) {
    final rows = <Widget>[];
    for (var i = 0; i < chips.length; i += 2) {
      final rowChips = <Widget>[chips[i]];
      if (i + 1 < chips.length) {
        rowChips.add(const SizedBox(width: AppSpacing.sm));
        rowChips.add(chips[i + 1]);
      }
      rows.add(
        Row(mainAxisAlignment: MainAxisAlignment.center, children: rowChips),
      );
      if (i + 2 < chips.length) {
        rows.add(const SizedBox(height: AppSpacing.sm));
      }
    }
    return rows;
  }
}

class _IllustrationFallback extends StatelessWidget {
  const _IllustrationFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.emoji_emotions_outlined,
        size: AppSpacing.xxl,
        color: AppColors.mutedSoft,
      ),
    );
  }
}

/// 캡슐 칩 — 흰 배경 + #D1D1D6 테두리 + (이모지 + 레이블 + 값) 12/500 #929292.
class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.emoji,
    required this.label,
    required this.value,
  });

  final String emoji;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // 12/500 #929292 — 디자이너 지정(토큰 밖 크기).
    final style = AppTypography.caption.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AppColors.mutedSoft,
    );
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: MyActivityCard._chipBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: AppSpacing.xs),
          Text('$label $value', style: style, maxLines: 1),
        ],
      ),
    );
  }
}
