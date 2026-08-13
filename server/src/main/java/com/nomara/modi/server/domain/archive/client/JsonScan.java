package com.nomara.modi.server.domain.archive.client;

import java.util.ArrayList;
import java.util.List;

/**
 * HTML 안에 박힌 JSON 을 <b>선형으로</b> 훑는 스캐너. 크롤러들이 페이지에서 값 몇 개만 뽑을 때 쓴다.
 *
 * <p>🔴 <b>정규식을 쓰면 안 된다.</b> 2026-08-03 에 {@code "key":"((?:\\.|[^"\\])*)"} 로 1.28 MB 유튜브 페이지를 훑다가
 * <b>{@code StackOverflowError}</b> 가 났다 — 자바 정규식은 반복 안의 교대(alternation)를 재귀로 처리해서 긴 입력에서 스택이 터진다.
 * <b>그때 픽스처 테스트 28개는 전부 통과했다</b>(작은 입력에서는 안 드러난다). 네이버 장소 페이지는 609 KB 라 같은 위험 구간이다.
 *
 * <p>여기 있는 것은 전부 <b>되짚지 않는 한 번 훑기</b>다.
 *
 * <p><b>언이스케이프는 하지 않는다.</b> 개행이나 유니코드 이스케이프는 호출부가 Jackson 에 맡긴다({@code objectMapper.readTree("\"" +
 * raw + "\"").asText()}) — 손으로 풀면 유니코드 이스케이프의 네 자리가 16진수가 아닐 때 {@code NumberFormatException} 이 새어
 * 나가는 종류의 사고가 난다(2026-08-03 리뷰 M2).
 *
 * <p>⚠️ <b>이 주석에 역슬래시-u 를 문자 그대로 쓰지 말 것</b> — 자바는 <b>주석 안에서도</b> 그 시퀀스를 유니코드 이스케이프로 처리해서 컴파일이
 * 깨진다(2026-08-05 에 여기서 실제로 한 번 깨뜨렸다).
 *
 * <p>⚠️ {@code InstagramUrlCrawler} 에도 비슷한 {@code between} 이 있지만 아직 옮기지 않았다 — 깨지기 쉬운 크롤러라 무관한 변경과
 * 같은 MR 에 섞지 않는다.
 */
final class JsonScan {

  private JsonScan() {}

  /**
   * {@code needle} 뒤에 처음 나오는 <b>중괄호가 맞는</b> 객체를 통째로 돌려준다. 없으면 빈 문자열.
   *
   * <p><b>왜 객체 단위로 자르는가</b>: 값을 "앵커 뒤에서 처음 나오는 것"으로 뽑으면, <b>그 필드가 없는 문서에서 옆 엔티티의 값을 집는다.</b> 네이버 장소
   * 페이지는 정규화된 엔티티 맵이라 {@code PlaceDetailBase} 바로 뒤에 {@code Menu} 가 붙어 있고, 둘 다 {@code "name"} 을 갖는다
   * — 경계를 안 두면 편의시설 없는 가게에서 메뉴 이름이 주소 자리에 들어간다.
   *
   * <p>문자열 안의 중괄호와 이스케이프된 따옴표를 건너뛴다. 안 그러면 {@code "road":"… {팁} …"} 같은 값 하나에 경계가 무너진다.
   */
  static String objectAfter(String text, String needle) {
    int at = text.indexOf(needle);
    if (at < 0) {
      return "";
    }
    int start = text.indexOf('{', at + needle.length());
    if (start < 0) {
      return "";
    }

    int depth = 0;
    boolean inString = false;
    for (int i = start; i < text.length(); i++) {
      char c = text.charAt(i);
      if (inString) {
        if (c == '\\') {
          i++; // 이스케이프된 다음 글자는 판정에서 건너뛴다
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}' && --depth == 0) {
        return text.substring(start, i + 1);
      }
    }
    // 안 닫힌 채 끝났다 = 페이지가 크기 상한에 잘렸다. 반토막을 쓰지 않는다.
    return "";
  }

