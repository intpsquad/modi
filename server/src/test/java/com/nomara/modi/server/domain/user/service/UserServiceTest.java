package com.nomara.modi.server.domain.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowableOfType;
import static org.assertj.core.api.Assertions.within;

import com.nomara.modi.server.domain.user.dto.UpdateProfileRequest;
import com.nomara.modi.server.domain.user.dto.UserProfileResponse;
import com.nomara.modi.server.domain.user.entity.LoginProvider;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.exception.ApiException;
import java.time.temporal.ChronoUnit;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

/** specs/0011-멤버-투두-콕찌르기.md 콕찌르기 푸시에 쓰이는 FCM 토큰 등록 + specs/0012-설정.md 프로필 수정. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class UserServiceTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    // 로컬 개발 환경에 MINIO_ENDPOINT가 export돼 있으면 Spring이 test/resources/application.yml에
    // minio.* 선언이 전혀 없어도 그 값을 자동으로 relaxed binding해 조건부 빈을 활성화하려다 나머지
    // 프로퍼티(access-key 등) 없이 컨텍스트가 통째로 못 뜬다(실측 확인, 2026-07-29 리뷰) — DynamicPropertySource가
    // 환경변수보다 우선순위가 높으므로 여기서 명시적으로 꺼서 ObjectStorage 빈이 절대 안 뜨게 한다.
    registry.add("minio.endpoint", () -> "false");
  }

  @Autowired private UserService userService;
  @Autowired private UserRepository userRepository;

  @Test
  void registerFcmTokenStoresTokenForExistingUser() {
    userRepository.save(new User("uid-fcm-existing", "닉네임", null));

    userService.registerFcmToken("uid-fcm-existing", "닉네임", "token-1", null, null);

    assertThat(userRepository.findById("uid-fcm-existing").orElseThrow().getFcmToken())
        .isEqualTo("token-1");
  }

  @Test
  void registerFcmTokenCreatesUserWhenMissing() {
    userService.registerFcmToken("uid-fcm-new", "새유저", "token-2", LoginProvider.GOOGLE, null);

    User saved = userRepository.findById("uid-fcm-new").orElseThrow();
    assertThat(saved.getNickname()).isEqualTo("새유저");
    assertThat(saved.getFcmToken()).isEqualTo("token-2");
    // 신규 생성 시점에 넘긴 로그인 수단이 그대로 저장된다.
    assertThat(saved.getLoginProvider()).isEqualTo(LoginProvider.GOOGLE);
  }

  @Test
  void registerFcmTokenUsesFallbackWhenSocialProfileNameIsUnavailable() {
    userService.registerFcmToken("uid-fcm-no-name", null, "token-3", null, null);

    User saved = userRepository.findById("uid-fcm-no-name").orElseThrow();
    assertThat(saved.getNickname()).matches("사용자\\d{4}");
  }

  @Test
  void ensureSocialUserUsesFourDigitFallbackWhenNicknameIsUnavailable() {
    User saved = userService.ensureSocialUser("kakao:no-nickname", null);

    assertThat(saved.getNickname()).matches("사용자\\d{4}");
  }

  // ---- V29: email 백필/갱신(specs/OPEN.md — 정보성 컬럼, 중복판정에는 안 쓴다) ----

  @Test
  void registerFcmTokenStoresEmailForNewUser() {
    userService.registerFcmToken(
        "uid-email-new", "새유저", "token-email-1", LoginProvider.GOOGLE, "new@example.com");

    User saved = userRepository.findById("uid-email-new").orElseThrow();
    assertThat(saved.getEmail()).isEqualTo("new@example.com");
  }

  @Test
  void registerFcmTokenBackfillsEmailForExistingUserWithNullEmail() {
    // 이 컬럼이 생기기 전에 만들어진 유저(email 항상 null)가 다음 로그인에서 채워지는 경로.
    userRepository.save(new User("uid-email-backfill", "닉네임", null));

    userService.registerFcmToken(
        "uid-email-backfill", "닉네임", "token-email-2", null, "backfilled@example.com");

    assertThat(userRepository.findById("uid-email-backfill").orElseThrow().getEmail())
        .isEqualTo("backfilled@example.com");
  }

  @Test
  void registerFcmTokenUpdatesEmailWhenItChanges() {
    // loginProvider(신규 생성 시에만)와 달리 email은 값이 다르면 매번 갱신한다 — 계정 이메일이 바뀔 수 있어서.
    userRepository.save(new User("uid-email-change", "닉네임", null));
    userService.registerFcmToken(
        "uid-email-change", "닉네임", "token-email-3a", null, "old@example.com");

    userService.registerFcmToken(
        "uid-email-change", "닉네임", "token-email-3b", null, "changed@example.com");

    assertThat(userRepository.findById("uid-email-change").orElseThrow().getEmail())
        .isEqualTo("changed@example.com");
  }

  @Test
  void registerFcmTokenDoesNotClearEmailWhenIncomingEmailIsNull() {
    // Kakao 등 이번 요청엔 이메일이 안 실려 오는 경우 기존 값을 지우면 안 된다.
    userRepository.save(new User("uid-email-keep", "닉네임", null));
    userService.registerFcmToken(
        "uid-email-keep", "닉네임", "token-email-4a", null, "keep@example.com");

    userService.registerFcmToken("uid-email-keep", "닉네임", "token-email-4b", null, null);

    assertThat(userRepository.findById("uid-email-keep").orElseThrow().getEmail())
        .isEqualTo("keep@example.com");
  }

  @Test
  void ensureSocialUserStoresKakaoEmailFromKakaoApi() {
    // Kakao는 Firebase ID 토큰에 이메일이 없어 Kakao API 응답에서 직접 받아 채운다.
    User saved =
        userService.ensureSocialUser(
            "kakao:with-email", "카카오유저", "https://img.kakao.test/p.png", "kakao@example.com");

    assertThat(saved.getEmail()).isEqualTo("kakao@example.com");
  }

  @Test
  void ensureSocialUserSetsKakaoLoginProvider() {
    // 카카오 진입점은 Firebase ID 토큰이 없는 시점이라 항상 KAKAO로 고정된다.
    User saved = userService.ensureSocialUser("kakao:login-provider", "카카오유저");

    assertThat(saved.getLoginProvider()).isEqualTo(LoginProvider.KAKAO);
  }

  @Test
  void ensureSocialUserDoesNotReplaceAnExistingNicknameWithFallback() {
    userRepository.save(new User("kakao:existing", "기존닉네임", null));

    User saved = userService.ensureSocialUser("kakao:existing", null);

    assertThat(saved.getNickname()).isEqualTo("기존닉네임");
  }

  @Test
  void ensureSocialUserStoresProviderProfileImageForNewUser() {
    User saved =
        userService.ensureSocialUser(
            "kakao:profile-image", "카카오닉네임", "https://img.kakao.test/profile.png");

    assertThat(saved.getProfileImage()).isEqualTo("https://img.kakao.test/profile.png");
  }

  @Test
  void ensureSocialUserPreservesExistingProfileImage() {
    userRepository.save(
        new User("kakao:existing-image", "기존닉네임", "https://img.old.test/profile.png"));

    User saved =
        userService.ensureSocialUser(
            "kakao:existing-image", "새카카오닉네임", "https://img.new.test/profile.png");

    assertThat(saved.getNickname()).isEqualTo("기존닉네임");
    assertThat(saved.getProfileImage()).isEqualTo("https://img.old.test/profile.png");
  }

  @Test
  void getProfileThrowsNotFoundWhenUserMissing() {
    ApiException ex =
        catchThrowableOfType(
            () -> userService.getProfile("uid-profile-missing"), ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
  }

  @Test
  void updateProfileCreatesUserWhenMissing() {
    // createdAt이 서버 생성 타임스탬프라 전체 레코드 비교 대신 개별 필드로 확인한다.
    UserProfileResponse response =
        userService.updateProfile(
            "uid-profile-new",
            "표시이름",
            new UpdateProfileRequest("새닉네임", "https://img/1.png"),
            LoginProvider.EMAIL,
            null);

    assertThat(response.userId()).isEqualTo("uid-profile-new");
    assertThat(response.nickname()).isEqualTo("새닉네임");
    assertThat(response.profileImage()).isEqualTo("https://img/1.png");
    assertThat(response.createdAt()).isNotNull();
    // 신규 생성 시점에 넘긴 로그인 수단이 그대로 저장된다.
    assertThat(response.loginProvider()).isEqualTo(LoginProvider.EMAIL);
    // DB 라운드트립에서 createdAt 정밀도가 미세하게 바뀔 수 있어(나노초 vs DB 컬럼 정밀도) 따로 근접 비교한다.
    UserProfileResponse reloaded = userService.getProfile("uid-profile-new");
    assertThat(reloaded.createdAt()).isCloseTo(response.createdAt(), within(1, ChronoUnit.SECONDS));
    assertThat(reloaded).usingRecursiveComparison().ignoringFields("createdAt").isEqualTo(response);
  }

  @Test
  void updateProfileBackfillsEmailForExistingUserWithNullEmail() {
    userRepository.save(new User("uid-profile-email-backfill", "닉네임", null));

    UserProfileResponse response =
        userService.updateProfile(
            "uid-profile-email-backfill",
            "표시이름",
            new UpdateProfileRequest("닉네임", null),
            null,
            "profile-backfill@example.com");

    assertThat(response.email()).isEqualTo("profile-backfill@example.com");
  }

  @Test
  void updateProfileOverwritesExistingNicknameAndPhoto() {
    userRepository.save(new User("uid-profile-existing", "옛날닉네임", "https://img/old.png"));

    userService.updateProfile(
        "uid-profile-existing",
        "표시이름",
        new UpdateProfileRequest("새닉네임", "https://img/new.png"),
        LoginProvider.GOOGLE,
        null);

    UserProfileResponse response = userService.getProfile("uid-profile-existing");
    assertThat(response.nickname()).isEqualTo("새닉네임");
    assertThat(response.profileImage()).isEqualTo("https://img/new.png");
    // 이미 있던 유저라 로그인 수단은 재로그인으로 덮어쓰이지 않는다(생성 시 null 그대로).
    assertThat(response.loginProvider()).isNull();
  }

  @Test
  void createProfilePhotoUploadUrlReturnsServiceUnavailableWithoutObjectStorage() {
    ApiException ex =
        catchThrowableOfType(
            () -> userService.createProfilePhotoUploadUrl("uid-photo-no-storage"),
            ApiException.class);

    assertThat(ex.getStatus()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
  }
}
