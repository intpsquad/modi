package com.nomara.modi.server.domain.feedback.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.nomara.modi.server.domain.feedback.entity.Feedback;
import com.nomara.modi.server.domain.feedback.entity.FeedbackType;
import com.nomara.modi.server.domain.feedback.repository.FeedbackRepository;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

/**
 * 인증을 통과한 문의가 <b>끝까지 저장되고 201을 돌려주는지</b> 확인한다(#99, #97).
 *
 * <p><b>왜 따로 필요했나.</b> 두 조각은 이미 각각 덮여 있었다 — {@code FeedbackControllerTest}가 "필터가 {@code /feedback}에
 * 붙는다"를, {@code FeedbackServiceTest}가 "uid를 주면 저장된다"를 본다. 덮이지 않은 건 <b>그 사이 이음매</b>였다: 필터가 심은 {@code
 * ATTR_UID}를 컨트롤러가 꺼내 서비스로 넘기는 구간. #99의 버그가 정확히 그 자리에서 터졌다(필터가 안 돌아 attribute가 비었고, 컨트롤러는 그 {@code
 * null}을 그대로 넘겼다).
 *
 * <p><b>{@code addFilters = false}인 이유</b>: 진짜 Firebase ID 토큰은 테스트에서 만들 수 없다({@code
 * AuthControllerTest} Javadoc 참고). 그래서 필터를 끄고, 필터가 성공했을 때 남기는 결과물({@code ATTR_UID})을 직접 심어 그 이후 구간만
 * 태운다. 필터가 실제로 붙는지는 {@code FeedbackControllerTest}가 따로 본다 — 둘을 합치면 사슬이 이어진다.
 *
 * <p>덤으로 <b>서버가 정말 201을 준다</b>는 것도 실행으로 확인된다. 앱이 201을 기대하도록 고친 근거(#97)가 문서가 아니라 테스트가 된다.
 */
@SpringBootTest
@AutoConfigureMockMvc(addFilters = false)
class FeedbackSubmitRoundTripTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    // 🔴 전용 H2 를 쓴다. 다른 테스트와 이름(`mem:server-test`)을 공유하면, 컨텍스트 캐시가
    // 넘쳐 이 컨텍스트가 닫힐 때 create-drop 이 **공용 DB 의 테이블을 통째로 지운다** —
    // 그러면 뒤따르는 테스트가 "Table USERS not found" 로 무더기로 깨진다(실제로 겪었다).
    registry.add("spring.datasource.url", () -> "jdbc:h2:mem:feedback-roundtrip;MODE=PostgreSQL");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    // "false"는 @ConditionalOnProperty를 끄는 관용구다(AuthControllerTest와 같다).
    registry.add("minio.endpoint", () -> "false");
    registry.add("firebase.credentials-path", () -> "false");
    registry.add("spring.mail.host", () -> "false");
  }

  @Autowired private MockMvc mockMvc;
  @Autowired private FeedbackRepository feedbackRepository;
  @Autowired private UserRepository userRepository;

  @Test
  void authenticatedSubmitReturnsCreatedAndStoresTheFeedback() throws Exception {
    userRepository.save(new User("uid-예원", "예원", null));

    mockMvc
        .perform(
            multipart("/feedback")
                .param("type", "QUESTION")
                .param("content", "콕찌르기가 안 돼요")
                .param("replyEmail", "me@example.com")
                .param("appVersion", "1.1.0(9)")
                .param("deviceInfo", "ios 18.2")
                // 필터가 성공했을 때 남기는 것 — 이게 컨트롤러까지 흘러야 한다.
                .requestAttr(FirebaseAuthFilter.ATTR_UID, "uid-예원"))
        // 🔴 200이 아니라 201이다. 앱이 200만 성공으로 보던 것이 #97이었다.
        .andExpect(status().isCreated());

    assertThat(feedbackRepository.count()).as("문의가 저장돼야 한다 — 운영에서는 이 값이 0이었다(#99)").isEqualTo(1);

    Feedback saved = feedbackRepository.findAll().getFirst();
    assertThat(saved.getType()).isEqualTo(FeedbackType.QUESTION);
    assertThat(saved.getContent()).isEqualTo("콕찌르기가 안 돼요");
    assertThat(saved.getReplyEmail()).isEqualTo("me@example.com");
    assertThat(saved.getUser().getId())
        .as("필터가 심은 uid가 서비스까지 닿아야 한다 — 끊기면 null이 되어 500이 났다")
        .isEqualTo("uid-예원");
  }
}
