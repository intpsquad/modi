package com.nomara.modi.server.domain.archive.client;

import com.nomara.modi.server.domain.archive.exception.CrawlException;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.URI;
import java.net.UnknownHostException;
import org.springframework.stereotype.Component;

/**
 * 등록해도 되는 주소인가 — <b>네트워크로 내용을 받아오기 전에</b> 판정한다.
 *
 * <p>{@link JsoupUrlCrawler} 안에 있던 {@code validateUrl} 을 그대로 꺼냈다(2026-08-06). 꺼낸 이유는 <b>크롤링 없이 이
 * 판정만 필요한 자리가 생겼기 때문</b>이다 — 인앱 등록(S-25-C)이 비동기로 바뀌면서, 내용을 받아오는 것은 뒤로 미루되 <b>오타·사설망 주소는 등록 시점에
 * 즉시</b> 거절해야 한다({@code ArchiveItemService.createItem}). 그 둘을 한 메서드에 묶어 두면 "검증만" 부를 방법이 없다.
 *
 * <p>🔴 <b>이 클래스가 SSRF 방어선이다.</b> 사용자가 준 주소로 서버가 요청을 보내는 구조라, 여기가 느슨하면 서버가 내부망을 대신 긁어준다. 전용
 * 크롤러들(인스타 shortcode·유튜브 id·네이버 place id)은 <b>각자 별도의 방어선</b>을 갖고 있고 이것을 대체하지 않는다.
 *
 * <p>⚠️ <b>DNS 를 한 번 탄다</b>({@code InetAddress.getByName}). 호스트 이름이 어떤 IP 로 풀리는지 봐야 사설망인지 알 수 있어서
 * 피할 수 없다. 보통 수 밀리초지만 <b>네트워크를 타는 검증</b>이라는 점은 호출부가 알고 있어야 한다.
 */
@Component
public class UrlSafetyValidator {

  /**
   * 문제가 있으면 {@link CrawlException} 을 던진다. 통과하면 조용히 돌아온다.
   *
   * <p>문구는 꺼내기 전과 <b>글자 하나까지 같다</b> — 사용자에게 보이는 메시지라 이 리팩터링으로 바뀌면 안 된다.
   */
  public void validate(String url) {
    URI uri;
    try {
      uri = URI.create(url);
    } catch (IllegalArgumentException e) {
      throw new CrawlException("올바르지 않은 링크예요", e);
    }
    String scheme = uri.getScheme();
    if (!"http".equalsIgnoreCase(scheme) && !"https".equalsIgnoreCase(scheme)) {
      throw new CrawlException("http/https 링크만 등록할 수 있어요");
    }
    String host = uri.getHost();
    if (host == null || host.isBlank()) {
      throw new CrawlException("올바르지 않은 링크예요");
    }
    try {
      InetAddress address = InetAddress.getByName(host);
      if (address.isLoopbackAddress()
          || address.isLinkLocalAddress()
          || address.isSiteLocalAddress()
          || address.isMulticastAddress()
          || address.isAnyLocalAddress()
          || isIpv6UniqueLocal(address)) {
        throw new CrawlException("등록할 수 없는 주소예요");
      }
    } catch (UnknownHostException e) {
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }
  }

  // JDK의 isSiteLocalAddress()는 폐기된 IPv6 fec0::/10만 인식하고, 실제로 쓰이는
  // RFC 4193 ULA(fc00::/7 — IPv4 사설망의 IPv6 대응)는 별도 체크가 필요하다(리뷰에서 실측 확인).
  private boolean isIpv6UniqueLocal(InetAddress address) {
    if (!(address instanceof Inet6Address)) {
      return false;
    }
    byte[] bytes = address.getAddress();
    return (bytes[0] & 0xFE) == 0xFC;
  }
}
