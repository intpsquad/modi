/// 앱 안의 약관·정책 본문과 **웹에 올라간 정적 페이지**가 같은지 검사한다.
///
/// 왜 필요한가: App Store 심사에 **개인정보처리방침 URL**(`https://maramodi.cloud/privacy`)을
/// 등록했다. Apple 은 그 주소의 내용과 앱이 보여주는 내용이 같다고 전제하므로, 한쪽만 고치면
/// 심사에서 지적될 수 있다. 그런데 두 벌은 언어도 저장소 위치도 달라서
/// (`legal_content.dart` ↔ `deploy/site/*.html`) 사람 눈으로는 어긋난 걸 알아챌 방법이 없다.
///
/// 이 테스트가 그 드리프트를 CI 에서 잡는다. **본문을 고칠 때는 두 벌을 함께 고친다** —
/// 단일 진실은 `legal_content.dart` 쪽이다.
///
/// HTML 은 `<p class="body">` 안에 Dart 본문을 **그대로**(`white-space: pre-wrap`) 넣는 규칙이라
/// 파서 없이 정규식으로 비교할 수 있다. 이 규칙이 깨지면 이 테스트도 함께 고쳐야 한다.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/legal/legal_content.dart';

/// `flutter test` 는 `app/` 에서 돈다(CI 의 `working-directory: app`).
/// 정적 페이지는 저장소 루트의 `deploy/site/` 에 있다.
File _sitePage(String fileName) => File('../deploy/site/$fileName');

/// `<h2>…</h2>` 안쪽 문자열을 순서대로 뽑는다.
List<String> _headings(String html) => RegExp(
  r'<h2>(.*?)</h2>',
  dotAll: true,
).allMatches(html).map((m) => m.group(1)!).toList();

/// `<p class="body">…</p>` 안쪽 문자열을 순서대로 뽑는다.
List<String> _bodies(String html) => RegExp(
  r'<p class="body">(.*?)</p>',
  dotAll: true,
).allMatches(html).map((m) => m.group(1)!).toList();

void _expectDocumentMatches(LegalDocument doc, String fileName) {
  final file = _sitePage(fileName);
  expect(
    file.existsSync(),
    isTrue,
    reason: '${file.path} 가 없다. 웹 약관 페이지는 App Store 제출에 필요하다(개인정보처리방침 URL).',
  );

  final html = file.readAsStringSync();
  final headings = _headings(html);
  final bodies = _bodies(html);

  expect(
    headings.length,
    doc.sections.length,
    reason: '$fileName 의 <h2> 개수가 ${doc.title} 의 절 개수와 다르다 — 절이 빠졌거나 더 있다.',
  );
  expect(
    bodies.length,
    doc.sections.length,
    reason: '$fileName 의 <p class="body"> 개수가 ${doc.title} 의 절 개수와 다르다.',
  );

  for (var i = 0; i < doc.sections.length; i++) {
    final section = doc.sections[i];
    expect(
      headings[i],
      section.heading,
      reason: '$fileName ${i + 1}번째 절 제목이 legal_content.dart 와 다르다.',
    );
    expect(
      bodies[i],
      section.body,
      reason: '$fileName "${section.heading}" 본문이 legal_content.dart 와 다르다.',
    );
  }
}

void main() {
  group('웹 약관 페이지가 앱 본문과 일치한다', () {
    test('개인정보 처리방침 (privacy.html)', () {
      _expectDocumentMatches(kPrivacyPolicy, 'privacy.html');
    });

    test('이용약관 (terms.html)', () {
      _expectDocumentMatches(kTermsOfService, 'terms.html');
    });

    test('HTML 에 이스케이프가 필요한 문자가 본문에 없다', () {
      // 지금 본문에는 <, >, & 가 없어서 그대로 넣어도 안전하다. 나중에 들어오면
      // 페이지가 깨지거나 조용히 다르게 렌더된다 — 그때 이스케이프 규칙을 세우라는 신호다.
      for (final doc in [kPrivacyPolicy, kTermsOfService]) {
        for (final section in doc.sections) {
          expect(
            RegExp(r'[<>&]').hasMatch('${section.heading}${section.body}'),
            isFalse,
            reason:
                '"${section.heading}" 에 HTML 특수문자가 생겼다 — '
                'deploy/site/*.html 에 넣을 때 이스케이프가 필요하고 이 테스트도 고쳐야 한다.',
          );
        }
      }
    });

    test('문의 이메일과 시행일이 웹 페이지에도 그대로 있다', () {
      for (final name in ['privacy.html', 'terms.html', 'index.html']) {
        final html = _sitePage(name).readAsStringSync();
        expect(
          html,
          contains(kLegalContactEmail),
          reason: '$name 에 문의 이메일이 없다 — Apple 지원 URL 요건.',
        );
      }
      for (final name in ['privacy.html', 'terms.html']) {
        expect(
          _sitePage(name).readAsStringSync(),
          contains(kLegalEffectiveDate),
          reason: '$name 에 시행일($kLegalEffectiveDate)이 없다.',
        );
      }
    });
  });
}
