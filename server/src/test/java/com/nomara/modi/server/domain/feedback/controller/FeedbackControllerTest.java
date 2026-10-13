package com.nomara.modi.server.domain.feedback.controller;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;

/**
 * {@code POST /feedback}이 {@code FirebaseAuthFilter} 안에 있는지 확인한다(#99).
 *
 * <p>이 테스트가 없던 동안 {@code /feedback}은 필터 등록 목록에서 빠져 있었고, 그래서 {@code uid}가 {@code null}인 채로 컨트롤러에 들어가
 * {@code userRepository.findById(null)}이 터졌다 — 운영에서 모든 문의가 <b>500</b>이었다(저장 0건). 즉 <b>인증 구멍이 500으로
 * 가려져 있던</b> 상태다.
 *
 * <p><b>왜 401만 보는가</b>: 토큰이 있는 성공 경로는 실제 Firebase 없이 재현할 수 없다({@code AuthControllerTest} Javadoc과
 * {@code RoomServiceTest}가 같은 이유를 적어 뒀다). 다행히 이 버그를 잡는 데는 미인증 경로만으로 충분하다 — 필터가 붙어 있으면 401, 안 붙어 있으면
 * 컨트롤러까지 가서 500이므로 둘이 또렷이 갈린다.
 *
 * <p>{@code firebase.credentials-path}가 없어도 {@code firebaseAuthFilterRegistration} 빈에는
 * {@code @ConditionalOnProperty}가 없어 <b>필터는 항상 등록된다</b>. 그래서 크리덴셜 없는 테스트 컨텍스트에서도 이 경로를 태울 수 있다.
 */
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
class FeedbackControllerTest {

  @Autowired private TestRestTemplate restTemplate;

  @Test
  void submitWithoutBearerTokenIsRejectedByFirebaseAuthFilter() {
    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.MULTIPART_FORM_DATA);
    MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
    // 유효한 값이어야 한다 — 바인딩에서 400으로 걸리면 필터 유무와 무관한 실패가 되어 이 테스트가 무의미해진다.
    form.add("type", "QUESTION");
    form.add("content", "인증 없이 보낸 문의");

    ResponseEntity<String> response =
        restTemplate.postForEntity("/feedback", new HttpEntity<>(form, headers), String.class);

    // 🔴 500이 나오면 필터가 안 붙은 것이다 — uid가 null로 서비스까지 흘러갔다는 뜻.
    assertThat(response.getStatusCode())
        .as("토큰 없는 문의는 필터에서 401로 끊겨야 한다 — 500이면 필터 밖이라는 신호다")
        .isEqualTo(HttpStatus.UNAUTHORIZED);
  }
}
