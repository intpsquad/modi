package com.nomara.modi.server.domain.auth.service;

public interface FirebaseTokenIssuer {

  String issue(String uid, String nickname);
}
