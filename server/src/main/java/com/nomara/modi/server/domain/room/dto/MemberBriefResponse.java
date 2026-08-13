package com.nomara.modi.server.domain.room.dto;

import com.nomara.modi.server.domain.room.entity.RoomMember;
import com.nomara.modi.server.domain.user.entity.User;

public record MemberBriefResponse(String userId, String nickname, String profileImage) {

  public static MemberBriefResponse of(RoomMember member) {
    return of(member.getUser());
  }

  /**
   * 방 멤버십을 거치지 않고 사용자만으로 만든다 — 자료 등록자처럼 "이 콘텐츠를 만든 사람"을 실을 때 쓴다(2026-08-08, S-25-B).
   *
   * <p>{@code null}을 그대로 돌려주는 이유: 탈퇴한 사용자의 콘텐츠는 남고 작성자만 {@code null}이 되므로({@code
   * V9__account_deletion_cascades.sql}) 호출부마다 분기를 쓰지 않게 여기서 흡수한다. 앱은 등록자가 없으면 아바타 자리를 비운다.
   */
  public static MemberBriefResponse of(User user) {
    if (user == null) {
      return null;
    }
    return new MemberBriefResponse(user.getId(), user.getNickname(), user.getProfileImage());
  }
}
