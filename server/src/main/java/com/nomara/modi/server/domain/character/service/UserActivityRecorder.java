package com.nomara.modi.server.domain.character.service;

import com.nomara.modi.server.domain.character.entity.UserActivity;
import com.nomara.modi.server.domain.character.entity.UserActivityKind;
import com.nomara.modi.server.domain.character.repository.UserActivityRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 협업 캐릭터(specs/0016-협업-캐릭터.md) 판정용 접속·조회 로그를 남긴다.
 *
 * <p><b>실패해도 예외를 던지지 않는다</b> — 로그는 부수 효과라, 여기서 문제가 생겨 대시보드 조회·자료 상세 조회 같은 핵심 동작이 실패하면 안 된다({@code
 * ActivityService.record}와 같은 방향).
 *
 * <p>🔴 <b>{@code REQUIRES_NEW}가 필수다.</b> 호출부(예: {@code ArchiveItemService.getDetail}, {@code
 * TodoService.getTodo})는 {@code readOnly} 트랜잭션이다 — 기본 {@code REQUIRED} 전파로 그 트랜잭션에 합류하면 여기서의
 * 쓰기(insert)가 read-only 위반으로 실패하고, Java에서 예외를 잡아도 <b>트랜잭션은 이미 rollback-only로 표시된 뒤</b>라 호출부의 나머지
 * 조회까지 "current transaction is aborted"로 함께 죽는다(실제로 겪은 회귀). 별도 트랜잭션으로 분리해야 실패가 호출부에 전혀 새지 않는다.
 */
@Service
public class UserActivityRecorder {

  private static final Logger log = LoggerFactory.getLogger(UserActivityRecorder.class);

  private final UserActivityRepository userActivityRepository;
  private final UserRepository userRepository;

  public UserActivityRecorder(
      UserActivityRepository userActivityRepository, UserRepository userRepository) {
    this.userActivityRepository = userActivityRepository;
    this.userRepository = userRepository;
  }

  @Transactional(propagation = Propagation.REQUIRES_NEW)
  public void record(String uid, UserActivityKind kind, Room room, Long targetId) {
    try {
      User user = userRepository.getReferenceById(uid);
      userActivityRepository.save(new UserActivity(user, room, kind, targetId));
    } catch (Exception e) {
      log.warn("접속·조회 로그 기록 실패(무시하고 계속): uid={} kind={}", uid, kind, e);
    }
  }
}
