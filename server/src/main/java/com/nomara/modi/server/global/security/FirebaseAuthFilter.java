package com.nomara.modi.server.global.security;

import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import com.google.firebase.auth.FirebaseToken;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * {@code Authorization: Bearer <Firebase ID 토큰>}을 Firebase Admin SDK로 검증해 uid/email/name을 request
 * attribute로 노출한다. {@link com.nomara.modi.server.global.config.FirebaseConfig}의
 * FilterRegistrationBean이 이 필터를 등록하는 경로에만 적용된다(현재 "/me", "/me/*", "/rooms", "/rooms/*",
 * "/invite-codes/*").
 */
public class FirebaseAuthFilter extends OncePerRequestFilter {

  private static final Logger log = LoggerFactory.getLogger(FirebaseAuthFilter.class);

  public static final String ATTR_UID = "firebaseUid";
  public static final String ATTR_EMAIL = "firebaseEmail";
  public static final String ATTR_NAME = "firebaseName";
  public static final String ATTR_SIGN_IN_PROVIDER = "firebaseSignInProvider";

  @Override
  protected void doFilterInternal(
      HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
      throws ServletException, IOException {
    String header = request.getHeader("Authorization");
    if (header == null || !header.startsWith("Bearer ")) {
      response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Missing bearer token");
      return;
    }

    String idToken = header.substring("Bearer ".length());
    try {
      FirebaseToken decoded = FirebaseAuth.getInstance().verifyIdToken(idToken);
      request.setAttribute(ATTR_UID, decoded.getUid());
      request.setAttribute(ATTR_EMAIL, decoded.getEmail());
      request.setAttribute(ATTR_NAME, displayName(decoded));
      request.setAttribute(ATTR_SIGN_IN_PROVIDER, signInProvider(decoded));
    } catch (FirebaseAuthException | IllegalStateException e) {
      log.warn("Firebase ID 토큰 검증 실패: {}", e.getMessage());
      response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Invalid token");
      return;
    }

    filterChain.doFilter(request, response);
  }

  private String displayName(FirebaseToken decoded) {
    if (decoded.getName() != null && !decoded.getName().isBlank()) {
      return decoded.getName();
    }
    Object nickname = decoded.getClaims().get("nickname");
    return nickname instanceof String value && !value.isBlank() ? value : null;
  }

  /**
   * 마이 탭 로그인 수단 배지용 원본 클레임 — {@code "google.com"}/{@code "password"}(이메일)/{@code
   * "apple.com"}/{@code "custom"}(카카오, Firebase Custom Token) 중 하나. 도메인 enum({@code LoginProvider})
   * 매핑은 인증 필터가 아니라 호출부에서 한다.
   */
  private String signInProvider(FirebaseToken decoded) {
    Object firebaseClaim = decoded.getClaims().get("firebase");
    if (firebaseClaim instanceof Map<?, ?> claims) {
      Object provider = claims.get("sign_in_provider");
      if (provider instanceof String value) {
        return value;
      }
    }
    return null;
  }
}
