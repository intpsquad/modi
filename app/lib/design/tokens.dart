import 'package:flutter/material.dart';

/// 색상 토큰 — specs/design.md §2 (v4: Airbnb 디자인 철학). 하드코딩 색 대신 반드시 여기를 참조한다.
class AppColors {
  AppColors._();

  // 브랜드 / 강조 — 화면당 강조색은 primary 하나만.
  static const primary = Color(0xFFFF385C);
  static const primaryActive = Color(0xFFE00B41);
  static const primaryDisabled = Color(0xFFFFD1DA);
  static const onPrimary = Color(0xFFFFFFFF);

  // 표면 — canvas와 surface가 같은 흰색이므로 계층은 border 헤어라인으로만 만든다.
  static const canvas = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFF7F7F7);
  static const surfaceStrong = Color(0xFFF2F2F2);

  // 텍스트 — 순수 검정은 쓰지 않는다.
  static const foreground = Color(0xFF222222);
  static const foregroundSoft = Color(0xFF3F3F3F);
  static const muted = Color(0xFF6A6A6A);
  static const mutedSoft = Color(0xFF929292);
  // 완료된 투두 — 연회색 텍스트만으로 흐리게(2026-08-08, 취소선 없음).
  static const completedTodo = Color(0xFFB0B0B0);

  // 구분선 / 테두리
  static const border = Color(0xFFDDDDDD);
  static const borderSoft = Color(0xFFEBEBEB);
  static const borderStrong = Color(0xFFC1C1C1);

  // 의미색 — 강조색과 혼용 금지.
  static const accentDanger = Color(0xFFC13515);
  // Figma 정의값 그대로. 값은 파란색이나 이름은 success로, 색-이름이 어긋나 있음(2026-08-01 Figma 동기화).
  static const accentSuccess = Color(0xFF0068FF);
  static const accentWarningBackground = Color(0xFFFFF2D9);
  static const accentWarningText = Color(0xFFB5720A);
  static const scrim = Color(0x80000000); // #000000 @ 50%

  // AI 그라데이션 — AI 생성물(요약·추천·자동 태깅) 표식 전용 컬러칩.
  // 단색으로 쓰지 않는다(두 색을 그라데이션 양 끝으로만 쓴다).
  static const aiGradientStart = Color(0xFF61FFE5);
  static const aiGradientEnd = Color(0xFFFF7BF8);

  // 소셜 로그인 브랜드 색 (로그인 버튼 전용 — 화면 강조색과 혼용 금지)
  static const kakao = Color(0xFFFEE500);
  static const kakaoText = Color(0xFF000000);
  static const kakaoLabel = Color(0xD9000000);
  static const naver = Color(0xFF03C75A);
  static const naverText = Color(0xFFFFFFFF);
  static const googleBorder = Color(0xFFDADCE0);
  static const apple = Color(0xFF000000);
  static const appleText = Color(0xFFFFFFFF);
}

/// 스페이싱 토큰 — specs/design.md §4. 4px 기반, 2px 마이크로 스텝.
class AppSpacing {
  AppSpacing._();

  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const base = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// 화면 좌우 여백 (= base)
  static const content = base;

  /// 카드 사이 간격 (= md)
  static const cardGap = md;
}

/// 라운드 토큰 — specs/design.md §4. 하드 코너는 화면 그리드 외에 쓰지 않는다.
class AppRadius {
  AppRadius._();

  static const xs = 4.0;

  /// 작은 아이템 카드(예: 홈 주간달력 일정 카드).
  static const small = 8.0;
  static const control = 16.0;
  static const card = 16.0;
  static const sheet = 20.0;

  /// 플로팅 하단 네비 바 상단 좌우 라운드(하단 0).
  static const navBar = 24.0;

  /// 히어로 위로 올라오는 흰 바디 시트 상단 좌우 라운드(하단 0).
  static const bodySheet = 30.0;

  /// 완전 pill — 뱃지·칩·아바타·원형 아이콘 버튼.
  static const pill = 9999.0;
}

/// 엘리베이션 — specs/design.md §5. 티어는 flat과 float 둘뿐이다.
class AppElevation {
  AppElevation._();

  /// 실제로 떠 있는 요소(바텀시트·드롭다운·플로팅 뱃지·하단 고정 CTA)에만.
  static const float = <BoxShadow>[
    BoxShadow(color: Color(0x05000000), blurRadius: 0, spreadRadius: 1),
    BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x1A000000), blurRadius: 8, offset: Offset(0, 4)),
  ];

  /// 플로팅 하단 네비 바 — 위쪽으로 은은한 그림자(스크롤 콘텐츠와 분리). 0 -4 12 @ 6%.
  static const navBar = <BoxShadow>[
    BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, -4)),
  ];

  /// [float] 을 **Material 의 숫자 elevation 으로 근사한 값.**
  ///
  /// ⚠️ design.md §5 는 "점진적 엘리베이션 단계(1dp/2dp/4dp…)는 만들지 않는다"고 못 박는다 —
  /// 이 값은 그 단계표가 아니라 **[float] 을 못 쓰는 위젯을 위한 단 하나의 대체값**이다.
  /// `PopupMenu` 처럼 `BoxShadow` 리스트를 못 받고 숫자만 받는 Material 위젯에서만 쓴다.
  /// [float] 의 가장 강한 층(`0 4 8 @10%`)에 가깝게 잡았고, 헤어라인(`border` 1px)을 함께 둬서
  /// 흰 배경 위에서 경계가 그림자에만 의존하지 않게 한다.
  ///
  /// **새 단계를 추가하지 말 것** — 필요해지면 그 위젯이 [float] 을 받을 수 있는지 먼저 본다.
  /// 미결 항목은 `specs/OPEN.md`.
  static const floatMaterial = 3.0;
}

/// 타이포그래피 토큰 — specs/design.md §3. 앱 전역 폰트 = Pretendard(SIL OFL, `app/fonts/`).
/// 굵기 800은 쓰지 않는다 — 위계는 굵기가 아니라 크기·색·여백으로 만든다.
class AppTypography {
  AppTypography._();

  /// 앱 전역 폰트 패밀리. pubspec.yaml `fonts:` · theme.dart와 동일해야 한다.
  static const fontFamily = 'Pretendard';

  /// 홈 히어로 D-day 전용 — "단 하나의 큰 순간"(design.md §3). 다른 곳에서 쓰지 않는다.
  /// 2026-08-07: 56→48로 축소(요청).
  static const displayDday = TextStyle(
    fontFamily: fontFamily,
    fontSize: 48,
    fontWeight: FontWeight.w700,
    height: 1.1,
    color: AppColors.foreground,
  );

  /// 화면당 최대 한 곳 — 온보딩 타이틀, 초대코드.
  static const displayHero = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.foreground,
  );
  static const display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.foreground,
  );
  static const section = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.foreground,
  );
  static const title = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: AppColors.foreground,
  );
  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.foreground,
  );
  static const bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    color: AppColors.muted,
  );
  static const button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  );
  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.25,
    color: AppColors.muted,
  );
  static const badge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.foreground,
  );

  /// 초대 코드 표시 전용 — Jalnan2 디스플레이 폰트(Pretendard 단일 원칙의 유일 예외).
  /// 사용처: S-10-A 초대 코드 공유 카드의 코드 텍스트.
  static const inviteCode = TextStyle(
    fontFamily: 'Jalnan2',
    fontSize: 28,
    height: 1.1,
    letterSpacing: 2,
    color: AppColors.foreground,
  );
}
