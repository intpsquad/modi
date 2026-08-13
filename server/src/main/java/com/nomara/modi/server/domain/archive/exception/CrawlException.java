package com.nomara.modi.server.domain.archive.exception;

/**
 * URL 크롤링 실패(잘못된 주소/SSRF 차단/타임아웃/네트워크 오류) — 등록 자체를 막는 사유가 된다.
 *
 * <p>🔴 <b>{@link #isRetryable()} 로 두 종류를 가른다</b>(2026-08-06). 지금까지는 실패가 전부 한 덩어리라 "잠시 뒤 다시 해보면 될
 * 것"과 "몇 번을 해도 같은 답이 올 것"을 구분할 수 없었다. 그래서 인스타가 IP 를 소프트 블록한 동안 들어온 공유가 <b>영구 실패로 확정</b>됐다 — 운영 실패율
 * 58%(19건 중 11건)의 실체가 그것이고, 그 차단은 10~20분이면 풀렸다(운영 DB 실측: 12:45 실패 → 12:54 성공).
 *
 * <p><b>기본값은 {@code false} 다.</b> 새 실패 사유를 추가하는 사람이 아무것도 안 하면 "재시도하지 않음"이 된다 — 조용히 재시도되는 쪽보다 안전하다.
 * 재시도는 외부 사이트를 한 번 더 때리는 일이라 확신이 있을 때만 켜야 한다.
 *
 * <p><b>{@code true} 로 켜도 되는 것</b>: 상대의 일시적 상태 때문에 실패한 것 — 소프트 블록, 연결·읽기 타임아웃, 게이트웨이 순단.
 *
 * <p><b>켜면 안 되는 것</b>: 입력이나 대상 자체가 원인인 것 — 비공개·삭제된 게시물, 알아볼 수 없는 주소, 본문이 없는 페이지. 다시 걸어도 같은 답이 오고 외부
 * 사이트를 헛되게 더 때리기만 한다.
 */
public class CrawlException extends RuntimeException {

  private final boolean retryable;
  private final boolean attempted;

  public CrawlException(String message) {
    this(message, null, false, true);
  }

  public CrawlException(String message, Throwable cause) {
    this(message, cause, false, true);
  }

  private CrawlException(String message, Throwable cause, boolean retryable, boolean attempted) {
    super(message, cause);
    this.retryable = retryable;
    this.attempted = attempted;
  }

  /** 상대의 <b>일시적</b> 상태 때문에 실패했다 — 잠시 뒤 다시 해볼 값이 있다. */
  public static CrawlException retryable(String message) {
    return new CrawlException(message, null, true, true);
  }

  /** 위와 같고 원인 예외를 함께 남긴다. */
  public static CrawlException retryable(String message, Throwable cause) {
    return new CrawlException(message, cause, true, true);
  }

  /**
   * <b>요청을 보내지도 못하고</b> 끝났다 — 쿨다운 단락처럼 우리 쪽에서 스스로 멈춘 경우(2026-08-06 리뷰 P2).
   *
   * <p>🔴 <b>왜 {@link #retryable} 과 갈라야 하나.</b> 재시도 횟수는 "몇 번 해봤나"를 세는 것인데, 쿨다운 단락은 인스타를 한 번도 안 때린다.
   * 같은 카운터를 쓰면 <b>차단이 길 때 밀려 있던 자료들이 요청 0회로 상한을 소진하고 실패로 확정</b>된다 — 이 기능이 정확히 겨냥한 상황에서 무력해진다.
   *
   * <p>배치의 큐 거부에 이미 같은 원칙을 쓰고 있다({@code ArchiveItemRepository.rescheduleCrawl}): <i>"실패한 것이 아니라
   * 보내지도 못한 것이다."</i>
   */
  public static CrawlException notAttempted(String message) {
    return new CrawlException(message, null, true, false);
  }

  public boolean isRetryable() {
    return retryable;
  }

  /**
   * 실제로 상대에게 요청을 보냈나. {@code false} 면 재시도 횟수를 <b>태우지 않는다</b>({@code ArchiveCrawlProcessor}).
   *
   * <p>기본값이 {@code true} 인 이유: 대부분의 실패는 보내고 나서 나고, 잘못 {@code false} 로 두면 상한이 안 걸려 항목이 오래 "분석 중"으로
   * 남는다 — 안전한 쪽이 {@code true} 다.
   */
  public boolean isAttempted() {
    return attempted;
  }
}
