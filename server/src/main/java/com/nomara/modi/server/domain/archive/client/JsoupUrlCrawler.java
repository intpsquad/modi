package com.nomara.modi.server.domain.archive.client;

import com.nomara.modi.server.domain.archive.exception.CrawlException;
import java.net.URI;
import org.jsoup.Connection;
import org.jsoup.HttpStatusException;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.nodes.Node;
import org.jsoup.nodes.TextNode;
import org.jsoup.select.NodeTraversor;
import org.jsoup.select.NodeVisitor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 사용자가 등록한 외부 URL을 크롤링한다(S-25-C). 이 프로젝트가 처음으로 임의 외부 URL을 서버에서 직접 요청하는 지점이라 SSRF 방어를 함께 둔다:
 * http/https 스킴만 허용, 사설/루프백/링크로컬/멀티캐스트 IP 차단, 리다이렉트 미추종(추종 시 스킴/IP 재검증 없이 다른 호스트로 넘어가는 것을 막기 위함 —
 * 단축 URL 등 리다이렉트가 필요한 링크는 크롤링 실패로 처리, specs/0010 엣지케이스 참고), 연결/읽기 타임아웃과 응답 크기 상한. 응답이 200이어도 실제
 * 텍스트가 없는 페이지(예: 네이버 블로그 PC 주소처럼 iframe 껍데기뿐인 경우)도 크롤링 실패로 처리한다(2026-07-30 확정, `specs/OPEN.md`) —
 * 사이트별 iframe 추종은 SSRF 재검증이 따로 필요해 하지 않는다.
 */
@Component
public class JsoupUrlCrawler implements UrlCrawler {

  private final UrlSafetyValidator urlSafetyValidator;

  public JsoupUrlCrawler(UrlSafetyValidator urlSafetyValidator) {
    this.urlSafetyValidator = urlSafetyValidator;
  }

  private static final Logger log = LoggerFactory.getLogger(JsoupUrlCrawler.class);

  private static final int TIMEOUT_MILLIS = 5000;
  private static final int MAX_BODY_SIZE = 2_000_000;
  private static final String USER_AGENT = "Mozilla/5.0 (compatible; ModiArchiveBot/1.0)";

  /**
   * 본문이 아닌 것이 확실한 요소들. 여기서 걷어낸 잡음이 그대로 태깅·요약·추천 세 프롬프트의 입력 토큰이 되므로 크롤링 단계에서 없앤다. 클래스명·id 같은 사이트별
   * 추측은 넣지 않는다 — 시맨틱 태그와 ARIA 역할만 본다.
   */
  private static final String NOISE_SELECTOR =
      "script, style, noscript, template, iframe, svg, canvas, form, button, "
          + "nav, aside, "
          + "[role=navigation], [role=banner], [role=contentinfo], [role=complementary], "
          + "[role=search], [aria-hidden=true]";

  /**
   * <b>본문 바깥에 있을 때만</b> 노이즈인 것들. {@code <article><header><h1>글 제목</h1></header>}은 표준 블로그 템플릿이라 위치를
   * 보지 않고 지우면 문서에서 정보 밀도가 가장 높은 한 줄(제목·작성일·작성자)이 사라진다 — 태깅 프롬프트에 들어가는 것은 {@code bodyText}뿐이므로 AI
   * 입력에서도 통째로 빠진다.
   */
  private static final String OUTSIDE_CONTENT_NOISE_SELECTOR = "header, footer";

  /** 위 셀렉터의 "본문 안쪽" 판정 기준. */
  private static final String CONTENT_ROOT_ANCESTORS = "article, main, [role=main]";

  /** 본문 루트 후보. 매치된 것 중 <b>텍스트가 가장 긴 것</b>을 쓴다 — 첫 번째가 아니다(아래 비율 가드 주석 참고). */
  private static final String[] CONTENT_ROOT_SELECTORS = {"main", "[role=main]", "article"};

  /**
   * 본문 루트가 (노이즈를 걷어낸) 페이지 텍스트에서 차지해야 하는 최소 비율. 미달이면 셀렉터가 본문이 아닌 곳을 짚은 것으로 보고 body를 쓴다.
   *
   * <p>실측(EXPERIMENTS #12)에서 정상 케이스는 99% 이상이었고(위키백과 99.9%, MDN 99.1%), {@code <article>}을 카드 UI로 쓰는
   * 사이트는 7.4%였다 — 그 사이트에서 본문 3,384자가 92자로 날아갔다. 두 무리가 멀리 떨어져 있어 중간값을 쓴다. 가드가 걸렸을 때의 결과는 "덜 걷어낸
   * body"이므로, 틀려도 본문을 잃지는 않는다.
   */
  private static final double MIN_CONTENT_ROOT_RATIO = 0.5;

