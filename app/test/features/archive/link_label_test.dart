import 'package:app/features/archive/link_label.dart';
import 'package:flutter_test/flutter_test.dart';

/// S-25-B 링크 표시 라벨 — 2026-08-05 요청:
/// "https://docs.example.com/guide/main/index.do#none 이거라고 치면 docs.example까지만 보이는
///  형태로 앞뒤로 불필요한 거 제거하고 두 줄로 되지 않도록".
void main() {
  test('스킴·경로·쿼리·프래그먼트와 TLD를 떼고 호스트만 남긴다', () {
    expect(
      shortenLinkLabel('https://docs.example.com/guide/main/index.do#none'),
      'docs.example',
    );
  });

  test('경로가 없어도 같은 규칙이다', () {
    expect(shortenLinkLabel('https://github.com'), 'github');
    expect(shortenLinkLabel('http://sample.com/'), 'sample');
  });

  test('www는 떼고 나머지 서브도메인은 남긴다', () {
    expect(shortenLinkLabel('https://www.naver.com/search?q=1'), 'naver');
    expect(shortenLinkLabel('https://blog.naver.com/x'), 'blog.naver');
  });

  test('co.kr 같은 2단 접미도 함께 떼어낸다', () {
    expect(shortenLinkLabel('https://blog.naver.co.kr/x'), 'blog.naver');
    expect(shortenLinkLabel('https://www.sample.co.kr'), 'sample');
  });

  test('호스트가 한 조각뿐이면 그대로 둔다', () {
    // localhost처럼 뗄 TLD가 없으면 지우면 빈 문자열이 된다 — 그럴 땐 원래 호스트.
    expect(shortenLinkLabel('http://localhost:8080/a'), 'localhost');
  });

  test('대문자 호스트는 소문자로 정규화한다', () {
    expect(shortenLinkLabel('https://DOCS.EXAMPLE.COM/main'), 'docs.example');
  });

  test('파싱할 수 없거나 호스트가 없으면 원문을 트림해 보여준다', () {
    expect(shortenLinkLabel('  그냥 문자열  '), '그냥 문자열');
    expect(shortenLinkLabel(''), '');
  });
}
