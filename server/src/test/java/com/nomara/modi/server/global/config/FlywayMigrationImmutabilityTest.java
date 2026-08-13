package com.nomara.modi.server.global.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * <b>이미 적용된 Flyway 마이그레이션 파일이 바뀌지 않았는지</b> 묶는다.
 *
 * <p>🔴 <b>2026-08-13 실제 사고 때문에 생긴 테스트다.</b> 조직 흔적 제거 작업이 {@code V5}·{@code V6}·{@code V7}·{@code
 * V10} 의 <b>첫 주석 줄에서 티켓 번호만</b> 지웠다. DDL 은 한 글자도 안 바뀌었지만 파일 내용이 바뀌어 Flyway 체크섬이 달라졌고, 운영 배포가 이렇게
 * 죽었다:
 *
 * <pre>
 * Validate failed: Migrations have failed validation
 * Migration checksum mismatch for migration version 5
 * -&gt; Applied to database : 1863795280
 * -&gt; Resolved locally    : -26747768
 * </pre>
 *
 * <p><b>부팅 자체가 안 됐다.</b> 그런데 그 시점에 서버 테스트 774개가 전부 통과했다 — 이 계약은 저장소 파일과 <b>운영 DB의 이력 테이블</b> 사이에
 * 있어서 어떤 단위·통합 테스트도 잡을 수 없다. H2/Testcontainers 는 매번 빈 DB로 시작하므로 마이그레이션이 그냥 처음부터 다시 적용되고 통과한다.
 *
 * <p>그래서 <b>"과거 파일이 바뀌었다"는 사실 자체</b>를 커밋된 지문 목록({@code
 * src/test/resources/db/migration-checksums.txt})과 비교해 잡는다. DB 없이도 돌고, PR 리뷰에서 눈으로 놓쳐도 잡힌다.
 *
 * <p>⚠️ <b>이 테스트가 검증하지 못하는 것</b>: 운영 DB 에 실제로 적용된 체크섬과 맞는지는 못 본다(DB 를 봐야 안다). 여기서 보는 것은 "우리가 과거 파일을
 * 건드렸는가"까지다 — 사고의 원인이 바로 그것이었다.
 */
class FlywayMigrationImmutabilityTest {

  /** 저장소 루트. 테스트 작업 디렉터리는 {@code server/} 다(Gradle 기본). */
  private static final Path REPO_ROOT = Path.of("..").toAbsolutePath().normalize();

  private static final Path MIGRATIONS =
      REPO_ROOT.resolve("server/src/main/resources/db/migration");
  private static final Path MANIFEST =
      REPO_ROOT.resolve("server/src/test/resources/db/migration-checksums.txt");

  /** `V12__foo.sql` → 12. 버전 순서로 정렬해 사람이 읽기 좋은 실패 메시지를 만든다. */
  private static final Pattern VERSION = Pattern.compile("^V(\\d+)__");

  @Test
  @DisplayName("이미 적용된 마이그레이션 파일이 한 글자도 바뀌지 않았다")
  void applied_migrations_are_never_edited() throws IOException {
    Map<String, String> expected = readManifest();
    Map<String, String> actual = fingerprintMigrations();

    // ① 목록에 있는데 내용이 다른 것 = **과거 파일을 고쳤다.** 이게 운영을 깨뜨린 그 상황이다.
    List<String> edited =
        expected.keySet().stream()
            .filter(actual::containsKey)
            .filter(name -> !expected.get(name).equals(actual.get(name)))
            .sorted(byVersion())
            .toList();

    assertThat(edited)
        .as(
            """
            🔴 이미 적용된 마이그레이션 파일이 바뀌었다: %s

            **주석 한 줄만 고쳐도 운영 부팅이 깨진다.** Flyway 는 파일 내용의 체크섬을 이력 테이블과
            비교하고, 다르면 `Validate failed` 로 컨텍스트를 못 띄운다(2026-08-13 실제로 그렇게 멈췄다).

            되돌리는 것이 정답이다 — 바꿀 내용이 있으면 **새 V번호 파일**로 만든다.

            정말 의도한 변경이라면(예: 조직 흔적 제거처럼 되돌릴 수 없는 이유) 두 가지를 함께 해야 한다:
              1) **모든 환경 DB 에서 flyway repair** — 이력 테이블의 checksum 을 새 값으로 교정.
                 안 하면 그 DB 는 다음 배포에서 부팅이 깨진다.
              2) 지문 목록 갱신:  ./scripts/regen-migration-checksums.sh
            """,
            edited)
        .isEmpty();

    // ② 파일은 있는데 목록에 없는 것 = 새 마이그레이션. 목록에 추가해야 이후 변경이 잡힌다.
    List<String> unlisted =
        actual.keySet().stream()
            .filter(name -> !expected.containsKey(name))
            .sorted(byVersion())
            .toList();

    assertThat(unlisted)
        .as(
            """
            새 마이그레이션이 지문 목록에 없다: %s

            `server/src/test/resources/db/migration-checksums.txt` 에 아래 줄을 추가할 것
            (목록에 없으면 그 파일은 이후 누가 고쳐도 이 테스트가 못 잡는다):

            %s
            """,
            unlisted,
            unlisted.stream().map(n -> n + "  " + actual.get(n)).reduce("", (a, b) -> a + b + "\n"))
        .isEmpty();

    // ③ 목록에 있는데 파일이 없는 것 = 마이그레이션을 지웠다. 적용된 것을 지우면 새 환경이 못 뜬다.
    List<String> deleted =
        expected.keySet().stream()
            .filter(name -> !actual.containsKey(name))
            .sorted(byVersion())
            .toList();

    assertThat(deleted)
        .as(
            """
            마이그레이션 파일이 사라졌다: %s

            이미 적용된 마이그레이션을 지우면 **새 환경에서 스키마를 재현할 수 없다**(기존 DB 는 이력에
            남아 있어 조용히 넘어가므로 발견이 늦다). 되살릴 것.
            """,
            deleted)
        .isEmpty();
  }

