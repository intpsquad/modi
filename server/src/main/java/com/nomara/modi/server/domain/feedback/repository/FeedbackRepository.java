package com.nomara.modi.server.domain.feedback.repository;

import com.nomara.modi.server.domain.feedback.entity.Feedback;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface FeedbackRepository extends JpaRepository<Feedback, Long> {

  /**
   * 탈퇴 처리에서 개인정보({@code reply_email})만 지우기 위해 그 사람의 제보를 모은다. FK {@code SET NULL}은 {@code user_id}만
   * 비우므로 이 컬럼은 코드가 직접 지워야 한다(V30 마이그레이션 근거).
   */
  List<Feedback> findAllByUserId(String userId);
}
