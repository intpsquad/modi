package com.nomara.modi.server.domain.archive.client;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

/**
 * HTML 안 JSON 선형 스캐너. 정규식을 안 쓰는 이유(1.28MB 페이지에서 {@code StackOverflowError})는 {@link JsonScan} 주석에
 * 있다.
 *
 * <p>여기 있는 케이스는 대부분 <b>조용히 틀린 값을 내는</b> 종류다 — 예외가 안 나고 등록도 성공해서, 테스트가 없으면 아무도 모른다.
 */
class JsonScanTest {

  @Nested
  class ObjectAfter {

    @Test
    void itCutsTheBalancedObjectSoNeighbouringEntitiesAreNotRead() {
      // 네이버 장소 페이지가 정확히 이 모양이다 — PlaceDetailBase 바로 뒤에 Menu 가 붙어 있고
      // 둘 다 "name" 을 갖는다. 경계를 안 두면 편의시설 없는 가게에서 메뉴 이름을 집는다.
      String text = "{\"A:1\":{\"name\":\"가게\"},\"Menu:1\":{\"name\":\"메뉴\"}}";

      String entity = JsonScan.objectAfter(text, "\"A:1\"");

      assertThat(entity).isEqualTo("{\"name\":\"가게\"}");
      assertThat(JsonScan.stringValue(entity, "name")).isEqualTo("가게");
    }

    @Test
    void bracesInsideStringsDoNotBreakTheBoundary() {
      // 네이버의 `road`(길안내)에 중괄호가 들어간 적이 있다. 문자열 안을 세면 경계가 무너진다.
      String text = "{\"A\":{\"road\":\"입구 {오른쪽} 계단\",\"name\":\"가게\"},\"B\":{}}";

      assertThat(JsonScan.stringValue(JsonScan.objectAfter(text, "\"A\""), "name")).isEqualTo("가게");
    }

    @Test
    void anUnclosedObjectYieldsNothingRatherThanHalf() {
      // 페이지가 크기 상한에 잘린 경우. 반토막을 쓰면 남은 필드를 주워 담는다.
      assertThat(JsonScan.objectAfter("{\"A\":{\"name\":\"가게\"", "\"A\"")).isEmpty();
    }

    @Test
    void aMissingAnchorYieldsNothing() {
      assertThat(JsonScan.objectAfter("{\"B\":{}}", "\"A\"")).isEmpty();
    }
  }

  @Nested
  class StringValue {

    @Test
    void aNestedObjectWithTheSameKeyIsNotMistakenForTheTopLevelOne() {
      // 🔴 2026-08-05 리뷰가 잡은 것. 깊이를 안 세면 INNER 를 집는다 — 그리고 **아무 경고도 안 뜬다.**
      String text = "{\"sub\":{\"name\":\"INNER\"},\"name\":\"OUTER\"}";

      assertThat(JsonScan.stringValue(text, "name")).isEqualTo("OUTER");
    }

    @Test
    void aNestedArrayWithTheSameKeyIsSkippedToo() {
      String text = "{\"list\":[{\"name\":\"INNER\"}],\"name\":\"OUTER\"}";

      assertThat(JsonScan.stringValue(text, "name")).isEqualTo("OUTER");
    }

    @Test
    void escapesAreLeftForJacksonToUnwrap() {
      // 손으로 풀지 않는다(JsonScan 주석 참고) — 이스케이프를 살린 원문을 그대로 준다.
      assertThat(JsonScan.stringValue("{\"a\":\"1\\n2\"}", "a")).isEqualTo("1\\n2");
    }

    @Test
    void anEscapedQuoteDoesNotEndTheValue() {
      assertThat(JsonScan.stringValue("{\"a\":\"그는 \\\"안녕\\\" 했다\"}", "a"))
          .isEqualTo("그는 \\\"안녕\\\" 했다");
    }

    @Test
    void aValueCutOffByTheSizeLimitIsDiscardedNotHalved() {
      assertThat(JsonScan.stringValue("{\"a\":\"반토막", "a")).isEmpty();
    }

    @Test
    void aMissingKeyYieldsNothing() {
      assertThat(JsonScan.stringValue("{\"b\":\"x\"}", "a")).isEmpty();
    }
  }

  @Nested
  class StringArray {

    @Test
    void itReadsEveryElement() {
      assertThat(JsonScan.stringArray("{\"a\":[\"단체 이용 가능\",\"무선 인터넷\"]}", "a"))
          .containsExactly("단체 이용 가능", "무선 인터넷");
    }

    @Test
    void commasAndBracketsInsideElementsAreKept() {
      assertThat(JsonScan.stringArray("{\"a\":[\"쉼,표\",\"닫는]괄호\"]}", "a"))
          .containsExactly("쉼,표", "닫는]괄호");
    }

    @Test
    void aNestedArrayWithTheSameKeyIsNotMistakenForTheTopLevelOne() {
      String text = "{\"sub\":{\"a\":[\"INNER\"]},\"a\":[\"OUTER\"]}";

      assertThat(JsonScan.stringArray(text, "a")).containsExactly("OUTER");
    }

    @Test
    void anArrayOfSomethingElseIsLeftEmptyRatherThanGuessed() {
      // 숫자 배열·객체 배열을 본문에 밀어 넣지 않는다.
      assertThat(JsonScan.stringArray("{\"a\":[1,2]}", "a")).isEmpty();
      assertThat(JsonScan.stringArray("{\"a\":[{\"x\":\"y\"}]}", "a")).isEmpty();
    }

    @Test
    void anEmptyOrMissingArrayYieldsNothing() {
      assertThat(JsonScan.stringArray("{\"a\":[]}", "a")).isEmpty();
      assertThat(JsonScan.stringArray("{\"b\":[\"x\"]}", "a")).isEmpty();
    }

    @Test
    void anUnclosedArrayIsDiscarded() {
      assertThat(JsonScan.stringArray("{\"a\":[\"하나\",\"둘", "a")).isEmpty();
    }
  }
}