  /**
   * 객체의 <b>바로 아래 단계</b>에서 {@code "key":"...값..."} 을 찾아 <b>이스케이프를 살린 채</b> 돌려준다. 없으면 빈 문자열.
   *
   * <p>🔴 <b>왜 깊이를 세는가</b>: 단순히 처음 나오는 {@code "key":"} 를 집으면 <b>중첩 객체 안의 같은 키를 먼저 집는다.</b>
   * 실측({@code {"sub":{"name":"INNER"},"name":"OUTER"}} → {@code INNER}). 네이버 장소의 {@code
   * PlaceDetailBase} 는 {@code name} 앞에 이미 중첩 객체({@code reviewSettings})를 갖고 있어서, 네이버가 거기에 {@code
   * name} 을 추가하는 순간 <b>가게명 자리에 그 값이 조용히 들어간다</b>(앵커는 찾았으므로 경고도 안 뜬다). 2026-08-05 리뷰가 잡았다.
   *
   * <p>값은 여는 따옴표부터 <b>이스케이프되지 않은</b> 닫는 따옴표까지다. 안 닫힌 채 끝나면(= 입력이 잘렸다) 반토막 대신 빈 문자열을 준다.
   */
  static String stringValue(String text, String key) {
    int at = findKeyAtTopLevel(text, "\"" + key + "\":\"");
    return at < 0 ? "" : readString(text, at);
  }

  /**
   * 객체의 <b>바로 아래 단계</b>에서 {@code "key":["a","b"]} 를 찾아 원소들을 <b>이스케이프를 살린 채</b> 돌려준다. 없거나 빈 배열이면 빈
   * 배열.
   *
   * <p>네이버 장소의 {@code microReviews}·{@code conveniences} 가 이 모양이다. 원소가 문자열이 아닌 배열({@code [1,2]}·
   * {@code [{…}]})은 대상이 아니라 빈 배열을 준다 — 추측해서 숫자나 객체를 본문에 넣지 않는다.
   */
  static List<String> stringArray(String text, String key) {
    List<String> out = new ArrayList<>();
    int at = findKeyAtTopLevel(text, "\"" + key + "\":[");
    if (at < 0) {
      return out;
    }

    boolean inString = false;
    int elementStart = -1;
    for (int i = at; i < text.length(); i++) {
      char c = text.charAt(i);
      if (inString) {
        if (c == '\\') {
          i++;
        } else if (c == '"') {
          out.add(text.substring(elementStart, i));
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
        elementStart = i + 1;
      } else if (c == ']') {
        return out;
      } else if (c == '{' || c == '[') {
        // 중첩 구조가 나오면 이 배열은 우리가 다룰 모양이 아니다. 추측하지 않고 비운다.
        out.clear();
        return out;
      }
    }
    // 안 닫힌 채 끝났다 = 잘렸다.
    out.clear();
    return out;
  }

  /**
   * {@code needle} 이 <b>깊이 1</b>(= 바깥 객체의 직속 필드)에 나오는 첫 위치의 <b>값 시작 인덱스</b>. 없으면 {@code -1}.
   *
   * <p>문자열 안의 중괄호·대괄호와 이스케이프된 따옴표를 건너뛴다.
   */
  private static int findKeyAtTopLevel(String text, String needle) {
    int depth = 0;
    boolean inString = false;
    for (int i = 0; i < text.length(); i++) {
      char c = text.charAt(i);
      if (inString) {
        if (c == '\\') {
          i++;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '{' || c == '[') {
        depth++;
      } else if (c == '}' || c == ']') {
        depth--;
      } else if (c == '"') {
        if (depth == 1 && text.startsWith(needle, i)) {
          return i + needle.length();
        }
        inString = true; // 우리 키가 아니면 문자열 전체를 건너뛴다(키든 값이든)
      }
    }
    return -1;
  }

  /** {@code from} 부터 <b>이스케이프되지 않은</b> 닫는 따옴표까지. 안 닫히면 빈 문자열. */
  private static String readString(String text, int from) {
    for (int i = from; i < text.length(); i++) {
      char c = text.charAt(i);
      if (c == '\\') {
        i++;
      } else if (c == '"') {
        return text.substring(from, i);
      }
    }
    return "";
  }
}
