import 'package:flutter/material.dart';

import '../../design/line_tabs.dart';
import '../../design/tokens.dart';
import 'legal_content.dart';

/// 약관·정책 페이지 (QA).
///
/// 회원가입 약관 보기(비로그인)와 설정 '약관·정책' 타일(로그인) 양쪽에서 진입한다.
/// 긴 문서라 바텀시트가 아닌 별도 스크롤 페이지로 제공한다(design.md 표면 규칙).
/// 상단 라인 탭(밑줄형)으로 이용약관 ↔ 개인정보 처리방침을 전환한다.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, this.initialDoc = LegalDoc.terms});

  final LegalDoc initialDoc;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late LegalDoc _doc = widget.initialDoc;

  static const _docs = [LegalDoc.terms, LegalDoc.privacy];

  @override
  Widget build(BuildContext context) {
    final document = legalDocumentFor(_doc);
    return Scaffold(
      appBar: AppBar(title: const Text('약관 · 정책')),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.content,
                AppSpacing.sm,
                AppSpacing.content,
                AppSpacing.base,
              ),
              child: LineTabs(
                tabs: [for (final d in _docs) d.label],
                selectedIndex: _docs.indexOf(_doc),
                onChanged: (i) => setState(() => _doc = _docs[i]),
              ),
            ),
            Expanded(
              child: ListView(
                key: ValueKey('legal-body-${_doc.name}'),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.content,
                  0,
                  AppSpacing.content,
                  AppSpacing.xl,
                ),
                children: [
                  Text(document.title, style: AppTypography.section),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '시행일 $kLegalEffectiveDate',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.mutedSoft,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final section in document.sections) ...[
                    Text(section.heading, style: AppTypography.title),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      section.body,
                      style: AppTypography.body.copyWith(
                        color: AppColors.foregroundSoft,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
