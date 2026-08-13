package com.nomara.modi.server.global.config;

import com.nomara.modi.server.domain.todo.client.HttpTodoSuggestionClient;
import com.nomara.modi.server.domain.todo.client.TodoSuggestionClient;
import java.time.Duration;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * AI 서버(FastAPI) 호출 클라이언트 구성.
 *
 * <p>{@code OpenAiConfig}와 달리 {@code @ConditionalOnProperty}로 감싸지 않는다 — base-url에 로컬 기본값이 있어 항상 만들
 * 수 있고, 서버가 떠 있지 않은 상황은 호출 시점의 502로 다루는 편이 원인이 분명하기 때문이다(빈이 없으면 404처럼 보인다).
 */
@Configuration
public class AiServerConfig {

  @Bean
  public TodoSuggestionClient todoSuggestionClient(
      @Value("${modi.ai-server.base-url}") String baseUrl,
      @Value("${modi.ai-server.internal-key:}") String internalKey,
      @Value("${modi.ai-server.read-timeout-seconds:60}") long readTimeoutSeconds) {
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(Duration.ofSeconds(5));
    // 실측 7~9초(자료 2건, ai/docs/EXPERIMENTS.md #10)지만 아카이브가 늘면 길어진다. 잠정값이며
    // "추천 응답 동기 유지 여부"(ai/docs/DECISIONS.md 미확정)가 정해지면 함께 재검토한다.
    requestFactory.setReadTimeout(Duration.ofSeconds(readTimeoutSeconds));

    RestClient restClient =
        RestClient.builder().baseUrl(baseUrl).requestFactory(requestFactory).build();
    return new HttpTodoSuggestionClient(restClient, internalKey);
  }
}
