package com.nomara.modi.server.domain.archive.exception;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 크롤링 실패의 <b>재시도 분류</b>를 못 박는다.
 *
 * <p>🔴 <b>왜 소스를 읽는 이상한 테스트인가.</b> 위험은 "지금 분류가 틀렸다"가 아니라 <b>나중에 추가되는 실패가 잘못 분류되는 것</b>이다. 재시도는 외부
 * 사이트를 한 번 더 때리는 일이라, 영구 실패(비공개 게시물 등)에 켜지면 차단을 스스로 키운다 — 이 기능이 없애려던 문제를 이 기능이 만든다.
 *
 * <p>단위 테스트로는 그 실수를 못 잡는다. 새 {@code CrawlException.retryable(...)} 호출이 생겨도 기존 테스트는 전부 초록이다. 그래서
 * <b>호출 지점 목록 자체</b>를 고정한다 — 늘리거나 줄이면 여기가 빨개지고, 그때 "정말 일시적 실패인가"를 한 번 더 생각하게 된다.
 */
class CrawlExceptionRetryableTest {

  private static final Path CLIENT_DIR =
      Path.of("src/main/java/com/nomara/modi/server/domain/archive/client");

  /**
   * 재시도 대상을 만드는 팩토리 <b>둘 다</b> 본다 — {@code retryable} 과 {@code notAttempted}.
   *
   * <p>{@code notAttempted} 도 재시도 대상이라 감시 범위 밖에 두면 안 된다. 다르게 취급되는 것은 재시도 <b>횟수를 세느냐</b>뿐이다.
   */
  private static final Pattern RETRYABLE_CALL =
      Pattern.compile("CrawlException\\.(?:retryable|notAttempted)\\(\\s*\"([^\"]+)\"");

  /** 인자 모양과 무관하게 <b>호출 자체</b>를 센다. */
  private static final Pattern ANY_RETRYABLE_CALL =
      Pattern.compile("CrawlException\\.(?:retryable|notAttempted)\\(");

  /** 요청을 보내지도 못한 자리 — 재시도 횟수를 안 태우는 유일한 갈래다. */
  private static final Pattern NOT_ATTEMPTED_CALL =
      Pattern.compile("CrawlException\\.notAttempted\\(\\s*\"([^\"]+)\"");

  @Test
  @DisplayName("기본값은 재시도하지 않음이다")
  void the_default_is_not_retryable() {
    // 새 실패 사유를 추가하는 사람이 아무것도 안 하면 안전한 쪽으로 간다.
    assertThat(new CrawlException("무슨 실패").isRetryable()).isFalse();
    assertThat(new CrawlException("무슨 실패", new RuntimeException()).isRetryable()).isFalse();
  }

  @Test
  @DisplayName("retryable 로 만든 것만 재시도 대상이다")
  void only_the_factory_marks_it_retryable() {
    assertThat(CrawlException.retryable("잠시 막힘").isRetryable()).isTrue();
    assertThat(CrawlException.retryable("잠시 막힘", new RuntimeException()).isRetryable()).isTrue();
  }

  @Test
  @DisplayName("원인 예외를 잃지 않는다")
  void the_cause_survives() {
    RuntimeException cause = new RuntimeException("소켓 끊김");

    assertThat(CrawlException.retryable("잠시 막힘", cause)).hasCause(cause);
  }

  @Test
  @DisplayName("재시도로 표시된 곳은 이것뿐이다")
  void exactly_these_call_sites_are_retryable() throws IOException {
    // 늘리는 것 자체가 나쁘다는 뜻이 아니다 — **의식적으로** 늘리라는 뜻이다.
    // 새로 켰다면 여기 추가하면서 "상대의 일시적 상태 때문인가"를 답하면 된다.
    assertThat(retryableCallSites())
        .containsExactlyInAnyOrder(
            // 2026-08-05 운영에서 실측한 인스타 IP 소프트 블록. 10~20분이면 풀린다.
            "InstagramUrlCrawler: 인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요",
            // 아래는 전부 연결·읽기 실패다 — 상대 서버나 그 사이 경로 문제.
            "InstagramUrlCrawler: 링크를 불러오지 못했어요. 다시 시도해 주세요",
            "JsoupUrlCrawler: 링크를 불러오지 못했어요. 다시 시도해 주세요",
            "NaverUrlCrawler: 링크를 불러오지 못했어요. 다시 시도해 주세요",
            "YouTubeUrlCrawler: 링크를 불러오지 못했어요. 다시 시도해 주세요",
            // DNS 조회 실패 — JsoupUrlCrawler 에 있던 것이 UrlSafetyValidator 로 옮겨왔다
            // (2026-08-06). 새로 켠 것이 아니라 자리가 바뀐 것이다.
            "UrlSafetyValidator: 링크를 불러오지 못했어요. 다시 시도해 주세요");
  }

  @Test
  @DisplayName("요청을 보내지도 못한 것으로 표시된 곳은 이것뿐이다")
  void exactly_these_call_sites_skip_the_retry_counter() throws IOException {
    // 🔴 늘리는 데 특히 신중해야 한다. 이 갈래는 재시도 횟수를 안 태우므로 상한(3)이 안 걸리고,
    // 등록 후 경과 시간(6시간)만이 브레이크다. 진짜로 "우리가 스스로 멈춘" 경우여야 한다 —
    // 상대에게 요청을 보냈다면 그것은 시도한 것이다.
    assertThat(countInCrawlers(NOT_ATTEMPTED_CALL)).as("쿨다운 단락 한 곳뿐이어야 한다").isEqualTo(1);
    assertThat(retryableCallSites())
        .contains("InstagramUrlCrawler: 인스타그램이 잠시 막아둔 상태예요. 잠시 후 다시 시도해 주세요");
  }

