/// 저장된 링크를 화면에 **짧게** 보여줄 라벨을 만든다 — S-25-B(specs/0010).
///
/// 2026-08-05 요청: `https://docs.example.com/guide/main/index.do#none` 이면 `docs.example`까지만.
/// 앞(스킴)·뒤(경로·쿼리·프래그먼트)를 떼고, 흔한 최상위 도메인도 떼어 한 줄에 들어가게 한다.
/// 여기서 줄이고 화면에서 `maxLines: 1` + 말줄임으로 한 번 더 막는다(두 줄 금지).
///
/// 공용 도메인 목록을 완전히 다루려는 함수가 아니다(그건 public suffix list가 필요하다) —
/// 흔한 형태를 짧게 보여주는 **표시 전용** 규칙이고, 링크를 여는 쪽은 원본 URL을 쓴다.
String shortenLinkLabel(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  if (host.isEmpty) return url.trim();

  final withoutWww = host.startsWith('www.') ? host.substring(4) : host;
  final labels = withoutWww.split('.');
  if (labels.length < 2) return withoutWww;

  labels.removeLast(); // .com / .kr 등 최상위 도메인
  // `co.kr`·`or.kr`처럼 2단으로 된 접미는 한 조각 더 떼야 의미 있는 이름이 남는다.
  const secondLevel = {
    'co',
    'ne',
    'or',
    'go',
    'ac',
    'com',
    'net',
    'org',
    'edu',
    'gov',
  };
  if (labels.length >= 2 && secondLevel.contains(labels.last)) {
    labels.removeLast();
  }

  final label = labels.join('.');
  return label.isEmpty ? withoutWww : label;
}
