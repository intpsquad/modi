import Foundation

struct ShareContent {
  let value: String
  let isURL: Bool
}

/// 공유 시트로 들어온 값에서 등록할 링크를 뽑는다(S-25-D).
///
/// 🔴 **왜 필요한가**: 앱들은 URL 만 보내지 않는다. 네이버 지도 공유 버튼은 이렇게 보낸다 —
///
///     [네이버지도] 돼지통 역삼2호점 서울 강남구 … https://naver.me/52aGF4S5
///
/// 원래 코드는 `URL(string: value)?.host` 로 **문자열 전체가 URL 인지**를 봤다. 위 텍스트는 거짓이라
/// 링크가 아니라 텍스트로 등록됐고, **크롤링이 아예 안 일어났다**(안드로이드에서 2026-08-05 실측:
/// `crawl_status=DONE · url=(빈칸) · title=[네이버지도] 돼지통…`). iOS 도 같은 모양으로 깨진다.
///
/// ⚠️ **안드로이드에 같은 규칙이 따로 있다**(`SharedTextUrl.kt`). 네이티브 2종이라 공유 코드가 없다 —
/// 규칙의 단일 진실은 `specs/0014-외부-공유-등록.md` 이고, 한쪽을 고치면 다른 쪽도 고쳐야 한다.
///
/// ⚠️ **`NSDataDetector(.link)` 를 쓰지 않았다.** 계획에는 그렇게 적었는데, 그건 애플의 휴리스틱이라
/// 안드로이드의 정규식과 **어디서 갈리는지 열거할 수도 테스트할 수도 없다**(스킴 없는 `naver.me/x`·
/// 이메일까지 잡고, 괄호 균형을 자체 규칙으로 맞춘다). 두 네이티브가 **글자 단위로 같은 규칙**을 갖는
/// 쪽이 스펙을 단일 진실로 유지하는 데 유리해 같은 패턴의 정규식으로 맞췄다.
enum ShareContentParser {
  static func parse(_ rawValue: String?) -> ShareContent? {
    guard let rawValue else { return nil }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    if let extracted = extractHTTPURL(from: value) {
      return ShareContent(value: extracted, isURL: true)
    }

    // 뽑을 링크가 없다 → 텍스트로 등록한다. 다만 **문자열 전체가 http(s) 아닌 URL** 이면 거른다:
    // provider 가 file://·mailto: 를 건네줄 수 있는데, 로컬 파일 경로를 텍스트인 척 등록하지 않는다.
    // (S-25-D 계약은 웹 URL 만 받는다. nil 을 주면 호출부가 다음 provider 로 넘어간다.)
    if let scheme = URL(string: value)?.scheme?.lowercased(), scheme != "http", scheme != "https" {
      return nil
    }

    return ShareContent(value: value, isURL: false)
  }

  /// http/https 로 시작하는 조각. 공백·꺾쇠·따옴표에서 끊는다.
  ///
  /// ⚠️ 안드로이드 `SharedTextUrl.HTTP_URL` 과 **패턴이 글자 단위로 같아야 한다.**
  ///
  /// 🔴 **`\p{Z}` 와 `\x0B` 가 왜 붙어 있는가** — 두 엔진의 `\s` 가 서로 다르기 때문이다. ICU 는
  /// `[\t\n\f\r\p{Z}]`, 자바/코틀린은 **ASCII 전용** `[ \t\n\x0B\f\r]` 다. 그대로 두면 전각
  /// 공백(U+3000)·NBSP 에서 안드로이드만 안 끊긴다(2026-08-05 리뷰 실측). 양쪽에 `\p{Z}` 와
  /// `\x0B` 를 명시하면 두 집합이 정확히 같아진다 — 공백 U+0020 은 `\p{Z}`(Zs) 에 들어 있다.
  ///
  /// `try!` 인 이유: 리터럴 상수라 컴파일 실패는 런타임 조건이 아니라 버그다. 여기서 조용히 nil 로
  /// 물러나면 모든 공유가 텍스트로 등록되는 편이 훨씬 나쁘다.
  private static let httpURL = try! NSRegularExpression(
    pattern: #"https?://[^\s\p{Z}\x0B<>"']+"#,
    options: [.caseInsensitive]
  )

  /// URL 뒤에 붙어 오는 문장부호. 닫는 괄호류는 `isBalancedCloser` 로 한 번 더 거른다.
  ///
  /// `"` 와 `'` 는 위 패턴이 이미 URL 본문에서 제외해 여기까지 오지 않는다. 두 플랫폼의 목록을 눈으로
  /// 대조할 수 있게 그대로 둔다.
  private static let trailingPunctuation: Set<Character> = [
    ".", ",", ";", ":", "!", "?", ")", "]", "}", "\"", "'", "»",
  ]

  /// 짝을 세어볼 괄호들 — 닫는 문자 → 여는 문자.
  private static let brackets: [Character: Character] = [")": "(", "]": "[", "}": "{"]

  /// 공유 텍스트에서 등록할 URL. 없으면 `nil`.
  ///
  /// **여러 개면 마지막 것을 쓴다** — 앱들은 설명을 앞에, 링크를 끝에 붙인다.
  private static func extractHTTPURL(from text: String) -> String? {
    let whole = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = httpURL.matches(in: text, options: [], range: whole).last,
      let matched = Range(match.range, in: text)
    else {
      return nil
    }

    let candidate = trimTrailingPunctuation(String(text[matched]))
    return candidate.isEmpty ? nil : candidate
  }

  /// URL 뒤에 문장부호가 붙어 오는 경우를 걷어낸다(`…/x.` · `여기(…/x)`).
  ///
  /// 🔴 **닫는 괄호는 짝이 맞으면 URL 의 일부로 본다.** 처음엔 무조건 잘랐는데, 그러면
  /// `https://en.wikipedia.org/wiki/Cat_(disambiguation)` 같은 **정상 URL 이 조용히 망가진다**
  /// (2026-08-05 리뷰가 잡았다). 등록 후에는 앱에서 `url` 을 고칠 수단이 아예 없어 영구 손상이다.
  ///
  /// ```
  ///   …/Cat_(disambiguation)   → '(' 1개 ')' 1개 → 짝이 맞다  → 그대로 둔다
  ///   여기(…/52aGF4S5)          → '(' 0개 ')' 1개 → 짝이 없다 → 잘라낸다
  /// ```
  ///
  /// ⚠️ 안드로이드에 같은 함수가 있다(`SharedTextUrl.kt`). 규칙은 `specs/0014`.
  private static func trimTrailingPunctuation(_ url: String) -> String {
    var candidate = url
    while let last = candidate.last, trailingPunctuation.contains(last) {
      if isBalancedCloser(candidate, last) {
        break
      }
      candidate.removeLast()
    }
    return candidate
  }

  /// 마지막 글자가 닫는 괄호이고, 그 앞에 짝지을 여는 괄호가 충분히 있는가.
  private static func isBalancedCloser(_ candidate: String, _ last: Character) -> Bool {
    guard let opener = brackets[last] else { return false }
    return candidate.filter { $0 == opener }.count >= candidate.filter { $0 == last }.count
  }
}
