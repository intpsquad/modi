package com.nomara.modi.server.global.config;

import com.nomara.modi.server.domain.archive.client.AiEmbeddingClient;
import com.nomara.modi.server.domain.archive.client.AiSummaryClient;
import com.nomara.modi.server.domain.archive.client.AiTaggingClient;
import com.nomara.modi.server.domain.archive.client.OpenAiEmbeddingClient;
import com.nomara.modi.server.domain.archive.client.OpenAiSummaryClient;
import com.nomara.modi.server.domain.archive.client.OpenAiTaggingClient;
import java.time.Duration;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.document.MetadataMode;
import org.springframework.ai.openai.OpenAiChatModel;
import org.springframework.ai.openai.OpenAiChatOptions;
import org.springframework.ai.openai.OpenAiEmbeddingModel;
import org.springframework.ai.openai.OpenAiEmbeddingOptions;
import org.springframework.ai.openai.api.OpenAiApi;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * spring.ai.openai.api-key 프로퍼티가 <b>존재할 때</b> AI 클라이언트들을 만든다. FirebaseConfig와 동일한 패턴이고,
 * ArchiveItemService는 빈이 없으면 태그·요약 없이 등록을 계속 진행한다(specs/OPEN.md 2026-07-27 확정).
 *
 * <p><b>⚠️ "키가 비어 있으면 빈이 안 생긴다"가 아니다</b>(2026-07-30 리뷰 정정). {@code @ConditionalOnProperty}는 값이
 * {@code "false"}가 아니기만 하면 매칭하므로, {@code application.yml}이 {@code api-key: ${OPENAI_API_KEY:}}로
 * 프로퍼티를 <b>항상 선언</b>하는 한 키가 빈 문자열이어도 빈은 생성되고 호출은 인증 실패로 떨어진다(폴백으로 흡수된다). 빈이 실제로 안 생기는 곳은 프로퍼티 선언
 * 자체를 뺀 {@code src/test/resources/application.yml}뿐이다 — 그 파일의 주석이 "프로퍼티 자체를 없애야 빈이 확실히 생성되지 않는다"라고
 * 적어둔 것이 바로 이 사실이다. 운영에서 게이트를 실제로 닫으려면 프로퍼티를 조건부로 선언해야 하고, 그건 태깅까지 영향이 가는 별도 작업이다({@code
 * specs/OPEN.md}).
 *
 * <p>Spring AI의 OpenAI 자동설정(OpenAiChatAutoConfiguration 등)은 application.yml에서 전부 꺼뒀다 — 키가 비어 있으면 그
 * 자동설정 빈들이 생성 시점에 곧바로 예외를 던져 컨텍스트 자체가 안 뜨기 때문(실측 확인). 대신 여기서 OpenAiApi/ChatClient를 직접 만들어 조건부로 감싼다.
 *
 * <p><b>태깅과 요약은 프로퍼티가 둘이지만 값은 같다</b>({@code gpt-5.4-nano}, 2026-08-13 통일) — 태깅은 {@code
 * spring.ai.openai.chat.options.model}, 요약은 {@code modi.archive.summary-model}. 원래 태깅만 {@code
 * gpt-5-nano}였고 그 유일한 근거는 옛 LLM 게이트웨이의 크레딧 등급이었는데, 게이트웨이 키 회수로 제공사가 OpenAI 직접으로 바뀌면서 그 축이
 * 사라졌다({@code ai/docs/EXPERIMENTS.md} #34). 방향이 {@code gpt-5-nano}가 아니라 {@code gpt-5.4-nano}인 근거는
 * #14·#34의 실측이다: {@code gpt-5-nano}는 150자 요약에 숨은 추론 토큰 3,500개를 태우고 20초 넘게 걸리며, 그 추론 토큰은 OpenAI 직접
 * 과금에서 <b>출력 토큰 요금</b>으로 그대로 청구된다.
 *
 * <p><b>⚠️ 키 환경변수({@code OPENAI_API_KEY})의 이름을 바꿀 때는 운영 {@code .env}를 같은 배포에서 함께 바꿔야 한다</b> — 어긋나면
 * 값이 안 들어와도 부팅은 성공하고 AI 기능만 조용히 꺼진다(위 {@code @ConditionalOnProperty} 설명이 그 이유다). 로그에 아무 흔적이 남지 않으므로
 * 발견이 늦는다. 2026-08-13에 옛 게이트웨이 이름을 딴 변수명에서 이 이름으로 개명할 때 실제로 그렇게 했다.
 *
 * <p><b>임베딩도 여기서 만든다</b> — 같은 게이트웨이·같은 타임아웃 규칙을 쓰고 경로와 모델만 다르다({@code text-embedding-3-small}).
 *
 * <p>{@code ChatClient}를 빈으로 노출하지 않는 이유는 모델 프로퍼티가 둘이라 타입만으로는 구분되지 않기 때문이다 — 지금은 두 값이 같지만 한 기능만 모델을
 * 바꿔 재보는 일이 다시 생기므로 합치지 않는다. 주입 지점에서 어느 쪽인지 헷갈리는 대신 여기서 각각 만들어 넣는다.
 */
@Configuration
public class OpenAiConfig {

  @Bean
  @ConditionalOnProperty(name = "spring.ai.openai.api-key")
  public AiTaggingClient aiTaggingClient(
      @Value("${spring.ai.openai.api-key}") String apiKey,
      @Value("${spring.ai.openai.base-url}") String baseUrl,
      @Value("${spring.ai.openai.chat.completions-path}") String completionsPath,
      @Value("${spring.ai.openai.chat.options.model}") String model,
      @Value("${modi.archive.ai-read-timeout-seconds:60}") long readTimeoutSeconds) {
    return new OpenAiTaggingClient(
        chatClient(apiKey, baseUrl, completionsPath, model, readTimeoutSeconds));
  }

  @Bean
  @ConditionalOnProperty(name = "spring.ai.openai.api-key")
  public AiSummaryClient aiSummaryClient(
      @Value("${spring.ai.openai.api-key}") String apiKey,
      @Value("${spring.ai.openai.base-url}") String baseUrl,
      @Value("${spring.ai.openai.chat.completions-path}") String completionsPath,
      @Value("${modi.archive.summary-model}") String summaryModel,
      @Value("${modi.archive.ai-read-timeout-seconds:60}") long readTimeoutSeconds) {
    return new OpenAiSummaryClient(
        chatClient(apiKey, baseUrl, completionsPath, summaryModel, readTimeoutSeconds));
  }

  /**
   * 자료 임베딩. 태깅·요약과 <b>같은 게이트웨이·같은 타임아웃</b>을 쓰되 부르는 경로만 다르다({@code /v1/embeddings}).
   *
   * <p>게이트웨이가 이 경로를 받아 준다는 것은 실제 호출로 확인했다(2026-08-01: HTTP 200, {@code text-embedding-3-small},
   * 1536차원, {@code ai/docs/EXPERIMENTS.md} #19). 실제 코드 경로로는 건당 약 1.4초다(백필 12건 평균).
   *
   * <p>{@code dimensions}를 지정하지 않는다 — 모델 기본값(1536)을 그대로 받는다. 축소는 정확도를 깎는 최적화인데 아직 저장 용량이 문제가 된 적이
   * 없다(자료 1건 = 6KB).
   */
  @Bean
  @ConditionalOnProperty(name = "spring.ai.openai.api-key")
  public AiEmbeddingClient aiEmbeddingClient(
      @Value("${spring.ai.openai.api-key}") String apiKey,
      @Value("${spring.ai.openai.base-url}") String baseUrl,
      // 기본값을 주는 이유: 이 프로퍼티가 빠진 채 키만 있으면 부팅이 깨진다. completions-path 는
      // 기본값 없이 두었지만(선례) 위험이 "운영 부팅 실패"라 여기서는 싼 쪽을 택했다.
      @Value("${spring.ai.openai.embedding.embeddings-path:embeddings}") String embeddingsPath,
      @Value("${modi.archive.embedding-model}") String embeddingModel,
      @Value("${modi.archive.ai-read-timeout-seconds:60}") long readTimeoutSeconds) {
    OpenAiApi openAiApi =
        openAiApi(apiKey, baseUrl, readTimeoutSeconds).embeddingsPath(embeddingsPath).build();
    return new OpenAiEmbeddingClient(
        new OpenAiEmbeddingModel(
            openAiApi,
            MetadataMode.EMBED,
            OpenAiEmbeddingOptions.builder().model(embeddingModel).build()));
  }

  private static ChatClient chatClient(
      String apiKey,
      String baseUrl,
      String completionsPath,
      String model,
      long readTimeoutSeconds) {
    OpenAiApi openAiApi =
        openAiApi(apiKey, baseUrl, readTimeoutSeconds).completionsPath(completionsPath).build();
    OpenAiChatModel chatModel =
        OpenAiChatModel.builder()
            .openAiApi(openAiApi)
            .defaultOptions(OpenAiChatOptions.builder().model(model).build())
            .build();
    return ChatClient.create(chatModel);
  }

  /**
   * LLM 호출에 <b>타임아웃을 명시한다.</b> 주지 않으면 Spring AI 기본 {@code RestClient.builder()}가 쓰이고, Java 21에서 그
   * 기본 요청 팩토리는 connect/read 타임아웃이 <b>없다</b> — 게이트웨이가 응답 없이 멈추면 톰캣 스레드가 영구 점유된다.
   *
   * <p>{@code AiServerConfig}가 FastAPI 호출에 connect 5s / read 60s를 명시하는 것과 같은 기준을 따른다("외부 호출엔 타임아웃을
   * 건다"). 값도 그쪽과 맞췄다 — 요약은 실측 1.3~2.8초(픽스처 3건, {@code ai/docs/EXPERIMENTS.md} #14)지만 실사용 본문은 자료당 약
   * 6.8k tok(#11)이라 여유를 둔다. 타임아웃이 걸리면 예외가 되어 호출부의 폴백(태그·요약·임베딩 없이 등록 진행)을 그대로 탄다.
   *
   * <p><b>경로를 붙이지 않은 빌더를 돌려준다</b> — 채팅은 {@code completionsPath}, 임베딩은 {@code embeddingsPath}로 갈리기
   * 때문이다. 타임아웃 규칙 자체는 둘이 공유해야 하므로 여기 한 곳에만 둔다.
   */
  private static OpenAiApi.Builder openAiApi(
      String apiKey, String baseUrl, long readTimeoutSeconds) {
    SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(Duration.ofSeconds(5));
    requestFactory.setReadTimeout(Duration.ofSeconds(readTimeoutSeconds));

    return OpenAiApi.builder()
        .apiKey(apiKey)
        .baseUrl(baseUrl)
        .restClientBuilder(RestClient.builder().requestFactory(requestFactory));
  }
}
