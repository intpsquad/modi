import java.io.*;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.GZIPInputStream;

/**
 * 인스타 2단계 요청(페이지 GET → GraphQL POST)을 **서버의 Java 로 직접** 보내 본다 — 진단용, 운영 코드 아님.
 *
 * <p>쓰는 때: 운영 서버에서 curl 은 JSON 을 받는데 서버만 로그인 HTML 을 받을 때. 2단계를 (a) {@code HttpURLConnection}(jsoup 이 쓰는
 * 스택) 과 (b) {@code java.net.http.HttpClient}/HTTP2 로 각각 보내 결과를 나란히 찍는다. 2026-08-23 실측: (a) HTML(로그인 벽) ·
 * (b) JSON items 있음 → 인스타가 데이터센터 IP 에서 접속 지문을 본다는 근거(#62). 절차는 README "서버의 Java 로 직접 재기".
 *
 * <pre>
 *   scp scripts/IgProbe.java modi:/tmp/
 *   ssh modi 'docker run --rm -v /tmp/IgProbe.java:/IgProbe.java eclipse-temurin:21-jdk java /IgProbe.java <shortcode>'
 * </pre>
 *
 * <p>토큰·쿠키 <b>값은 찍지 않는다</b>(있음/없음과 이름만). {@code DOC_ID} 는 손으로 맞춘다 — 운영값은 {@code main} 의
 * {@code application.yml}.
 */
public class IgProbe {
  static final String UA =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";
  static final String BASE = "https://www.instagram.com";
  static final String DOC_ID = "26713194205046842";

