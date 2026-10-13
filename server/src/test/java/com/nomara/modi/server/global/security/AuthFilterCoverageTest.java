package com.nomara.modi.server.global.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.http.ResponseEntity;

/**
 * <b>모든 API 경로는 인증 필터에 덮이거나, 공개가 의도라고 명시돼 있어야 한다.</b>
 *
 * <p>왜 이 테스트가 생겼나(#99): {@code /feedback}이 {@code FirebaseAuthFilter} 등록 목록에서 빠진 채 배포됐다. 토큰 검증 없이
 * 누구나 부를 수 있었고, 운영 문의는 전부 500이었다(uid가 null로 서비스까지 흘렀다). 한 달 동안 아무도 몰랐다 — <b>"이 경로는 보호돼야 한다"를 확인하는
 * 검사가 한 줄도 없었기 때문이다.</b> 있던 것은 정반대 검사뿐이었다({@code
 * AuthControllerTest.sendEmailCodeWithoutBearerTokenIsNotBlockedByFirebaseAuthFilter} — {@code
 * /auth/email/code}가 필터 <i>밖</i>임을 못박는다). 이 테스트가 그 거울상이다.
 *
 * <p>설계상 중요한 두 가지:
 *
 * <ul>
 *   <li><b>경로 목록을 베껴 적지 않는다.</b> 등록된 패턴은 {@link FilterRegistrationBean#getUrlPatterns()}에서 실제 값으로
 *       읽는다. 목록이 두 군데가 된 것이 애초의 병이었다.
 *   <li><b>커밋된 {@code docs/api/openapi.json}이 아니라 {@code /v3/api-docs}를 라이브로 읽는다</b>({@code
 *       OpenApiExportTest}와 같은 방식). 파일이 낡아도 이 검사는 지금 컨트롤러를 본다.
 * </ul>
 *
 * <p>{@code /actuator/*}와 springdoc 자체 경로는 OpenAPI {@code paths}에 안 나오므로 이 검사 대상이 아니다. 외부 노출은
 * {@code deploy/Caddyfile}이 막는다.
 */
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class AuthFilterCoverageTest {

  /**
   * 로그인 <b>전</b>에 부르므로 인증을 걸 수 없는 경로들 — 공개가 의도다.
   *
   * <p>🔴 여기에 경로를 추가한다는 것은 "이 엔드포인트는 토큰 없이 누구나 부를 수 있어도 된다"는 선언이다. 반드시 이유를 주석으로 남길 것.
   */
  private static final Set<String> INTENTIONALLY_PUBLIC =
      Set.of(
          "/auth/email/code", // 가입·로그인 전 이메일 인증코드 발송 — 이 시점엔 토큰이 없다
          "/auth/email/code/verify", // 같은 흐름의 검증
          "/auth/kakao"); // 카카오 액세스 토큰 → Firebase 커스텀 토큰 교환(로그인 성립 이전)

  @Autowired private TestRestTemplate restTemplate;

  @Autowired private FilterRegistrationBean<FirebaseAuthFilter> firebaseAuthFilterRegistration;

  @Test
  void everyApiPathIsAuthenticatedUnlessExplicitlyPublic() throws Exception {
    Collection<String> patterns = firebaseAuthFilterRegistration.getUrlPatterns();
    assertThat(patterns).as("필터 등록 패턴을 읽지 못했다 — 테스트가 아무것도 검사하지 못한다").isNotEmpty();

    List<String> unprotected =
        apiPaths().stream()
            .filter(path -> !isCoveredBy(patterns, path))
            .filter(path -> !INTENTIONALLY_PUBLIC.contains(path))
            .sorted()
            .toList();

    assertThat(unprotected)
        .as(
            """
            아래 경로가 인증 필터 밖이다 — 토큰 없이 누구나 부를 수 있다.
            둘 중 하나를 하라:
              (1) 보호가 필요하면 FirebaseConfig#firebaseAuthFilterRegistration 의 addUrlPatterns 에 추가한다
              (2) 공개가 의도면 이 테스트의 INTENTIONALLY_PUBLIC 에 **이유와 함께** 넣는다
            조용히 (2)로 넘기지 말 것 — #99 가 그렇게 한 달을 갔다.
            """)
        .isEmpty();
  }

  @Test
  void feedbackIsProtected() {
    // #99 의 회귀 가드. 위 검사가 일반론이라면 이건 그 버그 자체를 콕 집는다 —
    // INTENTIONALLY_PUBLIC 에 /feedback 을 넣어 위 검사를 '통과'시키는 우회를 막는다.
    assertThat(isCoveredBy(firebaseAuthFilterRegistration.getUrlPatterns(), "/feedback"))
        .as("POST /feedback 은 로그인한 사용자만 쓴다 — 필터 밖으로 내보내지 말 것(#99)")
        .isTrue();
    assertThat(INTENTIONALLY_PUBLIC).doesNotContain("/feedback");
  }

  /** 현재 떠 있는 서버가 스스로 보고하는 API 경로들 — 커밋된 문서가 아니라 실제 컨트롤러가 기준이다. */
  private List<String> apiPaths() throws Exception {
    ResponseEntity<String> response = restTemplate.getForEntity("/v3/api-docs", String.class);
    assertThat(response.getStatusCode().is2xxSuccessful()).isTrue();
    JsonNode paths = new ObjectMapper().readTree(response.getBody()).get("paths");
    assertThat(paths).as("OpenAPI 문서에 paths 가 없다").isNotNull();

    List<String> result = new ArrayList<>();
    paths.fieldNames().forEachRemaining(result::add);
    assertThat(result).as("API 경로가 하나도 안 잡혔다 — 검사가 공회전한다").isNotEmpty();
    return result;
  }

  /**
   * 서블릿 URL 패턴 매칭 — 완전일치이거나, {@code /x/*}가 {@code /x/}로 시작하는 경로를 덮는다.
   *
   * <p>OpenAPI 경로의 {@code {roomId}} 같은 템플릿은 그대로 두고 비교해도 된다. 접두사만 보기 때문이다 — {@code
   * /rooms/{roomId}/todos}는 {@code /rooms/*}에 덮인다.
   */
  private static boolean isCoveredBy(Collection<String> patterns, String path) {
    for (String pattern : patterns) {
      if (pattern.equals(path)) {
        return true;
      }
      if (pattern.endsWith("/*") && path.startsWith(pattern.substring(0, pattern.length() - 1))) {
        return true;
      }
    }
    return false;
  }
}
