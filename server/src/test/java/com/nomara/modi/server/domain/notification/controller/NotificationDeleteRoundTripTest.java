package com.nomara.modi.server.domain.notification.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.nomara.modi.server.domain.notification.repository.NotificationRepository;
import com.nomara.modi.server.domain.notification.service.NotificationHistoryService;
import com.nomara.modi.server.domain.user.entity.User;
import com.nomara.modi.server.domain.user.repository.UserRepository;
import com.nomara.modi.server.global.notification.PushType;
import com.nomara.modi.server.global.security.FirebaseAuthFilter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

/**
 * 알림 내역 삭제(#111, specs/0017)의 HTTP 계약 — 성공 204, 남의 것·없는 것 404.
 *
 * <p>규칙 자체(본인 것만 지운다)는 {@code NotificationHistoryServiceTest}가 실제 Postgres 로 본다. 여기서는 필터가 심은 uid 가
 * 컨트롤러를 거쳐 서비스까지 가고, 예외가 맞는 상태 코드로 바뀌는지만 본다. 필터를 끄는 이유는 {@code FeedbackSubmitRoundTripTest} 와 같다(진짜
 * Firebase ID 토큰을 테스트에서 만들 수 없다). 필터가 {@code /me/notifications/*} 에 붙는지는 {@code
 * AuthFilterCoverageTest} 가 본다.
 */
@SpringBootTest
@AutoConfigureMockMvc(addFilters = false)
class NotificationDeleteRoundTripTest {

  @DynamicPropertySource
  static void properties(DynamicPropertyRegistry registry) {
    // 전용 H2 — 공용 이름을 쓰면 컨텍스트가 닫힐 때 다른 테스트의 테이블까지 지운다(FeedbackSubmitRoundTripTest 참고).
    registry.add("spring.datasource.url", () -> "jdbc:h2:mem:notification-delete;MODE=PostgreSQL");
    registry.add("spring.jpa.hibernate.ddl-auto", () -> "create-drop");
    registry.add("minio.endpoint", () -> "false");
    registry.add("firebase.credentials-path", () -> "false");
    registry.add("spring.mail.host", () -> "false");
  }

  @Autowired private MockMvc mockMvc;
  @Autowired private NotificationHistoryService notificationHistoryService;
  @Autowired private NotificationRepository notificationRepository;
  @Autowired private UserRepository userRepository;

  private User owner;
  private User other;

  @BeforeEach
  void setUp() {
    notificationRepository.deleteAll();
    owner = userRepository.save(new User("uid-noti-owner", "주인", null));
    other = userRepository.save(new User("uid-noti-other", "남", null));
  }

  private Long recordFor(User user, String title) {
    notificationHistoryService.record(user, PushType.POKE, null, title, "본문");
    return notificationHistoryService.list(user.getId()).getFirst().id();
  }

  @Test
  void deletingOwnNotificationReturnsNoContent() throws Exception {
    Long id = recordFor(owner, "내 알림");

    mockMvc
        .perform(
            delete("/me/notifications/{id}", id)
                .requestAttr(FirebaseAuthFilter.ATTR_UID, owner.getId()))
        .andExpect(status().isNoContent());

    assertThat(notificationRepository.existsById(id)).isFalse();
  }

  @Test
  void deletingSomeoneElsesNotificationIsNotFound() throws Exception {
    Long othersId = recordFor(other, "남의 알림");

    mockMvc
        .perform(
            delete("/me/notifications/{id}", othersId)
                .requestAttr(FirebaseAuthFilter.ATTR_UID, owner.getId()))
        .andExpect(status().isNotFound());

    assertThat(notificationRepository.existsById(othersId)).isTrue();
  }

  @Test
  void deletingAllReturnsNoContentAndLeavesOthersAlone() throws Exception {
    recordFor(owner, "1");
    recordFor(owner, "2");
    recordFor(other, "남의 알림");

    mockMvc
        .perform(
            delete("/me/notifications").requestAttr(FirebaseAuthFilter.ATTR_UID, owner.getId()))
        .andExpect(status().isNoContent());

    assertThat(notificationHistoryService.list(owner.getId())).isEmpty();
    assertThat(notificationHistoryService.list(other.getId())).hasSize(1);
  }
}
