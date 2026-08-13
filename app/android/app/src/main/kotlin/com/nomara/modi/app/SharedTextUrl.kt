package com.nomara.modi.app

/**
 * 공유 시트로 들어온 텍스트에서 등록할 링크를 뽑는다(S-25-D).
 *
 * 🔴 **왜 필요한가**: 앱들은 URL 만 보내지 않는다. 네이버 지도 공유 버튼은 이렇게 보낸다 —
 *
 *     [네이버지도] 돼지통 역삼2호점 서울 강남구 … https://naver.me/52aGF4S5
 *
 * 원래 코드는 `Patterns.WEB_URL.matcher(text).matches()` 로 **문자열 전체가 URL 인지**를 봤다.
 * 위 텍스트는 거짓이라 `url` 이 아니라 `text` 로 등록됐고, **크롤링이 아예 안 일어났다**
 * (2026-08-05 실측: `crawl_status=DONE · url=(빈칸) · title=[네이버지도] 돼지통…`).
 *
 * ⚠️ **`android.util.Patterns` 를 쓰지 않는다.** 프레임워크 클래스라 JVM 단위 테스트에서 못 부른다
 * (안드로이드 기기 없이 돌려야 규칙을 고정할 수 있다). 그리고 `Patterns.WEB_URL` 은 스킴 없는
 * `naver.me/x` 같은 것도 잡는데, 서버로 보낼 값은 http(s) 로 확정된 편이 낫다.
 *
 * ⚠️ **iOS 에 같은 규칙이 따로 있다**(`ShareContent.swift`). 네이티브 2종이라 공유 코드가 없다 —
 * 규칙의 단일 진실은 `specs/0014-외부-공유-등록.md` 이고, 한쪽을 고치면 다른 쪽도 고쳐야 한다.
 */
object SharedTextUrl {

    /**
     * http/https 로 시작하는 조각. 공백·꺾쇠·따옴표에서 끊는다.
     *
     * 한글이 붙어 와도(`…역삼로 123 https://naver.me/x`) 공백으로 갈리므로 문제없다.
     *
     * 🔴 **`\p{Z}` 와 `\x0B` 가 왜 붙어 있는가** — iOS 와 글자 단위로 같은 집합을 만들기 위해서다.
     * 자바 정규식의 `\s` 는 **ASCII 전용**(` \t\n\x0B\f\r`)이고 iOS 가 쓰는 ICU 의 `\s` 는
     * `[\t\n\f\r\p{Z}]` 다. 그대로 두면 **전각 공백(U+3000)·NBSP(U+00A0) 에서 안드로이드만
     * 안 끊긴다** — 한국어 공유 텍스트에 실제로 나오는 문자다(2026-08-05 리뷰가 실측으로 잡았다:
     * `링크　https://naver.me/x　끝` → 안드로이드는 `https://naver.me/x끝` 을 뽑아 등록이
     * FAILED 로 떨어지고 iOS 는 성공했다). 양쪽에 `\p{Z}`(공백 계열 전부)와 `\x0B`(ICU 의 `\s` 에는
     * 없다)를 명시해 두 집합을 같게 맞춘다.
     *
     * ⚠️ **`\u` 를 문자 그대로 쓰지 말 것**(`\x0B` 를 쓴 이유). 코틀린 raw string 은 이스케이프를
     * 처리하지 않지만, 이 저장소는 자바 주석에서 `\u` 때문에 컴파일이 깨진 전례가 있다.
     */
    private val HTTP_URL = Regex("""https?://[^\s\p{Z}\x0B<>"']+""", RegexOption.IGNORE_CASE)

    /** URL 뒤에 붙어 오는 문장부호. 닫는 괄호류는 [isBalancedCloser] 로 한 번 더 거른다. */
    private val TRAILING = charArrayOf('.', ',', ';', ':', '!', '?', ')', ']', '}', '"', '\'', '»')

    /** 짝을 세어볼 괄호들 — 닫는 문자 → 여는 문자. */
    private val BRACKETS = mapOf(')' to '(', ']' to '[', '}' to '{')

    /**
     * 공유 텍스트에서 등록할 URL. 없으면 `null`(= 텍스트 메모로 등록한다).
     *
     * **여러 개면 마지막 것을 쓴다** — 앱들은 설명을 앞에, 링크를 끝에 붙인다.
     */
    fun extract(sharedText: String?): String? {
        if (sharedText.isNullOrBlank()) return null
        val last = HTTP_URL.findAll(sharedText).lastOrNull() ?: return null
        return trimTrailingPunctuation(last.value).ifBlank { null }
    }

    /**
     * URL 뒤에 문장부호가 붙어 오는 경우를 걷어낸다(`…/x.` · `여기(…/x)`).
     *
     * 🔴 **닫는 괄호는 짝이 맞으면 URL 의 일부로 본다.** 처음엔 무조건 잘랐는데, 그러면
     * `https://en.wikipedia.org/wiki/Cat_(disambiguation)` 같은 **정상 URL 이 조용히 망가진다**
     * (2026-08-05 리뷰가 잡았다). 등록 후에는 앱에서 `url` 을 고칠 수단이 아예 없어 영구 손상이다.
     * 짝을 세면 두 경우가 갈린다:
     *
     * ```
     *   …/Cat_(disambiguation)   → '(' 1개 ')' 1개 → 짝이 맞다  → 그대로 둔다
     *   여기(…/52aGF4S5)          → '(' 0개 ')' 1개 → 짝이 없다 → 잘라낸다
     * ```
     *
     * ⚠️ **iOS 에 같은 함수가 있다**(`ShareContent.swift`). 규칙은 `specs/0014`.
     */
    private fun trimTrailingPunctuation(url: String): String {
        var candidate = url
        while (true) {
            val last = candidate.lastOrNull() ?: break
            if (last !in TRAILING) break
            if (isBalancedCloser(candidate, last)) break
            candidate = candidate.dropLast(1)
        }
        return candidate
    }

    /** 마지막 글자가 닫는 괄호이고, 그 앞에 짝지을 여는 괄호가 충분히 있는가. */
    private fun isBalancedCloser(candidate: String, last: Char): Boolean {
        val opener = BRACKETS[last] ?: return false
        return candidate.count { it == opener } >= candidate.count { it == last }
    }
}
