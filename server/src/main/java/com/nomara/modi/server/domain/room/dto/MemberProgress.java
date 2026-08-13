package com.nomara.modi.server.domain.room.dto;

/** assignedTotal/assignedDone은 저장값이 아니라 요청 시점 집계(specs/0002-data-model.md 계산값). */
public record MemberProgress(
    String userId, String nickname, String profileImage, long assignedTotal, long assignedDone) {

  /** 정렬 전용 계산값(specs/0005-홈-대시보드.md: 멤버 아바타줄은 진행률 내림차순). 담당 0개는 0으로 취급해 뒤로 밀린다. */
  public double completionRate() {
    return assignedTotal == 0 ? 0.0 : (double) assignedDone / assignedTotal;
  }
}
