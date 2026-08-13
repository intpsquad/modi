import 'package:flutter/material.dart';

import 'tokens.dart';

/// 하단 4개 탭(투두·일정·모아보기·마이) 공용 상단 제목 바.
/// 제목·크기·굵기·위치를 통일한다: `section`(20/600) 좌측 정렬, 좌 [content]/우 [sm] 패딩,
/// 고정 높이 [height], 우측 [action] 슬롯(+ 버튼·⋮ 등). 없으면 제목만.
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, required this.title, this.action});

  /// 4개 탭 상단 제목 바의 통일 높이.
  static const double height = 56;

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.content,
          right: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(child: Text(title, style: AppTypography.section)),
            ?action,
          ],
        ),
      ),
    );
  }
}
