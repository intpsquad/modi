package com.nomara.modi.server.domain.user.controller;

import com.nomara.modi.server.domain.user.dto.MeResponse;
import com.nomara.modi.server.domain.user.dto.ProfilePhotoUploadUrlResponse;
import com.nomara.modi.server.domain.user.dto.RegisterFcmTokenRequest;
import com.nomara.modi.server.domain.user.dto.UpdateProfileRequest;
import com.nomara.modi.server.domain.user.dto.UserProfileResponse;
import com.nomara.modi.server.domain.user.entity.LoginProvider;
import com.nomara.modi.server.domain.user.service.UserService;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** 인증 왕복 검증용 스파이크 엔드포인트. {@link FirebaseAuthFilter}가 검증한 uid를 그대로 반환한다. */
@RestController
public class MeController {

  private final UserService userService;

  public MeController(UserService userService) {
    this.userService = userService;
  }

  @GetMapping("/me")
  public MeResponse me(HttpServletRequest request) {
    return new MeResponse(
        (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID),
        (String) request.getAttribute(FirebaseAuthFilter.ATTR_EMAIL),
        (String) request.getAttribute(FirebaseAuthFilter.ATTR_NAME));
  }

  /** specs/0011-멤버-투두-콕찌르기.md 콕찌르기 푸시 발송에 쓰인다. */
  @PutMapping("/me/fcm-token")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void registerFcmToken(
      HttpServletRequest request, @Valid @RequestBody RegisterFcmTokenRequest body) {
    userService.registerFcmToken(
        uid(request), displayName(request), body.token(), loginProvider(request), email(request));
  }

  /** specs/0012-설정.md 프로필 수정 화면 프리필. */
  @GetMapping("/me/profile")
  public UserProfileResponse getProfile(HttpServletRequest request) {
    return userService.getProfile(uid(request));
  }

  @PatchMapping("/me/profile")
  public UserProfileResponse updateProfile(
      HttpServletRequest request, @Valid @RequestBody UpdateProfileRequest body) {
    return userService.updateProfile(
        uid(request), displayName(request), body, loginProvider(request), email(request));
  }

  /** MinIO presigned PUT 업로드 URL 발급 — 실제 파일 바이트는 서버를 거치지 않는다. */
  @PostMapping("/me/profile/photo/upload-url")
  public ProfilePhotoUploadUrlResponse createProfilePhotoUploadUrl(HttpServletRequest request) {
    return userService.createProfilePhotoUploadUrl(uid(request));
  }

  /** specs/0012-설정.md S-40 회원 탈퇴 — 확인 모달을 거친 뒤에만 호출되는 파괴적 엔드포인트. */
  @DeleteMapping("/me")
  @ResponseStatus(HttpStatus.NO_CONTENT)
  public void withdraw(HttpServletRequest request) {
    userService.withdraw(uid(request));
  }

  private String uid(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_UID);
  }

  /** V29 — UserService가 신규/기존 유저 양쪽에 email을 채우는 유일한 소스(Google/Apple/이메일 자체가입 공통). */
  private String email(HttpServletRequest request) {
    return (String) request.getAttribute(FirebaseAuthFilter.ATTR_EMAIL);
  }

  private String displayName(HttpServletRequest request) {
    String name = (String) request.getAttribute(FirebaseAuthFilter.ATTR_NAME);
    if (name != null) {
      return name;
    }
    String email = (String) request.getAttribute(FirebaseAuthFilter.ATTR_EMAIL);
    if (email != null) {
      return email;
    }
    return uid(request);
  }

  /** — 신규 유저 최초 생성 시에만 쓰인다(기존 유저면 무시됨, {@code UserService#ensureUser} 참고). */
  private LoginProvider loginProvider(HttpServletRequest request) {
    return LoginProvider.fromFirebaseSignInProvider(
        (String) request.getAttribute(FirebaseAuthFilter.ATTR_SIGN_IN_PROVIDER));
  }
}
