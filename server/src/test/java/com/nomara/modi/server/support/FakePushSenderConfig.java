package com.nomara.modi.server.support;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

/** {@link RecordingPushSender}를 {@code @Primary} 빈으로 등록한다. 테스트 클래스에서 {@code @Import}해서 쓴다. */
@TestConfiguration
public class FakePushSenderConfig {

  @Bean
  @Primary
  public RecordingPushSender recordingPushSender() {
    return new RecordingPushSender();
  }
}
