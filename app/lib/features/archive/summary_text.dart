/// AI 요약을 **문장마다 한 줄**로 끊어 보여주기 위한 순수 함수(S-25-B, 2026-08-08).
///
/// ## 왜 서버가 아니라 앱인가
///
/// 요약 서식은 원래 프롬프트에서 `\n`을 받기로 했다가 **실측으로 뒤집혔다**
/// (`ai/docs/EXPERIMENTS.md` #33). `gpt-5.4-nano`에 "문장이 끝나면 줄바꿈을 넣어라"를 넣고
/// 픽스처 15건을 두 번 재보니 **7/15 · 8/15만 지켰고**, 어길 때는 예외 없이 통째로 한 줄이었다.
/// 규칙을 얹은 대가로 어투가 명령형·존댓말로 이탈하기도 했다(v4 동결본은 0/15건).
/// *(강조 규칙까지 얹은 조건에서는 계정명 유출까지 났다 — 그건 이 줄바꿈 규칙이 아니라 강조
/// 조건의 결과다. #33 ②③ 참고.)*
///
/// 여기서 나누면 **100% 확정적**이고, 프롬프트를 안 건드리므로 그 회귀가 아예 없다. 이미 등록된
/// 자료도 다시 요약할 필요 없이 그 자리에서 고쳐진다(재요약 백필은 크레딧이 든다).
///
/// ## 왜 "임의 추정"이 아닌가
///
/// 요약 프롬프트가 **평서문(`~한다`, `~다`)을 못 박고** 있어서 문장 경계가 문법으로 정해진다
/// (`OpenAiSummaryClient.SYSTEM_PROMPT`). 동결 픽스처 15건의 종결 부호는 **마침표 50개뿐**이고
/// `!`·`?`는 하나도 없었다. 즉 여기서 하는 것은 마크다운 추정이 아니라 **보증된 문법을 읽는 것**이다.
library;

/// 문장 종결 후보 — 마침표류 **뒤에 공백이나 문자열 끝이 오는** 자리.
///
/// 뒤를 보는 이유는 `3.5`처럼 숫자 안의 마침표를 후보에서 빼기 위해서다.
final RegExp _terminator = RegExp(r'[.!?](?=\s|$)');

/// 요약을 문장 단위로 끊는다. 원문의 글자는 하나도 바꾸지 않고 **경계만 찾는다.**
///
/// 빈 문자열이나 공백뿐이면 빈 목록을 준다 — 호출자가 "요약 없음"과 같게 다룰 수 있다.
List<String> splitSummarySentences(String summary) {
  final text = summary.trim();
  if (text.isEmpty) return const [];

  final sentences = <String>[];
  var start = 0;
  for (final match in _terminator.allMatches(text)) {
    if (_isNotSentenceEnd(text, match.end)) continue;
    final sentence = text.substring(start, match.end).trim();
    if (sentence.isNotEmpty) sentences.add(sentence);
    start = match.end;
  }
  final tail = text.substring(start).trim();
  if (tail.isNotEmpty) sentences.add(tail);
  return sentences;
}

/// 숫자·마침표로만 이뤄진 어절 — 목록 번호(`1.`)와 날짜(`2026.08.08.`)가 여기 걸린다.
final RegExp _numericWord = RegExp(r'^[0-9.]+$');

/// [end] 에서 끝나는 마침표가 **문장 종결이 아닌가** — 그렇다면 여기서 끊으면 안 된다.
///
/// 종결 어미 목록을 열거하지 않는다. 그러면 목록에 없는 어미에서 조용히 틀리기 때문이다 —
/// 동결 픽스처에도 `~보자.`처럼 `다`로 끝나지 않는 문장이 1건 있다(`008_fashion_shoulder`).
/// 대신 **끊으면 안 되는 두 모양**만 지목한다.
///
/// ① 🔴 **낱자 약어** — 운영 데이터에 실제로 있다. 게시물 제목의 감탄사 `드.디.어.` 가 요약
/// 중간에 나오는데(`010_jeongcheogi_lion`) 그 마지막 마침표 뒤에 공백이 온다. 안 막으면
/// *"이에 따라 드.디.어."* / *"정보처리기사 실기 요약노트도 출시될 예정이다."* 로 **한 문장이
/// 두 줄로 찢어진다.**
///
/// ② **숫자 어절** — 목록 번호 `1.` 과 날짜 `2026.08.08.`. 프롬프트가 `목록 기호 절대 금지`·
/// `날짜 및 시간 제외` 를 걸고 있지만 **100% 가 아니다**: 같은 실험에서 v4 요약에 날짜가 남아
/// 있는 것을 봤다(`ai/docs/EXPERIMENTS.md` #33 ⑧). 이쪽은 ①과 달리 **깨진 문장이 화면에
/// 그대로 보이므로**(`리스트는 1.` / `김밥 2.`) 막아 둔다.
///
/// ⚠️ **"마침표가 하나라도 더 있으면 약어"로 두면 안 된다.** 처음에 그렇게 썼다가 `3.5배다.`·
/// `blog.naver.com이다.`·`좋았다...` 같은 **정상 문장이 다음 문장과 통째로 붙었다**(리뷰 지적).
/// 그래서 ①은 "점으로 나눈 조각이 **전부 한 글자**"일 때로 좁힌다.
bool _isNotSentenceEnd(String text, int end) {
  var wordStart = end - 1;
  while (wordStart > 0 && !_isWhitespace(text[wordStart - 1])) {
    wordStart--;
  }
  // 마침표 자신(end - 1)은 빼고 그 앞쪽만 본다.
  final core = text.substring(wordStart, end - 1);
  if (core.isEmpty) return false;
  if (_numericWord.hasMatch(core)) return true;
  if (!core.contains('.')) return false;
  return core.split('.').every((part) => part.length == 1);
}

/// `String.trim()` 과 같은 기준으로 공백을 본다 — 손으로 목록을 만들면 ` ` 같은 것이
/// 빠져 어절 경계가 어긋난다(리뷰 지적).
bool _isWhitespace(String char) => char.trim().isEmpty;
