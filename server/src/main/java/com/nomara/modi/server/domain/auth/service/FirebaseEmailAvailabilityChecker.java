package com.nomara.modi.server.domain.auth.service;

import com.google.firebase.FirebaseApp;
import com.google.firebase.auth.AuthErrorCode;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseAuthException;
import com.nomara.modi.server.global.exception.BadGatewayException;
import com.nomara.modi.server.global.exception.ServiceUnavailableException;
import java.util.Optional;
import org.springframework.stereotype.Service;

@Service
public class FirebaseEmailAvailabilityChecker implements EmailAvailabilityChecker {

  private final Optional<FirebaseApp> firebaseApp;

  public FirebaseEmailAvailabilityChecker(Optional<FirebaseApp> firebaseApp) {
    this.firebaseApp = firebaseApp;
  }

  @Override
  public boolean isRegistered(String email) {
    FirebaseApp app =
        firebaseApp.orElseThrow(() -> new ServiceUnavailableException("이메일 인증이 지금은 지원되지 않아요"));
    try {
      FirebaseAuth.getInstance(app).getUserByEmail(email);
      return true;
    } catch (FirebaseAuthException e) {
      if (e.getAuthErrorCode() == AuthErrorCode.USER_NOT_FOUND) {
        return false;
      }
      throw new BadGatewayException("이메일 확인에 실패했어요", e);
    }
  }
}
