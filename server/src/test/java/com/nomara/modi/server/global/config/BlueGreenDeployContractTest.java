package com.nomara.modi.server.global.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 무중단 배포(blue/green)가 성립하기 위해 <b>여러 파일이 서로 맞아야 하는 것들</b>을 묶는다.
 *
 * <p>🔴 <b>왜 파일을 직접 읽는 이상한 테스트인가.</b> {@link ActuatorHealthGroupTest} 와 같은 이유다 — 이 계약들은 {@code
 * application.yml} · {@code deploy/docker-compose.app.yml} · {@code deploy/Caddyfile} · {@code
 * deploy/deploy.sh} <b>사이</b>에 있다. 스프링 컨텍스트를 띄워도 compose·Caddyfile·셸 스크립트는 안 읽히므로 통합 테스트로는 이 어긋남을 못
 * 잡는다.
 *
 * <p>어긋났을 때의 증상이 전부 "조용하다"는 것이 이 테스트가 있는 이유다:
 *
 * <ul>
 *   <li>색 이름이 어긋나면 Caddy 가 upstream 을 못 찾아 <b>전부 502</b>
 *   <li>{@code stop_grace_period} 가 작으면 Docker 가 SIGKILL 을 먼저 보내 <b>graceful 설정이 있는데도 요청이 잘린다</b> —
 *       로그에 아무 흔적이 없다
 *   <li>{@code shutdown: graceful} 이 빠지면 배포마다 그 순간의 요청이 끊기는데, 클라이언트는 커넥션이 끊긴 것만 보고 서버 로그에는 아무것도 안
 *       남는다
 * </ul>
 *
 * <p>⚠️ <b>이 테스트가 검증하지 못하는 것</b>: 실제로 무중단인지는 못 본다(전환 중 5xx 0건은 Docker 로 리허설해야 확인된다). 여기서 보는 것은
 * "설정끼리 모순이 없다"까지다.
 */
class BlueGreenDeployContractTest {

  /** 저장소 루트. 테스트 작업 디렉터리는 {@code server/} 다(Gradle 기본). */
  private static final Path REPO_ROOT = Path.of("..").toAbsolutePath().normalize();

  private static final String APPLICATION_YML = "server/src/main/resources/application.yml";
  private static final String COMPOSE = "deploy/docker-compose.app.yml";
  private static final String CADDYFILE = "deploy/Caddyfile";
  private static final String ACTIVE_UPSTREAM = "deploy/active-upstream.conf.example";
  private static final String DEPLOY_SH = "deploy/deploy.sh";

  private static String read(String relative) throws IOException {
    Path path = REPO_ROOT.resolve(relative);
    assertThat(path).as("이 테스트의 전제 — %s 가 있어야 한다", relative).exists();
    return Files.readString(path);
  }

  // ---------------------------------------------------------------------------
  // graceful shutdown — 없으면 blue/green 을 해도 배포마다 요청이 잘린다
  // ---------------------------------------------------------------------------

  @Test
  @DisplayName("graceful shutdown 이 켜져 있다 — 없으면 옛 색을 세울 때 in-flight 요청이 잘린다")
  void graceful_shutdown_is_on() throws IOException {
    assertThat(read(APPLICATION_YML))
        .as(
            "server.shutdown: graceful 이 없으면 기본값 immediate 다 — SIGTERM 을 받는 즉시 톰캣이 멈춰"
                + " 처리 중이던 요청을 끊는다. blue/green 전환에서 옛 색에는 아직 응답을 만들고 있던"
                + " 요청이 남아 있으므로 이게 없으면 '무중단'이 성립하지 않는다.")
        .containsPattern("(?m)^  shutdown: graceful$");
  }

  @Test
  @DisplayName("stop_grace_period 가 Spring 의 종료 유예보다 크다 — 작으면 SIGKILL 이 먼저 온다")
  void docker_waits_longer_than_spring_needs() throws IOException {
    int springSeconds = seconds(APPLICATION_YML, "timeout-per-shutdown-phase");
    int dockerSeconds = seconds(COMPOSE, "stop_grace_period");

    assertThat(dockerSeconds)
        .as(
            "compose 의 stop_grace_period(%ds)가 application.yml 의"
                + " timeout-per-shutdown-phase(%ds)보다 커야 한다. 작으면 Docker 가 graceful shutdown 이"
                + " 끝나기 전에 SIGKILL 을 보내 요청이 잘린다 — 설정은 있는데 효과가 없고 로그에 흔적이 없다.",
            dockerSeconds, springSeconds)
        .isGreaterThan(springSeconds);
  }

