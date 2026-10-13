package com.nomara.modi.server.global.config;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import com.nomara.modi.server.global.notification.FirebaseCloudMessagingPushSender;
import com.nomara.modi.server.global.notification.PushSender;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import java.io.FileInputStream;
import java.io.IOException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * firebase.credentials-path(= FIREBASE_CREDENTIALS_PATH 환경변수, Spring 완화 바인딩)가 설정된 경우에만 FirebaseApp을
 * 초기화한다. 크리덴셜이 없는 테스트/CI 컨텍스트에서는 이 빈이 생성되지 않아 부팅이 깨지지 않는다.
 */
@Configuration
public class FirebaseConfig {

  @Bean
  @ConditionalOnProperty(name = "firebase.credentials-path")
  public FirebaseApp firebaseApp(@Value("${firebase.credentials-path}") String credentialsPath)
      throws IOException {
    if (!FirebaseApp.getApps().isEmpty()) {
      return FirebaseApp.getInstance();
    }
    try (FileInputStream serviceAccount = new FileInputStream(credentialsPath)) {
      FirebaseOptions options =
          FirebaseOptions.builder()
              .setCredentials(GoogleCredentials.fromStream(serviceAccount))
              .build();
      return FirebaseApp.initializeApp(options);
    }
  }

  @Bean
  public FilterRegistrationBean<FirebaseAuthFilter> firebaseAuthFilterRegistration() {
    FilterRegistrationBean<FirebaseAuthFilter> registration =
        new FilterRegistrationBean<>(new FirebaseAuthFilter());
    // 🔴 보호가 필요한 경로는 **여기가 단일 진실**이다. 빠뜨리면 그 경로는 조용히 인증 없이 열린다 —
    // #99 에서 "/feedback" 이 빠져 운영 문의가 전부 500 이었고(uid 가 null 로 서비스까지 흘렀다),
    // 그 500 이 인증 구멍을 가리고 있었다. 누락은 AuthFilterCoverageTest 가 잡는다.
    registration.addUrlPatterns(
        "/me", "/me/*", "/rooms", "/rooms/*", "/invite-codes/*", "/feedback");
    registration.setName("firebaseAuthFilter");
    return registration;
  }

  /** {@link #firebaseApp}과 동일 조건 — 크리덴셜 없는 테스트/CI에서는 이 빈도 생성되지 않는다. */
  @Bean
  @ConditionalOnProperty(name = "firebase.credentials-path")
  public PushSender pushSender(FirebaseApp firebaseApp) {
    return new FirebaseCloudMessagingPushSender(FirebaseMessaging.getInstance(firebaseApp));
  }
}
