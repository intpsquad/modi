import XCTest

@testable import Runner

/// 공유 값에서 URL 을 뽑는 규칙(S-25-D).
///
/// ⚠️ **CI 는 이 파일을 돌리지 않는다** — macOS 러너가 아예 없다(프라이빗 저장소에서 분수를
/// 10배로 소모한다). iOS 릴리스도 Mac 에서 사람이 돌리는 절차뿐이다(`docs/ios-release.md`).
/// 그래서 이 테스트는 macOS 에서 사람이 돌려야 한다:
/// `xcodebuild test -workspace Runner.xcworkspace -scheme Runner \
///     -destination 'platform=iOS Simulator,name=iPhone 15'` (`specs/OPEN.md` 에 CI 공백으로 올림).
///
/// ⚠️ **안드로이드에 같은 케이스가 따로 있다**(`SharedTextUrlTest.kt`). 여기를 고치면 그쪽도 고친다 —
/// 규칙의 단일 진실은 `specs/0014-외부-공유-등록.md`.
final class ShareContentTests: XCTestCase {
  func testExtractsLinkFromNaverMapShareText() {
    // 🔴 2026-08-05 사용자가 신고한 바로 그 문자열(안드로이드에서 재현). iOS 도 같게 깨져 있었다.
    let shared = "[네이버지도] 돼지통 역삼2호점 서울 강남구 역삼로 123 https://naver.me/52aGF4S5"

    let content = ShareContentParser.parse(shared)

    XCTAssertEqual(content?.value, "https://naver.me/52aGF4S5")
    XCTAssertEqual(content?.isURL, true)
  }

  func testExtractsLinkAcrossNewlines() {
    let shared = "[네이버지도] 몽탄\n서울 용산구 백범로99길 50\nhttps://naver.me/FoEJcO1X"

    let content = ShareContentParser.parse(shared)

    XCTAssertEqual(content?.value, "https://naver.me/FoEJcO1X")
    XCTAssertEqual(content?.isURL, true)
  }

  func testKeepsBareURLShareUnchanged() {
    // 회귀 방어선 — 유튜브·인스타 공유는 지금까지 이 모양이었고 계속 되어야 한다.
    let trimmed = ShareContentParser.parse("  https://example.com/article  ")
    XCTAssertEqual(trimmed?.value, "https://example.com/article")
    XCTAssertEqual(trimmed?.isURL, true)

    let instagram = ShareContentParser.parse("https://www.instagram.com/p/DZb-UAhz4Iq/?igsh=x")
    XCTAssertEqual(instagram?.value, "https://www.instagram.com/p/DZb-UAhz4Iq/?igsh=x")
    XCTAssertEqual(instagram?.isURL, true)
  }

  func testKeepsArbitraryTextAsText() {
    let content = ShareContentParser.parse("  회의 자료를 읽어보기  ")

    XCTAssertEqual(content?.value, "회의 자료를 읽어보기")
    XCTAssertEqual(content?.isURL, false)
  }

  func testUsesLastLinkWhenSeveral() {
    // 앱들은 설명을 앞에, 링크를 끝에 붙인다.
    let shared = "https://example.com/도움말 를 보고 https://naver.me/52aGF4S5 갔어요"

    XCTAssertEqual(ShareContentParser.parse(shared)?.value, "https://naver.me/52aGF4S5")
  }

  func testDoesNotExtractSchemelessLink() {
    // 서버로 보낼 값은 http(s) 로 확정한다. 링크로 못 뽑으면 텍스트로 등록한다(동작 불변).
    let content = ShareContentParser.parse("네이버 지도에서 naver.me/52aGF4S5 확인")

    XCTAssertEqual(content?.value, "네이버 지도에서 naver.me/52aGF4S5 확인")
    XCTAssertEqual(content?.isURL, false)
  }

  func testTrimsTrailingPunctuation() {
    XCTAssertEqual(
      ShareContentParser.parse("여기 가봐 https://naver.me/52aGF4S5.")?.value,
      "https://naver.me/52aGF4S5")
    XCTAssertEqual(
      ShareContentParser.parse("여기(https://naver.me/52aGF4S5)")?.value,
      "https://naver.me/52aGF4S5")
  }

  func testKeepsBalancedClosingBracket() {
    // 🔴 2026-08-05 리뷰가 잡은 회귀. 닫는 괄호를 무조건 잘랐더니 위키백과 주소가 조용히 망가졌고,
    // 등록 후에는 앱에서 url 을 고칠 수단이 없어 영구 손상이었다.
    let wiki = "https://en.wikipedia.org/wiki/Cat_(disambiguation)"
    XCTAssertEqual(ShareContentParser.parse(wiki)?.value, wiki)
    // 주변에 설명이 있어도 같아야 한다 — "통째로 URL 일 때만" 봐주는 규칙으로는 이게 안 걸린다.
    XCTAssertEqual(ShareContentParser.parse("참고 \(wiki)")?.value, wiki)
    XCTAssertEqual(
      ShareContentParser.parse("https://x.test/a[b]")?.value, "https://x.test/a[b]")
  }

  func testBreaksOnUnicodeWhitespace() {
    // 🔴 두 엔진의 `\s` 가 달라서 명시한 `\p{Z}` 가 실제로 먹는지 본다. 안드로이드(자바)는 ASCII
    // 전용이라 이 둘에서 안 끊겼다 — 같은 공유 문자열로 플랫폼 결과가 갈렸다(2026-08-05 리뷰).
    // 눈에 안 보이는 문자라 코드포인트로 만든다.
    let nbsp = "\u{00A0}"
    let ideographic = "\u{3000}"

    XCTAssertEqual(
      ShareContentParser.parse("돼지통\(nbsp)https://naver.me/52aGF4S5\(nbsp)추가설명")?.value,
      "https://naver.me/52aGF4S5")
    XCTAssertEqual(
      ShareContentParser.parse("링크\(ideographic)https://naver.me/x\(ideographic)끝")?.value,
      "https://naver.me/x")
  }

  func testKeepsQueryAndFragment() {
    // 인스타 공유가 붙이는 ?igsh= 같은 추적 파라미터를 잘라내면 안 된다(크롤러가 알아서 다룬다).
    let shared = "영상 https://www.youtube.com/watch?app=desktop&v=dQw4w9WgXcQ&t=30s"

    XCTAssertEqual(
      ShareContentParser.parse(shared)?.value,
      "https://www.youtube.com/watch?app=desktop&v=dQw4w9WgXcQ&t=30s")
  }

  func testRejectsNonHTTPURLSchemes() {
    // ⚠️ **여기만 안드로이드와 다르다.** 안드로이드는 이걸 텍스트로 등록하고, iOS 는 nil 을 줘서
    // 호출부가 다음 provider 로 넘어간다. iOS 만 provider 가 file:// 를 건네줄 수 있어서다 —
    // 로컬 파일 경로를 텍스트인 척 등록하지 않는다(기존 계약, 이번 변경으로도 유지).
    XCTAssertNil(ShareContentParser.parse("file:///tmp/secret.txt"))
    XCTAssertNil(ShareContentParser.parse("ftp://example.com/file.zip"))
  }

  func testRejectsEmptyValues() {
    XCTAssertNil(ShareContentParser.parse("   "))
    XCTAssertNil(ShareContentParser.parse(nil))
  }
}