  @Test
  @DisplayName("변수로 넘긴 retryable 호출이 숨지 않는다")
  void no_retryable_call_hides_behind_a_variable() throws IOException {
    // 위 목록은 **문자열 리터럴만** 읽는다. 누가 CrawlException.retryable(someMessage) 로 쓰면
    // 목록에 안 잡히고 조용히 통과한다 — 이 테스트가 지키려던 "한 번 멈추는" 효과가 그대로 뚫린다.
    // 그래서 호출 **개수**를 따로 세어 맞춰 본다(2026-08-06 리뷰 지적).
    assertThat(countInCrawlers(ANY_RETRYABLE_CALL))
        .as("리터럴이 아닌 인자로 부른 곳이 있다 — 이 테스트가 그것을 못 본다")
        .isEqualTo(countInCrawlers(RETRYABLE_CALL));
  }

  @Test
  @DisplayName("예상 못 한 예외를 감싸는 자리는 재시도가 아니다")
  void the_unexpected_exception_wrapper_is_not_retryable() throws IOException {
    // CompositeUrlCrawler 의 문구는 아래 타임아웃들과 **같지만** 성격이 다르다 —
    // 거기 오는 것은 상대의 일시적 상태가 아니라 우리 쪽 버그(NPE·파싱 오류)다.
    // 그래서 이 테스트는 문구가 아니라 **어느 파일에서 켰는지**를 본다.
    assertThat(retryableCallSites()).noneMatch(site -> site.startsWith("CompositeUrlCrawler:"));
  }

  @Test
  @DisplayName("대상 자체가 원인인 실패는 재시도하지 않는다")
  void failures_caused_by_the_target_are_never_retried() throws IOException {
    List<String> retryable = retryableCallSites();

    // 다시 걸어도 같은 답이 온다 — 재시도하면 외부 사이트만 더 때린다.
    assertThat(retryable)
        .noneSatisfy(
            site ->
                assertThat(site)
                    .containsAnyOf(
                        "공개된 게시물만 등록할 수 있어요", // 비공개·삭제·doc_id 만료
                        "게시물 주소를 알아볼 수 없어요",
                        "본문을 찾을 수 없는 링크예요",
                        "리다이렉트되는 링크는 등록할 수 없어요",
                        "장소를 불러올 수 없는 링크예요",
                        "영상을 불러올 수 없는 링크예요",
                        "등록할 수 없는 주소예요", // SSRF 차단
                        "http/https 링크만 등록할 수 있어요"));
  }

  /**
   * {@code "클래스이름: 문구"} 목록.
   *
   * <p><b>왜 파일 이름을 붙이나</b> — 문구만 모으면 이미 허용된 문구를 다른 파일에서 켜는 것을 놓친다. {@code CompositeUrlCrawler} 가
   * 정확히 그 경우다(같은 문구, 다른 성격).
   *
   * <p><b>왜 호출 <i>횟수</i>는 고정하지 않나</b> — 같은 파일에서 같은 문구를 한 번 더 켜는 것은 이미 검토된 범주 안이라 위험이 낮다. 횟수까지 박으면
   * 단순 리팩터링에도 빨개져서, 사람이 생각 없이 숫자만 고치는 습관이 든다 — 이 테스트가 만들려던 "한 번 멈추는" 효과를 스스로 깎는다.
   */
  private static List<String> retryableCallSites() throws IOException {
    assertThat(CLIENT_DIR).as("이 테스트의 전제 — 크롤러 디렉터리를 찾아야 한다").isDirectory();
    try (Stream<Path> files = Files.list(CLIENT_DIR)) {
      return files
          .filter(path -> path.toString().endsWith(".java"))
          .flatMap(CrawlExceptionRetryableTest::retryableCallSitesIn)
          .distinct()
          .sorted()
          .toList();
    }
  }

  private static Stream<String> retryableCallSitesIn(Path file) {
    String className = file.getFileName().toString().replace(".java", "");
    Matcher matcher = RETRYABLE_CALL.matcher(readSource(file));
    return matcher.results().map(result -> className + ": " + result.group(1)).toList().stream();
  }

  /** 크롤러 소스 전체에서 패턴이 몇 번 나오는지. */
  private static long countInCrawlers(Pattern pattern) throws IOException {
    assertThat(CLIENT_DIR).as("이 테스트의 전제 — 크롤러 디렉터리를 찾아야 한다").isDirectory();
    try (Stream<Path> files = Files.list(CLIENT_DIR)) {
      return files
          .filter(path -> path.toString().endsWith(".java"))
          .mapToLong(path -> pattern.matcher(readSource(path)).results().count())
          .sum();
    }
  }

  private static String readSource(Path file) {
    try {
      return Files.readString(file);
    } catch (IOException e) {
      throw new AssertionError("크롤러 소스를 읽지 못했다: " + file, e);
    }
  }
}
