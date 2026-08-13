package com.nomara.modi.server.global.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 배포 헬스체크가 가리키는 <b>health 그룹</b>이 실제로 정의돼 있는지 묶는다.
 *
 * <p>🔴 <b>왜 파일을 직접 읽는 이상한 테스트인가.</b> 이 계약은 <b>두 저장소 파일 사이</b>에 있다 — {@code
 * deploy/docker-compose.app.yml} 의 healthcheck URL 과 {@code application.yml} 의 그룹 이름이다. 스프링 컨텍스트를
 * 띄워도 compose 파일은 안 읽히므로 통합 테스트로는 이 어긋남을 못 잡는다.
 *
 * <p>어긋나면 증상이 고약하다: {@code /actuator/health/<없는이름>} 이 <b>404</b> 를 주고 {@code curl -fsS} 가 실패해 <b>모든
 * 배포가 헬스체크 240초 초과로 실패</b>한다. 앱은 정상인데 배포만 안 된다 — 2026-08-05 에 그 상태를 겪었고, 원인을 찾는 데 EC2 접속과 로그 추적이
 * 필요했다.
 *
 * <p>⚠️ <b>이 테스트가 검증하지 못하는 것</b>: 그룹에 적은 지표 이름({@code db}·{@code redis}·{@code ping})이 스프링이 아는
 * 이름인지는 못 본다. 그건 컨텍스트를 띄워야 알 수 있고, 틀리면 그룹이 조용히 비어 200 을 준다(= 아무것도 검사하지 않는 헬스체크). 이름을 바꿀 때는 실제 응답을
 * 눈으로 확인할 것.
 */
class ActuatorHealthGroupTest {

  /** 저장소 루트. 테스트 작업 디렉터리는 {@code server/} 다(Gradle 기본). */
  private static final Path REPO_ROOT = Path.of("..").toAbsolutePath().normalize();

  private static String read(String relative) throws IOException {
    Path path = REPO_ROOT.resolve(relative);
    assertThat(path).as("이 테스트의 전제 — %s 가 있어야 한다", relative).exists();
    return Files.readString(path);
  }

  /** compose healthcheck URL 에서 그룹 이름을 뽑는다. 없으면 빈 문자열(= 전체 health 를 본다). */
  private static String healthGroupInCompose(String compose) {
    return compose
        .lines()
        .filter(line -> line.contains("actuator/health"))
        .filter(line -> !line.strip().startsWith("#"))
        .map(line -> line.replaceAll(".*actuator/health/?([a-zA-Z0-9_-]*).*", "$1"))
        .findFirst()
        .orElse("");
  }

  @Test
  @DisplayName("compose 헬스체크가 가리키는 그룹이 application.yml 에 정의돼 있다")
  void the_group_the_healthcheck_points_at_exists() throws IOException {
    String group = healthGroupInCompose(read("deploy/docker-compose.app.yml"));

    assertThat(group).as("compose healthcheck 가 그룹을 안 쓰면 전체 health 를 보게 된다").isNotEmpty();
    assertThat(read("server/src/main/resources/application.yml"))
        .as("healthcheck 는 '%s' 그룹을 보는데 application.yml 에 그 정의가 없다 → 404 → 모든 배포 실패", group)
        .contains(group + ":");
  }

  @Test
  @DisplayName("배포 게이트는 앱이 요청을 처리하는 데 필요한 것만 본다")
  void the_deploy_gate_only_watches_what_serving_needs() throws IOException {
    String group = deployGroupLine(read("server/src/main/resources/application.yml"));

    // 없으면 DB 가 죽었는데도 배포가 성공한다 — 게이트가 아무것도 안 지키는 것과 같다.
    assertThat(group).as("db 는 없으면 앱이 아무 일도 못 한다").contains("db");
    assertThat(group).as("redis 는 초대코드·쿨다운·레이트리밋이 쓴다").contains("redis");
  }

  @Test
  @DisplayName("부가 기능(mail)의 장애가 배포를 막지 않는다")
  void an_outage_of_a_side_feature_does_not_block_deploys() throws IOException {
    String group = deployGroupLine(read("server/src/main/resources/application.yml"));

    // 2026-08-05: SMTP 지표가 DOWN 이라 앱이 멀쩡한데 배포가 240초 초과로 실패했다.
    assertThat(group).as("메일 서버 장애가 배포 실패가 되면 안 된다").doesNotContain("mail");
    // ssl 지표(Boot 3.4+)는 인증서 만료 임박만으로 DOWN 이 된다 — 그것도 배포 사유가 아니다.
    assertThat(group).as("인증서 만료 임박이 배포 실패가 되면 안 된다").doesNotContain("ssl");
  }

  @Test
  @DisplayName("메일 헬스 지표는 꺼져 있다 — 켜면 SMTP 계정이 차단된다")
  void the_mail_health_indicator_stays_off() throws IOException {
    String application = read("server/src/main/resources/application.yml");

    // 🔴 2026-08-05 실측: `MailHealthIndicator` 는 헬스체크마다 SMTP 에 **실제로 로그인**한다.
    // docker healthcheck 간격 10초 × 하루 = 8,640회 → Gmail 이 막았다
    // (`454-4.7.0 Too many login attempts`). 그 차단 동안 실제 인증코드 발송도 실패했다.
    //
    // 그룹에서 뺀 것만으로는 부족하다 — 누군가 전체 `/actuator/health` 를 부르면 다시 시작된다.
    assertThat(application)
        .as("management.health.mail.enabled: false 가 없으면 헬스체크가 SMTP 로그인을 반복한다")
        .contains("mail:")
        .containsPattern("(?s)health:\\s*\\R\\s*mail:\\s*\\R(?:\\s*#.*\\R)*\\s*enabled: false");
  }

  @Test
  @DisplayName("show-details 를 켠 전제 — Caddy 가 actuator 를 외부에 막는다")
  void exposing_health_details_stays_internal() throws IOException {
    String application = read("server/src/main/resources/application.yml");
    if (!application.contains("show-details: always")) {
      return; // 상세를 안 켰으면 이 짝 조건은 필요 없다.
    }

    String caddy = read("deploy/Caddyfile");

    // 🔴 상세 노출이 안전한 **유일한 근거**가 이 규칙이다. 지우면 내부 정보가 공개된다.
    assertThat(caddy)
        .as("show-details: always 인데 Caddy 가 /actuator 를 막지 않으면 내부 정보가 외부에 열린다")
        .contains("/actuator");
    assertThat(caddy.lines().filter(l -> l.contains("actuator")).toList())
        .as("actuator 규칙이 404 로 끊는지")
        .isNotEmpty();
    assertThat(caddy).contains("respond @actuator 404");
  }

  /** `group: deploy:` 아래의 `include:` 한 줄. 없으면 실패시킨다 — 조용히 통과하면 이 테스트가 헛돈다. */
  private static String deployGroupLine(String application) {
    List<String> lines = application.lines().toList();
    for (int i = 0; i < lines.size(); i++) {
      if (lines.get(i).strip().equals("deploy:")) {
        for (int j = i + 1; j < Math.min(i + 4, lines.size()); j++) {
          if (lines.get(j).contains("include:")) {
            return lines.get(j);
          }
        }
      }
    }
    throw new AssertionError("application.yml 에서 health group 'deploy' 의 include 줄을 못 찾았다");
  }
}
