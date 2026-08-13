import 'package:app/features/archive/summary_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// 문장 분리기 — 지어낸 문자열이 아니라 **동결 픽스처의 실제 요약**으로 잠근다
/// (`ai/evals/data/summaries/`). 그 15건은 `gpt-5.4-nano`가 운영과 같은 프롬프트로 낸 것이라,
/// 여기서 통과하면 화면에 오는 값에서도 통과한다.
void main() {
  group('splitSummarySentences', () {
    test('평서문 네 문장을 네 줄로 끊는다 (001_gangneung_food 실제 요약)', () {
      const summary =
          '강릉 당일치기 맛집 투어 동선을 그대로 따라가도록 기록한다. '
          'KTX로 청량리에서 출발해 강릉에서 식사 3곳, 카페 3곳, 디저트 6곳을 하루에 연속 방문한다. '
          '식사는 최일순 짬뽕순두부, 강문어화횟집 인생물회, 강릉사임당오징어순대 코스로 진행한다. '
          '사근진해변과 경포호를 함께 들러 소품샵도 방문해 일정의 완성도를 높인다.';

      final sentences = splitSummarySentences(summary);

      expect(sentences, hasLength(4));
      expect(sentences.first, '강릉 당일치기 맛집 투어 동선을 그대로 따라가도록 기록한다.');
      expect(sentences.last, '사근진해변과 경포호를 함께 들러 소품샵도 방문해 일정의 완성도를 높인다.');
      // 글자를 바꾸지 않는다 — 경계만 찾는다.
      expect(sentences.join(' '), summary);
    });

    test('🔴 약어 `드.디.어.` 에서 문장을 찢지 않는다 (010_jeongcheogi_lion 실제 요약)', () {
      // 이 가드가 없으면 "이에 따라 드.디.어." / "정보처리기사 …" 로 한 문장이 두 줄이 된다.
      const summary =
          '정처기 필기 요약노트를 찾는 수요가 늘어, 실기 요약노트 제작 여부와 배포 시점에 대한 문의가 많아졌다. '
          '필기 합격 소식을 전한 뒤 실기 공부를 시작하는 사람들이 특히 제작 시기를 궁금해했다. '
          '이에 따라 드.디.어. 정보처리기사 실기 요약노트도 출시될 예정이다. '
          '다수의 문의에 맞춰 배포 시점이 안내될 계획이다.';

      final sentences = splitSummarySentences(summary);

      expect(sentences, hasLength(4));
      expect(sentences[2], '이에 따라 드.디.어. 정보처리기사 실기 요약노트도 출시될 예정이다.');
    });

    test('`~다` 로 끝나지 않는 문장도 제 줄을 갖는다 (008_fashion_shoulder 실제 요약)', () {
      // 종결 어미를 열거하는 방식이었다면 `보자.` 를 놓쳤다.
      const summary =
          '남자의 최대 고민인 어깨는 옷 하나로 커버할 수 있다. '
          '자연스럽게 떨어지는 어깨핏을 선택하면 시각적으로 어깨가 더 넓어 보이는 효과를 줄일 수 있다. '
          '커버가 필요한 사람은 옷 하나로 어깨 고민을 해결해 보자.';

      final sentences = splitSummarySentences(summary);

      expect(sentences, hasLength(3));
      expect(sentences.last, '커버가 필요한 사람은 옷 하나로 어깨 고민을 해결해 보자.');
    });

    test('숫자 안의 마침표에서 끊지 않는다', () {
      // 뒤에 공백이 없어 후보 자체가 아니다 — 그래도 회귀로 잠근다.
      final sentences = splitSummarySentences('평균 3.5배로 늘었다. 다음 분기에도 유지한다.');

      expect(sentences, ['평균 3.5배로 늘었다.', '다음 분기에도 유지한다.']);
    });

    test('🔴 종결 어절 안에 마침표가 있어도 문장은 끊긴다', () {
      // 약어 가드가 "마침표가 하나라도 더 있으면 약어"였을 때 이 셋이 통째로 한 조각이 됐다.
      // 사용자에게 깨진 문장이 보이지는 않지만 개행이 조용히 사라진다.
      expect(splitSummarySentences('평균 3.5배다. 다음 분기에도 유지한다.'), [
        '평균 3.5배다.',
        '다음 분기에도 유지한다.',
      ]);
      expect(splitSummarySentences('출처는 blog.naver.com이다. 다음 문장이다.'), [
        '출처는 blog.naver.com이다.',
        '다음 문장이다.',
      ]);
      expect(splitSummarySentences('정말 좋았다... 다음 문장이다.'), [
        '정말 좋았다...',
        '다음 문장이다.',
      ]);
    });

    test('🔴 목록 번호에서 문장을 끊지 않는다', () {
      // 이쪽은 반대로 **깨진 문장이 화면에 보인다.** 프롬프트가 `목록 기호 절대 금지`를 걸어
      // 두긴 했지만 100%가 아니다 — 같은 실험에서 `날짜 및 시간 제외`가 깨진 것을 봤다(#33 ⑧).
      expect(splitSummarySentences('리스트는 1. 김밥 2. 라면 순이다. 다음 문장이다.'), [
        '리스트는 1. 김밥 2. 라면 순이다.',
        '다음 문장이다.',
      ]);
    });

    test('날짜 표기에서 문장을 끊지 않는다', () {
      expect(splitSummarySentences('오늘은 2026.08.08. 이다. 다음 문장이다.'), [
        '오늘은 2026.08.08. 이다.',
        '다음 문장이다.',
      ]);
    });

    test('문장이 하나면 그대로 한 줄이다', () {
      expect(splitSummarySentences('한 문장뿐이다.'), ['한 문장뿐이다.']);
    });

    test('마침표가 없어도 통째로 한 문장으로 준다', () {
      // 요약이 절단되면(MAX_SUMMARY 500) 종결 부호 없이 끝날 수 있다.
      expect(splitSummarySentences('마침표 없이 끝나는 요약'), ['마침표 없이 끝나는 요약']);
    });

    test('빈 값과 공백뿐인 값은 빈 목록이다', () {
      expect(splitSummarySentences(''), isEmpty);
      expect(splitSummarySentences('   \n  '), isEmpty);
    });

    test('앞뒤 공백을 정리한다', () {
      expect(splitSummarySentences('  첫 문장이다.   둘째 문장이다.  '), [
        '첫 문장이다.',
        '둘째 문장이다.',
      ]);
    });

    test('이미 줄바꿈이 들어 있어도 문장 단위로 다시 정리한다', () {
      // 나중에 프롬프트가 `\n` 을 주게 되어도 이 함수가 이중 개행을 만들지 않는다.
      expect(splitSummarySentences('첫 문장이다.\n둘째 문장이다.'), [
        '첫 문장이다.',
        '둘째 문장이다.',
      ]);
    });

    test('나눈 조각에는 줄바꿈이 남지 않는다', () {
      // 화면은 조각마다 별도 `Text`로 그리고 사이를 6px로 벌린다 — 조각 안에 `\n`이 남으면
      // 그 자리만 행간(24)으로 벌어져 간격이 두 종류가 된다.
      final sentences = splitSummarySentences('첫 문장이다.\n둘째 문장이다. 셋째 문장이다.');

      expect(sentences, hasLength(3));
      expect(sentences.every((s) => !s.contains('\n')), isTrue);
    });
  });
}