  public static void main(String[] args) throws Exception {
    String sc = args.length > 0 ? args[0] : "DcS1NjlkbpQ";
    String postUrl = BASE + "/p/" + sc + "/";

    // ── 1단계: 페이지 GET (jsoup 과 같은 헤더) ──
    HttpURLConnection c = (HttpURLConnection) URI.create(postUrl).toURL().openConnection();
    c.setInstanceFollowRedirects(false);
    c.setConnectTimeout(5000); c.setReadTimeout(5000);
    c.setRequestProperty("User-Agent", UA);
    c.setRequestProperty("Accept", "text/html, application/xhtml+xml, application/xml;q=0.9, */*;q=0.8");
    c.setRequestProperty("Accept-Encoding", "gzip");
    c.setRequestProperty("Accept-Language", "en-US,en;q=0.9");
    int st = c.getResponseCode();
    Map<String, String> cookies = new LinkedHashMap<>();
    List<String> setCookies = c.getHeaderFields().getOrDefault("Set-Cookie", List.of());
    for (String s : setCookies) {
      String kv = s.split(";", 2)[0];
      int eq = kv.indexOf('=');
      if (eq > 0) cookies.put(kv.substring(0, eq).trim(), kv.substring(eq + 1).trim());
    }
    String html = readBody(c);
    String lsd = between(html, "\"LSD\",[],{\"token\":\"", "\"");
    String csrf = cookies.getOrDefault("csrftoken", "");
    if (csrf.isBlank()) csrf = between(html, "\"csrf_token\":\"", "\"");
    cookies.put("csrftoken", csrf);
    System.out.println("1단계 페이지: status=" + st + " bytes=" + html.length()
        + " lsd=" + (lsd.isEmpty() ? "없음" : "있음") + " csrf=" + (csrf.isEmpty() ? "없음" : "있음")
        + " cookies=" + cookies.keySet());
    if (st != 200 || lsd.isEmpty() || csrf.isEmpty()) { System.out.println("1단계에서 막힘 — 여기서 끝"); return; }

    String variables = "{\"shortcode\":\"" + sc + "\",\"fetch_tagged_user_count\":null,\"hoisted_comment_id\":null,"
        + "\"hoisted_reply_id\":null,\"__relay_internal__pv__PolarisAIGMMediaWebLabelEnabledrelayprovider\":false}";
    String form = "lsd=" + enc(lsd) + "&doc_id=" + enc(DOC_ID) + "&fb_api_req_friendly_name=" + enc("PolarisPostRootQuery")
        + "&server_timestamps=true&variables=" + enc(variables);
    StringBuilder ck = new StringBuilder();
    for (var e : cookies.entrySet()) { if (ck.length() > 0) ck.append("; "); ck.append(e.getKey()).append('=').append(e.getValue()); }
    String[][] headers = {
        {"X-IG-App-ID", "936619743392459"}, {"X-FB-LSD", lsd}, {"X-CSRFToken", csrf},
        {"X-FB-Friendly-Name", "PolarisPostRootQuery"}, {"X-Requested-With", "XMLHttpRequest"},
        {"Origin", BASE}, {"Referer", postUrl}, {"Sec-Fetch-Site", "same-origin"}, {"Sec-Fetch-Mode", "cors"},
        {"Sec-Fetch-Dest", "empty"}, {"Accept", "*/*"}, {"Accept-Language", "en-US,en;q=0.9"},
    };

    // ── 2단계 (a): HttpURLConnection — jsoup 과 같은 스택, HTTP/1.1 ──
    HttpURLConnection p = (HttpURLConnection) URI.create(BASE + "/graphql/query/").toURL().openConnection();
    p.setInstanceFollowRedirects(false);
    p.setConnectTimeout(5000); p.setReadTimeout(5000);
    p.setRequestMethod("POST"); p.setDoOutput(true);
    p.setRequestProperty("User-Agent", UA);
    p.setRequestProperty("Accept-Encoding", "gzip");
    p.setRequestProperty("Cookie", ck.toString());
    for (String[] h : headers) p.setRequestProperty(h[0], h[1]);
    p.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
    try (OutputStream os = p.getOutputStream()) { os.write(form.getBytes(StandardCharsets.UTF_8)); }
    int pst = p.getResponseCode();
    String body = readBody(p);
    report("2단계(a) HttpURLConnection", pst, p.getHeaderField("Content-Type"), body);

    // ── 2단계 (b): java.net.http.HttpClient — HTTP/2 ──
    HttpClient hc = HttpClient.newBuilder().version(HttpClient.Version.HTTP_2)
        .followRedirects(HttpClient.Redirect.NEVER).build();
    HttpRequest.Builder rb = HttpRequest.newBuilder(URI.create(BASE + "/graphql/query/"))
        .header("User-Agent", UA).header("Cookie", ck.toString())
        .header("Content-Type", "application/x-www-form-urlencoded")
        .POST(HttpRequest.BodyPublishers.ofString(form));
    for (String[] h : headers) rb.header(h[0], h[1]);
    HttpResponse<String> r = hc.send(rb.build(), HttpResponse.BodyHandlers.ofString());
    report("2단계(b) HttpClient/" + r.version(), r.statusCode(), r.headers().firstValue("Content-Type").orElse("?"), r.body());
  }

  static void report(String label, int status, String ctype, String body) {
    String shape = body.startsWith("<") ? "HTML(로그인 벽)" : body.startsWith("{") ? "JSON" : "기타";
    String items = body.contains("\"items\":[]") ? " items=빈배열" : body.contains("\"items\":[{") ? " items=있음" : "";
    System.out.println(label + ": status=" + status + " type=" + ctype + " shape=" + shape + items + " bytes=" + body.length());
  }

  static String readBody(HttpURLConnection c) throws IOException {
    InputStream in = c.getResponseCode() >= 400 ? c.getErrorStream() : c.getInputStream();
    if (in == null) return "";
    if ("gzip".equalsIgnoreCase(c.getContentEncoding())) in = new GZIPInputStream(in);
    return new String(in.readAllBytes(), StandardCharsets.UTF_8);
  }

  static String between(String s, String a, String b) {
    int i = s.indexOf(a); if (i < 0) return "";
    int j = s.indexOf(b, i + a.length()); if (j < 0) return "";
    return s.substring(i + a.length(), j);
  }

  static String enc(String s) { return URLEncoder.encode(s, StandardCharsets.UTF_8); }
}
