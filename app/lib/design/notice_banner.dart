import 'package:flutter/material.dart';

import 'tokens.dart';

/// 한 줄 안내/주의 배너 — 흰 배경 + **연한 회색 테두리**(`border` 1px) + **회색 그림자**(§5 float) +
/// 좌측 아이콘 + 문구. AI 표식이 아닌 일반 안내에 쓴다([AiHintBanner]는 AI 그라데이션 전용).
///
/// 규격은 [AiHintBanner]와 맞춘다: 높이 40 · `radius.control`(16) · 가로 패딩 16 · 아이콘 20 ·
/// 아이콘↔문구 간격 8 · 문구 13px(`caption`). 문구는 남는 폭을 다 쓰고, 길면 말줄임으로 자른다.
/// [bold]가 문구 안에 있으면 그 부분만 굵게 그린다(예: "MODI").
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.text,
    this.bold,
    this.iconAsset = 'assets/icons/icon_warning.png',
    this.onTap,
    this.maxLines = 1,
  });

  /// 배너 문구. 사용처마다 바꿔 쓴다.
  final String text;

  /// [text] 안에서 굵게 강조할 부분 문자열(있으면 첫 등장 1회만). null이면 강조 없음.
  final String? bold;

  /// 좌측 아이콘(디자이너 제공 PNG — 자체 채색이라 tint 없이 그대로 그린다).
  final String iconAsset;

  /// 누를 수 있는 배너면 준다. null이면 표시 전용.
  final VoidCallback? onTap;

  final int maxLines;

  static const double _height = 40;
  static const double _iconSize = 20;
  static const EdgeInsets _padding = EdgeInsets.symmetric(horizontal: 16);

  /// **아주 옅은** 그림자(2026-08-09 사용자 요청 "완전완전 연하게"). §5 float 티어(≈10% 검정)는
  /// 이 배너엔 너무 진해서, AI 표식 글로우처럼 이 컴포넌트 전용으로 한 단계 얹는다 — 검정 4%
  /// 한 층만. 다른 컴포넌트로 퍼뜨리지 않는다(float 토큰은 그대로 둔다).
  static const List<BoxShadow> _shadow = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// [bold]가 [text] 안에 있으면 [before, bold, after]로 쪼개 강조 span을 만든다.
  List<InlineSpan> _spans() {
    final base = AppTypography.caption.copyWith(color: AppColors.foreground);
    final key = bold;
    if (key == null || key.isEmpty) {
      return [TextSpan(text: text, style: base)];
    }
    final i = text.indexOf(key);
    if (i < 0) return [TextSpan(text: text, style: base)];
    return [
      if (i > 0) TextSpan(text: text.substring(0, i), style: base),
      TextSpan(
        text: key,
        style: base.copyWith(fontWeight: FontWeight.w700),
      ),
      if (i + key.length < text.length)
        TextSpan(text: text.substring(i + key.length), style: base),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: _padding,
      child: Row(
        children: [
          Image.asset(
            iconAsset,
            width: _iconSize,
            height: _iconSize,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text.rich(
              TextSpan(children: _spans()),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border),
        boxShadow: _shadow,
      ),
      // 흰 면을 Material 로 둬 Scaffold 밖에서도 잉크가 동작하고 리플이 라운드 안에 그려진다.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppRadius.control),
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? row
            : Semantics(
                button: true,
                child: InkWell(onTap: onTap, child: row),
              ),
      ),
    );
  }
}
