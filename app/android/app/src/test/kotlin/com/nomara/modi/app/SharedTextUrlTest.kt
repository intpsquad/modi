package com.nomara.modi.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * 공유 텍스트에서 URL 을 뽑는 규칙(S-25-D). 기기 없이 도는 순수 JVM 테스트다.
 *
 * ⚠️ **CI 는 이 파일을 돌리지 않는다** — `.github/workflows/ci.yml` 의 app 잡은 `flutter analyze`·
 * `flutter test` 만 돌리고 Gradle 유닛테스트는 부르지 않는다. 로컬에서 돌린다:
 * `cd app/android && ./gradlew :app:testDebugUnitTest` (`specs/OPEN.md` 에 CI 공백으로 올림).
 *
 * ⚠️ **iOS 에 같은 규칙이 따로 있다**(`ShareContentTests.swift`). 여기를 고치면 그쪽도 고친다 —
 * 규칙의 단일 진실은 `specs/0014-외부-공유-등록.md`.
 */
class SharedTextUrlTest {

    @Test
    fun `네이버 지도 공유 문자열에서 링크만 뽑는다`() {
        // 🔴 2026-08-05 사용자가 신고한 바로 그 문자열. 이게 이 파일이 존재하는 이유다.
        val shared = "[네이버지도] 돼지통 역삼2호점 서울 강남구 역삼로 123 https://naver.me/52aGF4S5"

        assertEquals("https://naver.me/52aGF4S5", SharedTextUrl.extract(shared))
    }

    @Test
    fun `줄바꿈으로 나뉜 공유 문자열도 된다`() {
        val shared = "[네이버지도] 몽탄\n서울 용산구 백범로99길 50\nhttps://naver.me/FoEJcO1X"

        assertEquals("https://naver.me/FoEJcO1X", SharedTextUrl.extract(shared))
    }

    @Test
    fun `URL 만 온 기존 경우는 그대로다`() {
        // 회귀 방어선 — 유튜브·인스타 공유는 지금까지 이 모양이었고 계속 되어야 한다.
        assertEquals(
            "https://youtu.be/ZVZjJAor15Y",
            SharedTextUrl.extract("https://youtu.be/ZVZjJAor15Y"),
        )
        assertEquals(
            "https://www.instagram.com/p/DZb-UAhz4Iq/?igsh=x",
            SharedTextUrl.extract("https://www.instagram.com/p/DZb-UAhz4Iq/?igsh=x"),
        )
    }

    @Test
    fun `URL 이 없으면 null 이라 텍스트 메모로 등록된다`() {
        assertNull(SharedTextUrl.extract("오늘 회의에서 정한 것 세 가지"))
        assertNull(SharedTextUrl.extract(""))
        assertNull(SharedTextUrl.extract("   "))
        assertNull(SharedTextUrl.extract(null))
    }

    @Test
    fun `여러 개면 마지막 것을 쓴다`() {
        // 앱들은 설명을 앞에, 링크를 끝에 붙인다.
        val shared = "https://example.com/도움말 를 보고 https://naver.me/52aGF4S5 갔어요"

        assertEquals("https://naver.me/52aGF4S5", SharedTextUrl.extract(shared))
    }

    @Test
    fun `스킴이 없으면 뽑지 않는다`() {
        // android.util.Patterns.WEB_URL 은 이런 것도 잡지만, 서버로 보낼 값은 http(s) 로 확정한다.
        assertNull(SharedTextUrl.extract("네이버 지도에서 naver.me/52aGF4S5 확인"))
        assertNull(SharedTextUrl.extract("ftp://example.com/file.zip"))
    }

    @Test
    fun `문장부호가 붙어 와도 걷어낸다`() {
        assertEquals(
            "https://naver.me/52aGF4S5",
            SharedTextUrl.extract("여기 가봐 https://naver.me/52aGF4S5."),
        )
        assertEquals(
            "https://naver.me/52aGF4S5",
            SharedTextUrl.extract("여기(https://naver.me/52aGF4S5)"),
        )
    }

    @Test
    fun `짝이 맞는 괄호는 URL 의 일부다`() {
        // 🔴 2026-08-05 리뷰가 잡은 회귀. 닫는 괄호를 무조건 잘랐더니 위키백과 주소가 조용히
        // 망가졌고, 등록 후에는 앱에서 url 을 고칠 수단이 없어 영구 손상이었다.
        val wiki = "https://en.wikipedia.org/wiki/Cat_(disambiguation)"
        assertEquals(wiki, SharedTextUrl.extract(wiki))
        // 주변에 설명이 있어도 같아야 한다 — "통째로 URL 일 때만" 봐주는 규칙으로는 이게 안 걸린다.
        assertEquals(wiki, SharedTextUrl.extract("참고 $wiki"))
        // 대괄호·중괄호도 같은 규칙.
        assertEquals("https://x.test/a[b]", SharedTextUrl.extract("https://x.test/a[b]"))
    }

    @Test
    fun `전각 공백과 NBSP 에서도 끊는다`() {
        // 🔴 자바 정규식의 `\s` 는 ASCII 전용이라 이 둘에서 안 끊긴다 — iOS(ICU)는 끊는다.
        // 두 네이티브가 같은 값을 서버로 보내야 해서 패턴에 `\p{Z}` 를 명시했다(2026-08-05 리뷰가
        // 실측으로 잡았다: 안드로이드는 `https://naver.me/x끝` 을 뽑아 등록이 FAILED 로 떨어졌다).
        //
        // 눈에 안 보이는 문자라 코드포인트로 만든다 — 소스에서 읽을 수 있어야 한다.
        val nbsp = Char(0x00A0).toString() // NO-BREAK SPACE
        val ideographic = Char(0x3000).toString() // IDEOGRAPHIC SPACE — 한국어 텍스트에 실제로 나온다

        assertEquals(
            "https://naver.me/52aGF4S5",
            SharedTextUrl.extract("돼지통" + nbsp + "https://naver.me/52aGF4S5" + nbsp + "추가설명"),
        )
        assertEquals(
            "https://naver.me/x",
            SharedTextUrl.extract("링크" + ideographic + "https://naver.me/x" + ideographic + "끝"),
        )
    }

    @Test
    fun `쿼리와 프래그먼트는 살린다`() {
        // 인스타 공유가 붙이는 ?igsh= 같은 추적 파라미터를 잘라내면 안 된다(크롤러가 알아서 다룬다).
        assertEquals(
            "https://www.youtube.com/watch?app=desktop&v=dQw4w9WgXcQ&t=30s",
            SharedTextUrl.extract("영상 https://www.youtube.com/watch?app=desktop&v=dQw4w9WgXcQ&t=30s"),
        )
    }
}
