package com.nomara.modi.server.domain.poke.service;

import com.nomara.modi.server.domain.activity.entity.ActivityType;
import com.nomara.modi.server.domain.activity.service.ActivityService;
import com.nomara.modi.server.domain.poke.dto.PokeResponse;
import com.nomara.modi.server.domain.poke.entity.Poke;
import com.nomara.modi.server.domain.poke.entity.PokeType;
import com.nomara.modi.server.domain.poke.repository.PokeRepository;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.entity.RoomMemberId;
import com.nomara.modi.server.domain.room.exception.NotRoomMemberException;
import com.nomara.modi.server.domain.room.exception.RoomMemberNotFoundException;
import com.nomara.modi.server.domain.room.exception.RoomNotFoundException;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.repository.RoomRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.TooManyRequestsException;
import com.nomara.modi.server.global.notification.PushNotifier;
import com.nomara.modi.server.global.notification.PushType;
import java.time.Duration;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * specs/0011-멤버-투두-콕찌르기.md — 홈 아바타줄 콕찌르기와 S-30-M [콕 찌르기] 버튼은 같은 기능으로 통일(2026-07-29 확정,
 * specs/OPEN.md). 항상 {@link PokeType#POKE}로 기록한다({@code KNOCK}은 2026-08-09 제거, {@code
 * V27__drop_knock_enabled.sql}).
 */
@Service
public class PokeService {

  /** 발신자+대상 쌍 기준 30초당 10회 제한(2026-08-03 확정, specs/OPEN.md). 초과분은 창이 끝날 때까지 429. */
  private static final Duration RATE_LIMIT_WINDOW = Duration.ofSeconds(30);

  private static final long RATE_LIMIT_MAX = 10;

  private final PokeRepository pokeRepository;
  private final RoomRepository roomRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final UserRepository userRepository;
  private final PushNotifier pushNotifier;
  private final StringRedisTemplate redisTemplate;
  private final ActivityService activityService;

  public PokeService(
      PokeRepository pokeRepository,
      RoomRepository roomRepository,
      RoomMemberRepository roomMemberRepository,
      UserRepository userRepository,
      PushNotifier pushNotifier,
      StringRedisTemplate redisTemplate,
      ActivityService activityService) {
    this.pokeRepository = pokeRepository;
    this.roomRepository = roomRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.userRepository = userRepository;
    this.pushNotifier = pushNotifier;
    this.redisTemplate = redisTemplate;
    this.activityService = activityService;
  }

  @Transactional
  public PokeResponse sendPoke(String uid, Long roomId, String targetUserId) {
    requireMembership(uid, roomId);
    checkRateLimit(uid, targetUserId);
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, targetUserId))) {
      throw new RoomMemberNotFoundException();
    }
    Room room = roomRepository.findById(roomId).orElseThrow(RoomNotFoundException::new);
    User fromUser = userRepository.findById(uid).orElseThrow();
    User toUser = userRepository.findById(targetUserId).orElseThrow();

    Poke poke = pokeRepository.save(new Poke(room, fromUser, toUser, PokeType.POKE));

    pushNotifier.notify(
        toUser,
        PushType.POKE,
        room,
        fromUser.getNickname() + "님이 콕! 👀",
        room.getName() + " · 아직 안 끝난 투두 확인해볼까요?");

    activityService.record(room, ActivityType.POKE, fromUser, toUser, null, null);
    // 홈 활동 피드 POKE_ACCUMULATED(2026-08-06, docs/backend/home-activity-feed.md) — 받은
    // 누적 콕 수가 마일스톤(5배수)에 도달했을 때만 별도로 남긴다. actor는 "쌓인" 쪽(toUser)이다.
    long accumulated = pokeRepository.countByRoomIdAndToUserId(roomId, targetUserId);
    if (activityService.isMilestone(accumulated)) {
      activityService.record(
          room, ActivityType.POKE_ACCUMULATED, toUser, null, null, (int) accumulated);
    }

    return PokeResponse.of(poke);
  }

  /**
   * {@code EmailVerificationService}의 "증가 후 첫 호출에만 TTL 설정" 카운터 패턴 재사용. 다른 DB 조회보다 먼저 확인해 어차피 막힐 요청이
   * 불필요한 조회를 하지 않게 한다.
   */
  private void checkRateLimit(String fromUid, String toUid) {
    String key = "poke:rate:" + fromUid + ":" + toUid;
    Long count = redisTemplate.opsForValue().increment(key);
    if (count != null && count == 1L) {
      redisTemplate.expire(key, RATE_LIMIT_WINDOW);
    }
    if (count != null && count > RATE_LIMIT_MAX) {
      throw new TooManyRequestsException("콕찌르기를 너무 자주 보내고 있어요. 잠시 후 다시 시도해 주세요");
    }
  }

  private void requireMembership(String uid, Long roomId) {
    if (!roomMemberRepository.existsById(new RoomMemberId(roomId, uid))) {
      throw new NotRoomMemberException();
    }
  }
}
