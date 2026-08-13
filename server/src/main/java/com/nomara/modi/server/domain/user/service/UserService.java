package com.nomara.modi.server.domain.user.service;

import com.google.firebase.FirebaseApp;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import com.nomara.modi.server.domain.room.entity.Room;
import com.nomara.modi.server.domain.room.repository.RoomMemberRepository;
import com.nomara.modi.server.domain.room.service.RoomService;
import com.nomara.modi.server.domain.user.dto.ProfilePhotoUploadUrlResponse;
import com.nomara.modi.server.domain.user.dto.UpdateProfileRequest;
import com.nomara.modi.server.domain.user.dto.UserProfileResponse;
import com.nomara.modi.server.domain.user.entity.LoginProvider;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.exception.UserNotFoundException;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ServiceUnavailableException;
import com.nomara.modi.server.global.storage.ObjectStorage;
import java.time.Duration;
import java.util.Optional;
import java.util.concurrent.ThreadLocalRandom;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class UserService {

  private static final Logger log = LoggerFactory.getLogger(UserService.class);
  private static final Duration UPLOAD_URL_EXPIRY = Duration.ofMinutes(5);

  private final UserRepository userRepository;
  private final RoomMemberRepository roomMemberRepository;
  private final RoomService roomService;
  private final Optional<ObjectStorage> objectStorage;
  private final Optional<FirebaseApp> firebaseApp;

  public UserService(
      UserRepository userRepository,
      RoomMemberRepository roomMemberRepository,
      RoomService roomService,
      Optional<ObjectStorage> objectStorage,
      Optional<FirebaseApp> firebaseApp) {
    this.userRepository = userRepository;
    this.roomMemberRepository = roomMemberRepository;
    this.roomService = roomService;
    this.objectStorage = objectStorage;
    this.firebaseApp = firebaseApp;
  }

  @Transactional
  public void registerFcmToken(
      String uid, String displayName, String token, LoginProvider loginProvider, String email) {
    User user = ensureUser(uid, displayName, loginProvider, email);
    user.updateFcmToken(token);
  }

  @Transactional
  public User ensureSocialUser(String uid, String nickname) {
    return ensureSocialUser(uid, nickname, null);
  }

  @Transactional
  public User ensureSocialUser(String uid, String nickname, String profileImage) {
    return ensureSocialUser(uid, nickname, profileImage, null);
  }

  /**
   * 유일한 카카오 진입점(`/auth/kakao`) — Firebase ID 토큰이 없는 시점이라 provider를 직접 KAKAO로 고정한다. {@code email}은
   * Kakao API 응답에서 온다(Custom Token 발급 후엔 Firebase ID 토큰에 이메일이 안 실려 이 경로가 유일한 확보 지점).
   */
  @Transactional
  public User ensureSocialUser(String uid, String nickname, String profileImage, String email) {
    User user =
        userRepository
            .findById(uid)
            .orElseGet(
                () ->
                    userRepository.save(
                        new User(
                            uid, nicknameOrFallback(nickname), profileImage, LoginProvider.KAKAO)));
    updateEmailIfPresentAndChanged(user, email);
    return user;
  }

  @Transactional(readOnly = true)
  public UserProfileResponse getProfile(String uid) {
    return userRepository
        .findById(uid)
        .map(UserProfileResponse::of)
        .orElseThrow(UserNotFoundException::new);
  }

  @Transactional
  public UserProfileResponse updateProfile(
      String uid,
      String displayName,
      UpdateProfileRequest request,
      LoginProvider loginProvider,
      String email) {
    User user = ensureUser(uid, displayName, loginProvider, email);
    user.changeNickname(request.nickname());
    user.changeProfileImage(request.profileImage());
    return UserProfileResponse.of(user);
  }

  /**
   * S-40 회원 탈퇴(specs/0012-설정.md). 소속된 모든 방을 먼저 나가고(마지막 멤버면 방도 하드 삭제 — {@link RoomService#leaveRoom}
   * 재사용), 유저 행을 지운다. 좋아요·콕찌르기·투두담당·알림설정은 DB 레벨 CASCADE로, 다른 멤버가 남은 방의 아카이브 자료는 작성자만 SET NULL로
   * 정리된다(V9 마이그레이션 참고, 2026-08-03 확정). Firebase 계정 삭제는 DB 커밋 이후 별도로 시도한다 — DB 삭제가 실패하면 Firebase 계정이
   * 남아 있어야 재시도할 수 있고, 반대로 Firebase 삭제만 실패해도 앱 데이터는 이미 없어졌으니 탈퇴 자체는 완료로 본다(로그만 남김).
   */
  public void withdraw(String uid) {
    withdrawAppData(uid);
    deleteFirebaseAccountIfConfigured(uid);
  }

  @Transactional
  public void withdrawAppData(String uid) {
    for (Room room : roomMemberRepository.findRoomsByUserId(uid)) {
      roomService.leaveRoom(uid, room.getId());
    }
    // deleteById는 행이 없으면 예외를 던지므로(EmptyResultDataAccessException), 쓰기 API를
    // 한 번도 안 태워 User 행이 아직 없는 극단적 케이스를 위해 존재 확인 후 지운다.
    if (userRepository.existsById(uid)) {
      userRepository.deleteById(uid);
    }
  }

  private void deleteFirebaseAccountIfConfigured(String uid) {
    firebaseApp.ifPresent(
        app -> {
          try {
            FirebaseAuth.getInstance(app).deleteUser(uid);
          } catch (FirebaseAuthException e) {
            log.warn("탈퇴 후 Firebase 계정 삭제 실패: uid={}", uid, e);
          }
        });
  }

  /** specs/0012-설정.md 프로필 사진 — 유저당 1장, 재업로드 시 같은 키를 덮어쓴다. */
  public ProfilePhotoUploadUrlResponse createProfilePhotoUploadUrl(String uid) {
    ObjectStorage storage =
        objectStorage.orElseThrow(() -> new ServiceUnavailableException("이미지 업로드가 지금은 지원되지 않아요"));
    String objectKey = "profile/" + uid;
    return new ProfilePhotoUploadUrlResponse(
        storage.createPresignedUploadUrl(objectKey, UPLOAD_URL_EXPIRY),
        storage.publicUrl(objectKey));
  }

  /**
   * 신규 생성 시에만 {@code loginProvider}를 채운다 — 이미 있는 유저는 {@code findById}가 먼저 걸려 재로그인으로 덮어쓰지 않는다(설계).
   * {@code email}은 반대로 **매번** 값이 오고 다르면 갱신한다({@link #updateEmailIfPresentAndChanged}) — 계정 이메일이 바뀔
   * 수 있고, 이 컬럼이 생기기 전 유저를 자연 백필하는 유일한 경로이기 때문이다.
   */
  private User ensureUser(
      String uid, String displayName, LoginProvider loginProvider, String email) {
    User user =
        userRepository
            .findById(uid)
            .orElseGet(
                () ->
                    userRepository.save(
                        new User(uid, nicknameOrFallback(displayName), null, loginProvider)));
    updateEmailIfPresentAndChanged(user, email);
    return user;
  }

  /** V29 — email이 null이면 건드리지 않는다(이번 요청에 이메일이 안 실려 왔다고 기존 값을 지우면 안 된다). */
  private void updateEmailIfPresentAndChanged(User user, String email) {
    if (email != null && !email.equals(user.getEmail())) {
      user.changeEmail(email);
    }
  }

  private String nicknameOrFallback(String nickname) {
    if (nickname != null && !nickname.isBlank()) {
      return nickname.trim();
    }
    return "사용자" + ThreadLocalRandom.current().nextInt(1000, 10000);
  }
}
