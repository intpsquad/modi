package com.nomara.modi.server.domain.auth.service;

import com.google.firebase.FirebaseApp;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import com.nomara.modi.server.global.exception.ServiceUnavailableException;
import java.util.Map;
import java.util.Optional;
import org.springframework.stereotype.Service;

/** Kakao 계정을 Firebase UID와 custom claims로 연결한다. */
@Service
public class FirebaseCustomTokenIssuer implements FirebaseTokenIssuer {

  private final Optional<FirebaseApp> firebaseApp;

  public FirebaseCustomTokenIssuer(Optional<FirebaseApp> firebaseApp) {
    this.firebaseApp = firebaseApp;
  }

  @Override
  public String issue(String uid, String nickname) {
    FirebaseApp app =
        firebaseApp.orElseThrow(
            () -> new ServiceUnavailableException("Firebase 인증 설정이 없어 로그인할 수 없습니다."));
    try {
      return FirebaseAuth.getInstance(app).createCustomToken(uid, Map.of("nickname", nickname));
    } catch (FirebaseAuthException e) {
      throw new ServiceUnavailableException("Firebase 인증 세션을 만들지 못했습니다.", e);
    }
  }
}
