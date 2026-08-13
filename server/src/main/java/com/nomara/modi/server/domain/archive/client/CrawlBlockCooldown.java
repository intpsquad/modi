package com.nomara.modi.server.domain.archive.client;

/**
 * "이 사이트가 지금 우리를 막고 있다"를 기억하는 곳.
 *
 * <p>🔴 <b>왜 필요한가</b>(2026-08-05 실측). 운영 EC2 IP 가 인스타그램에서 소프트 블록됐다. 그런데 우리 코드는 그걸 <b>기억하지 않아서</b>,
 * 다음 공유가 와도 똑같이 부트스트랩 + GraphQL + 재시도로 <b>4번</b> 때렸다. 얻는 것은 0 이고, 데이터센터 IP 의 비인증 트래픽이 누적될수록 차단이
 * 켜지므로 <b>스스로 차단을 길게 만들었다.</b>
 *
 * <p>실측 근거:
 *
 * <ul>
 *   <li>같은 shortcode 가 아침엔 JSON 146KB, 오후엔 challenge HTML 610KB (같은 서버·같은 코드)
 *   <li>{@code curl} 도 똑같이 막힌다 — 클라이언트가 아니라 <b>IP</b> 를 보고 막는다
 *   <li>실패 11건이 2~16분 간격으로 뭉쳐 있었다 — 그 구간의 호출이 전부 헛수고였다
 * </ul>
 *
 * <p>참조 문서(InstaFix 계열)도 같은 처방을 적어뒀다: <i>"Heavy unauthenticated traffic from one IP eventually gets
 * soft-blocked ... Cache aggressively, coalesce concurrent requests, and consider a residential
 * egress if running from a datacenter."</i>
 *
 * <p>⚠️ <b>이것은 차단을 없애지 않는다.</b> 차단된 동안 헛되게 때리는 것을 멈출 뿐이다. 근본 해결은 데이터센터가 아닌 곳으로 나가는 것이고 그건 코드가 아니다
 * ({@code specs/OPEN.md}).
 *
 * <p>인터페이스로 둔 이유는 <b>단위 테스트가 Redis 없이 돌아야 하기 때문</b>이다({@code ObjectStorage} 와 같은 이유).
 */
public interface CrawlBlockCooldown {

  /** 지금 쿨다운 중인가. <b>true 면 호출부는 외부 요청을 하나도 하지 않아야 한다.</b> */
  boolean isBlocked(String site);

  /** 차단을 확인했다 — 쿨다운을 건다. 이미 걸려 있으면 시간을 다시 채운다. */
  void markBlocked(String site);
}