  @Test
  @DisplayName("매니페스트는 마이그레이션 개수와 같다 — 한쪽만 늘어나면 가드가 헛돈다")
  void the_manifest_covers_every_migration() throws IOException {
    assertThat(readManifest()).hasSameSizeAs(fingerprintMigrations());
  }

  // ---------------------------------------------------------------------------

  /** 파일명 → 지문. CRLF 를 LF 로 정규화한다 — 윈도우 체크아웃에서도 같은 값이 나와야 한다. */
  private static Map<String, String> fingerprintMigrations() throws IOException {
    assertThat(MIGRATIONS).as("이 테스트의 전제 — 마이그레이션 디렉터리가 있어야 한다").exists();
    Map<String, String> map = new LinkedHashMap<>();
    try (Stream<Path> files = Files.list(MIGRATIONS)) {
      for (Path p : files.filter(p -> p.getFileName().toString().endsWith(".sql")).toList()) {
        byte[] normalized =
            Files.readString(p, StandardCharsets.UTF_8)
                .replace("\r\n", "\n")
                .getBytes(StandardCharsets.UTF_8);
        map.put(p.getFileName().toString(), sha256(normalized));
      }
    }
    assertThat(map).as("마이그레이션이 하나도 없다 — 경로가 바뀌었는지 볼 것").isNotEmpty();
    return map;
  }

  private static Map<String, String> readManifest() throws IOException {
    assertThat(MANIFEST).as("지문 목록이 있어야 한다 — 지우면 이 가드가 사라진다").exists();
    Map<String, String> map = new LinkedHashMap<>();
    for (String line : Files.readAllLines(MANIFEST, StandardCharsets.UTF_8)) {
      String trimmed = line.strip();
      if (trimmed.isEmpty() || trimmed.startsWith("#")) {
        continue;
      }
      String[] parts = trimmed.split("\\s+");
      assertThat(parts).as("매니페스트 형식은 `<파일명>  <sha256>` 이다: %s", line).hasSize(2);
      map.put(parts[0], parts[1]);
    }
    return map;
  }

  private static String sha256(byte[] bytes) {
    try {
      StringBuilder hex = new StringBuilder();
      for (byte b : MessageDigest.getInstance("SHA-256").digest(bytes)) {
        hex.append(String.format("%02x", b));
      }
      return hex.toString();
    } catch (NoSuchAlgorithmException e) {
      throw new IllegalStateException("SHA-256 이 없는 JVM 은 없다", e);
    }
  }

  /** `V10` 이 `V9` 보다 뒤에 오도록 숫자로 정렬한다(문자열 정렬이면 V10 이 V2 앞에 온다). */
  private static Comparator<String> byVersion() {
    return Comparator.comparingInt(
        name -> {
          Matcher m = VERSION.matcher(name);
          return m.find() ? Integer.parseInt(m.group(1)) : Integer.MAX_VALUE;
        });
  }
}
