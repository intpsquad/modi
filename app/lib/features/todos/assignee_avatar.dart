import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'todos_api.dart';

/// 담당자 프로필 아바타(원형) — 투두 탭 행과 투두 폼 시트 담당자 행이 공용으로 쓴다.
/// profileImage가 있으면 네트워크 이미지, 없으면 닉네임 첫 글자. design.md §5 아바타 규격.
class AssigneeAvatar extends StatelessWidget {
  const AssigneeAvatar({super.key, required this.member, this.size = 28});

  final MemberBrief member;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceSoft,
        image: member.profileImage != null
            ? DecorationImage(
                image: NetworkImage(member.profileImage!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: member.profileImage == null
          ? Text(
              member.nickname.isNotEmpty ? member.nickname[0] : '?',
              style: AppTypography.caption,
            )
          : null,
    );
  }
}
