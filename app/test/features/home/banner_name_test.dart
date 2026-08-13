import 'package:app/features/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 라이브 배너 닉네임 6자 컷 — `bannerName` 검증.
void main() {
  test('6자 이하 닉네임은 그대로 둔다', () {
    expect(bannerName('민재'), '민재');
    expect(bannerName('김서연똥깔라'), '김서연똥깔라'); // 정확히 6자
  });

  test('6자를 넘으면 6자까지만 보이고 …를 붙인다', () {
    expect(bannerName('김서연똥깔라밥'), '김서연똥깔라…'); // 7자
    expect(bannerName('가나다라마바사아'), '가나다라마바…');
  });

  test('빈 문자열은 그대로 빈 문자열', () {
    expect(bannerName(''), '');
  });
}
