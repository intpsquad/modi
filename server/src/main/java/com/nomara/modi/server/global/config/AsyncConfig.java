package com.nomara.modi.server.global.config;

import java.util.concurrent.Executor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

/**
 * S-25-D 외부 공유 등록의 크롤링+AI 태깅을 백그라운드로 돌리기 위한 이 프로젝트 최초의 비동기 인프라. 고정 크기 풀을 명시해 무제한 스레드 생성을 막는다(기본
 * {@code SimpleAsyncTaskExecutor}는 풀링을 안 해 요청마다 새 스레드를 만든다).
 */
@Configuration
@EnableAsync
public class AsyncConfig {

  @Bean(name = "archiveCrawlExecutor")
  public Executor archiveCrawlExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(2);
    executor.setMaxPoolSize(4);
    executor.setQueueCapacity(50);
    executor.setThreadNamePrefix("archive-crawl-");
    executor.initialize();
    return executor;
  }
}
