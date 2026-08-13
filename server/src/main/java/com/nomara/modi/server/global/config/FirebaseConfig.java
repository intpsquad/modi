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
    registration.addUrlPatterns("/me", "/me/*", "/rooms", "/rooms/*", "/invite-codes/*");
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