  // ---------------------------------------------------------------------------
  // 색 이름 — compose · Caddy 활성 파일 · deploy.sh 세 곳이 같아야 한다
  // ---------------------------------------------------------------------------

  @Test
  @DisplayName("compose 에 blue/green 두 색이 있고 컨테이너 이름이 색마다 다르다")
  void compose_defines_exactly_two_colors() throws IOException {
    String compose = read(COMPOSE);

    assertThat(serviceNames(compose))
        .as("blue/green 두 색이 서비스로 있어야 한다. 하나뿐이면 무중단 전환 대상이 없다")
        .contains("spring-blue", "spring-green");

    // 같은 container_name 을 쓰면 두 번째 색이 기동에 실패한다(이름 충돌).
    assertThat(compose)
        .as("색마다 container_name 이 달라야 한다 — 같으면 이름 충돌로 기동 실패")
        .contains("container_name: maramodi-spring-blue")
        .contains("container_name: maramodi-spring-green");

    // 옛 단일 서비스가 남아 있으면 `compose up` 이 그것까지 띄워 두 색+옛 색이 동시에 뜬다.
    assertThat(compose)
        .as("옛 단일 spring 서비스와 그 컨테이너 이름이 남아 있으면 안 된다")
        .doesNotContain("container_name: maramodi-spring\n");
  }

  @Test
  @DisplayName("Caddy 가 트래픽을 보내는 색 이름이 compose 의 서비스 이름과 같다")
  void caddy_upstream_matches_a_compose_service() throws IOException {
    String upstream = activeColor(read(ACTIVE_UPSTREAM));

    assertThat(serviceNames(read(COMPOSE)))
        .as(
            "Caddy 활성 파일이 '%s' 를 가리키는데 compose 에 그 서비스가 없다 →" + " 내부 DNS 가 못 풀어 **모든 요청이 502** 다",
            upstream)
        .contains(upstream);
  }

  @Test
  @DisplayName("deploy.sh 가 두 색 이름을 모두 알고 있다")
  void deploy_script_knows_both_colors() throws IOException {
    String script = read(DEPLOY_SH);

    // deploy.sh 는 활성 파일에서 읽은 색의 '반대'로 전환한다. 한쪽 이름만 알면 전환이 한 방향으로만
    // 되거나(=두 번째 배포가 같은 색을 다시 띄운다) 활성 파일 해석이 실패한다.
    assertThat(script)
        .as("deploy.sh 가 두 색 이름을 모두 알아야 전환이 양방향으로 돈다")
        .contains("spring-blue")
        .contains("spring-green");

    // 🔴 inode 함정: 리눅스에서 단일 파일 bind-mount 는 inode 를 묶는다. sed -i / mv 로 활성
    // 파일을 갈아치우면 Caddy 는 옛 inode = 옛 내용을 계속 보고, 배포는 성공했다고 보고하면서
    // 트래픽은 방금 세운 옛 색으로 간다.
    //
    // ⚠️ **이 함정은 Docker Desktop(Windows/macOS)에서는 재현되지 않는다** — 파일 공유가 inode 가
    // 아니라 경로로 동작한다(2026-08-13 실측: 호스트 inode 가 바뀌어도 컨테이너는 새 내용을 봤다).
    // 운영 호스트가 리눅스이므로 규칙은 유지한다. 로컬 확인으로 이 검사를 기각하지 말 것.
    //
    // ⚠️ 주석을 반드시 걸러야 한다 — deploy.sh 는 바로 이 함정을 **경고하는 주석**에서
    // `sed -i` 를 언급한다. 걸러지 않으면 이 검사가 그 경고문에 걸려 오탐한다(실제로 겪었다).
    assertThat(uncommented(script))
        .as(
            "활성 파일은 `printf > 파일` 로 제자리 truncate 해야 한다."
                + " 리눅스에서 sed -i·mv 는 inode 를 바꿔 컨테이너가 옛 내용을 계속 본다")
        .doesNotContain("sed -i");

    // 전환은 `printf ... > "$ACTIVE_FILE"` 이어야 한다. 이게 없으면 위 검사만으로는
    // "sed 를 안 쓴다"만 알 뿐 제자리 쓰기를 하는지는 모른다.
    assertThat(uncommented(script))
        .as("활성 파일을 제자리 truncate 로 쓰는 줄(`printf ... > \"$ACTIVE_FILE\"`)이 있어야 한다")
        .contains("> \"$ACTIVE_FILE\"");
  }