  @Override
  public CrawlResult crawl(String url) {
    validateUrl(url);

    Connection.Response response;
    try {
      response =
          Jsoup.connect(url)
              .timeout(TIMEOUT_MILLIS)
              .maxBodySize(MAX_BODY_SIZE)
              .followRedirects(false)
              .userAgent(USER_AGENT)
              .execute();
    } catch (HttpStatusException e) {
      // 🔴 **상대가 명확히 거절한 것은 다시 걸어도 같다**(2026-08-06 리뷰 P3). ignoreHttpErrors 를
      // 안 켜므로 jsoup 이 4xx/5xx 에 이 예외를 던지는데, 예전엔 아래 catch 가 전부 쓸어담아
      // **죽은 링크(404·410)도 20분 간격으로 세 번 더 긁었다.** 사용자는 한 시간 동안 "분석 중"을
      // 보다가 결국 "분석 실패"를 본다 — 즉시 알려주는 편이 낫다.
      log.warn("아카이브 링크가 오류 상태다(status={}): {}", e.getStatusCode(), url);
      if (isWorthRetrying(e.getStatusCode())) {
        throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
      }
      throw new CrawlException("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    } catch (Exception e) {
      log.warn("아카이브 링크 크롤링 실패: {}", url, e);
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }

    rejectRedirectStatus(response.statusCode());

    Document doc;
    try {
      doc = response.parse();
    } catch (Exception e) {
      log.warn("아카이브 링크 파싱 실패: {}", url, e);
      throw CrawlException.retryable("링크를 불러오지 못했어요. 다시 시도해 주세요", e);
    }

    return toCrawlResult(doc, url);
  }

  /**
   * 이 상태코드는 <b>상대의 일시적 상태</b>인가.
   *
   * <p>{@code 429}(과호출 제한)·{@code 408}(요청 타임아웃)·{@code 5xx}(서버 오류)는 잠시 뒤 달라질 수 있다. 나머지 4xx 는 <b>대상이
   * 원인</b>이다 — 없는 글(404·410), 권한 없음(401·403), 잘못된 요청. 다시 걸어도 같은 답이 오고 외부 사이트만 더 때린다.
   */
  static boolean isWorthRetrying(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  /**
   * 리다이렉트 미추종(SSRF 방어) 상태라 3xx는 예외 없이 그대로 돌아온다 — Jsoup은 3xx를 에러로 보지 않아 방치하면 빈/스텁 본문이 조용히 {@code
   * DONE}으로 저장된다(단축 URL 등, 2026-07-30 확정: 크롤링 실패로 처리). 네트워크 없이 상태코드 로직만 테스트할 수 있도록 분리했다.
   */
  void rejectRedirectStatus(int statusCode) {
    if (statusCode >= 300 && statusCode < 400) {
      throw new CrawlException("리다이렉트되는 링크는 등록할 수 없어요");
    }
  }

  /**
   * 파싱만 담당한다 — 네트워크를 타지 않아 픽스처 HTML로 단위 테스트할 수 있도록 분리했다({@code JsoupUrlCrawlerTest}).
   *
   * <p><b>{@code doc}을 파괴적으로 수정한다</b>(노이즈 요소 제거). 호출자는 이후 이 문서를 재사용하지 않는다.
   */
  CrawlResult toCrawlResult(Document doc, String url) {
    // 제목·썸네일은 <head>에서 읽으므로 본문 정제(파괴적)보다 먼저 뽑는다.
    String ogTitle = doc.select("meta[property=og:title]").attr("content");
    String title = !ogTitle.isBlank() ? ogTitle : doc.title();
    if (title.isBlank()) {
      title = url;
    }
    String ogImage = doc.select("meta[property=og:image]").attr("content");
    String source = URI.create(url).getHost();

    String bodyText = extractBodyText(doc);
    if (bodyText.isBlank()) {
      // 페이지가 사실상 iframe 껍데기뿐인 경우(예: 네이버 블로그 PC 주소, specs/OPEN.md 2026-07-29 실측) 조용히
      // 빈 본문으로 DONE 저장하지 않는다 — 크롤링 실패로 처리해 사용자가 원인을 알 수 있게 한다. 실제 본문이
      // 다른 호스트/iframe에 있을 수 있지만 SSRF 재검증이 필요한 사이트별 추종은 하지 않기로 확정(2026-07-30).
      throw new CrawlException("본문을 찾을 수 없는 링크예요");
    }

    return new CrawlResult(title, bodyText, ogImage.isBlank() ? null : ogImage, source);
  }

  private String extractBodyText(Document doc) {
    Element body = doc.body();
    if (body == null) {
      return "";
    }
    // 노이즈 제거 자체가 본문을 통째로 날리는 사이트가 있을 수 있어(예: 본문이 <form> 안) 정제 전 텍스트를
    // 최후의 폴백으로 먼저 확보해 둔다. DOM이 아니라 문자열이라 비용은 이 문서 한 벌뿐이다.
    String rawText = normalize(blockText(body));

    removeNoise(doc);
    String cleanedBody = normalize(blockText(body));
    if (cleanedBody.isBlank()) {
      return rawText;
    }

    String scoped = largestContentRootText(doc);
    if (scoped.length() >= cleanedBody.length() * MIN_CONTENT_ROOT_RATIO) {
      return scoped;
    }
    // 비율 가드가 걸린 기록을 남긴다 — MIN_CONTENT_ROOT_RATIO는 관측 3건으로 정한 값이라,
    // 운영 로그가 쌓여야 감이 아니라 수치로 재검토할 수 있다.
    log.debug("본문 루트가 페이지의 일부뿐이라 body를 쓴다: {}자 / {}자", scoped.length(), cleanedBody.length());
    return cleanedBody;
  }

  private void removeNoise(Document doc) {
    doc.select(NOISE_SELECTOR).remove();
    for (Element element : doc.select(OUTSIDE_CONTENT_NOISE_SELECTOR)) {
      if (element.closest(CONTENT_ROOT_ANCESTORS) == null) {
        element.remove();
      }
    }
  }

  /**
   * 본문 루트 후보 중 텍스트가 가장 긴 것. 첫 번째를 집으면 안 되는 이유는 실측에 있다 — {@code <article>}을 목록 카드마다 쓰는 사이트에서 {@code
   * selectFirst("article")}이 92자짜리 홍보 카드를 본문으로 골랐다(EXPERIMENTS #12).
   */
  private String largestContentRootText(Document doc) {
    String longest = "";
    for (String selector : CONTENT_ROOT_SELECTORS) {
      for (Element candidate : doc.select(selector)) {
        String text = normalize(blockText(candidate));
        if (text.length() > longest.length()) {
          longest = text;
        }
      }
    }
    return longest;
  }

  /**
   * 블록 경계를 개행으로 남기며 텍스트를 뽑는다. Jsoup의 {@code text()}는 문서 전체를 공백 하나로 이어붙여 한 줄로 만드는데, 이 결과물은 사람이 아니라
   * LLM이 읽는 입력이라 문단 경계가 의미를 가진다.
   */
  private static String blockText(Element root) {
    StringBuilder out = new StringBuilder();
    NodeTraversor.traverse(
        new NodeVisitor() {
          @Override
          public void head(Node node, int depth) {
            if (node instanceof TextNode textNode) {
              out.append(textNode.text());
            }
          }

          @Override
          public void tail(Node node, int depth) {
            if (node instanceof Element element
                && (element.tag().isBlock() || "br".equals(element.normalName()))) {
              out.append('\n');
            }
          }
        },
        root);
    return out.toString();
  }

  private static String normalize(String text) {
    return text.replaceAll("[^\\S\\n]+", " ") // 개행을 제외한 공백류를 하나로
        .replaceAll(" *\\n *", "\n") // 줄 앞뒤 공백 제거
        .replaceAll("\\n{2,}", "\n") // 빈 줄 제거
        .trim();
  }

  /**
   * 판정 자체는 {@link UrlSafetyValidator} 로 옮겼다(2026-08-06) — 크롤링 없이 이 검증만 필요한 자리가 생겨서다. 여기 남은 것은 호출뿐이고
   * 문구·순서·동작은 그대로다.
   */
  private void validateUrl(String url) {
    urlSafetyValidator.validate(url);
  }
}
