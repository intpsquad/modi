package com.nomara.modi.server.domain.auth.service;

/**
 * 이메일이 이미 Firebase 계정으로 가입돼 있는지 확인하는 경계. {@code FirebaseTokenIssuer}와 같은 이유로 인터페이스로 둔다 — 테스트에서 실제
 * Firebase Admin SDK를 부르지 않고 가짜를 끼울 수 있다.
 */
public interface EmailAvailabilityChecker {

  boolean isRegistered(String email);
}