  @Test
  @DisplayName("Caddyfile 이 활성 색을 import 로 읽는다 — upstream 하드코딩이 남아 있지 않다")
  void caddyfile_reads_the_active_color_from_the_imported_file() throws IOException {
    String caddy = read(CADDYFILE);

    assertThat(uncommented(caddy))
        .as(
            "Caddyfile 에 `reverse_proxy spring:8080` 같은 단일 upstream 하드코딩이 남아 있으면"
                + " 활성 파일을 바꿔도 트래픽이 안 옮겨간다(그 이름의 서비스는 이제 없어 502 다)")
        .doesNotContain("reverse_proxy spring:");

    assertThat(caddy)
        .as("활성 색 파일을 import 하지 않으면 배포가 전환할 대상이 없다")
        .contains("import active-upstream.conf");
  }

  @Test
  @DisplayName("활성 색 파일은 저장소 밖(상태 디렉터리)에서 마운트된다")
  void the_active_file_is_mounted_from_outside_the_repo() throws IOException {
    String infra = read("deploy/docker-compose.infra.yml");

    // 🔴 저장소 안의 경로(`./active-upstream.conf`)로 마운트하면, 배포 잡의
    // `git reset --hard origin/dev` 가 **매 배포마다 활성 색을 커밋된 값으로 되돌린다** —
    // 배포는 성공했다고 보고하는데 트래픽은 방금 세운 옛 색으로 가서 전부 502 다.
    assertThat(infra)
        .as(
            "활성 색 파일을 저장소 상대경로(./)로 마운트하면 git reset --hard 가 매 배포마다"
                + " 활성 색을 되돌린다. 상태 디렉터리(MARAMODI_STATE_DIR)에서 마운트할 것")
        .doesNotContain("./active-upstream.conf")
        .contains("MARAMODI_STATE_DIR");

    assertThat(read("deploy/.env.example"))
        .as("MARAMODI_STATE_DIR 이 .env.example 에 없으면 서버 .env 에 아무도 넣지 않는다")
        .contains("MARAMODI_STATE_DIR=");
  }

  // ---------------------------------------------------------------------------
  // 도우미
  // ---------------------------------------------------------------------------

  /** compose 의 `services:` 아래 최상위 서비스 이름들. */
  private static List<String> serviceNames(String compose) {
    List<String> lines = compose.lines().toList();
    int start = lines.indexOf("services:");
    if (start < 0) {
      throw new AssertionError("compose 에 `services:` 가 없다");
    }
    List<String> names = new java.util.ArrayList<>();
    for (String line : lines.subList(start + 1, lines.size())) {
      // 최상위 키(들여쓰기 0)를 만나면 services 블록이 끝난 것이다.
      if (!line.isBlank() && !line.startsWith(" ")) {
        break;
      }
      Matcher m = Pattern.compile("^ {2}([A-Za-z][A-Za-z0-9_-]*):\\s*$").matcher(line);
      if (m.matches()) {
        names.add(m.group(1));
      }
    }
    assertThat(names).as("services 아래에서 서비스 이름을 하나도 못 찾았다").isNotEmpty();
    return names;
  }

  /** `reverse_proxy spring-blue:8080` 에서 색 이름을 뽑는다. deploy.sh 의 sed 와 같은 규칙이다. */
  private static String activeColor(String activeUpstream) {
    Matcher m =
        Pattern.compile("(?m)^\\s*reverse_proxy\\s+(spring-(?:blue|green)):8080")
            .matcher(activeUpstream);
    assertThat(m.find())
        .as(
            "활성 색 파일에 `reverse_proxy spring-blue:8080` 형태의 줄이 없다."
                + " deploy.sh 도 같은 정규식으로 읽으므로 형식이 바뀌면 배포가 색을 못 알아본다")
        .isTrue();
    return m.group(1);
  }

  /** `<파일>` 에서 `<키>: 30s` 같은 값을 초 단위 정수로. 없으면 실패시킨다 — 조용히 통과하면 헛돈다. */
  private static int seconds(String relative, String key) throws IOException {
    Matcher m =
        Pattern.compile("(?m)^\\s*" + Pattern.quote(key) + ":\\s*(\\d+)s\\s*$")
            .matcher(read(relative));
    assertThat(m.find()).as("%s 에서 `%s: <숫자>s` 를 못 찾았다", relative, key).isTrue();
    return Integer.parseInt(m.group(1));
  }

  /** 주석(`#` 으로 시작하는 줄)을 뺀 본문. 주석에 적힌 옛 값 때문에 오탐하지 않게 한다. */
  private static String uncommented(String text) {
    return text.lines()
        .filter(line -> !line.strip().startsWith("#"))
        .reduce("", (a, b) -> a + b + "\n");
  }
}
