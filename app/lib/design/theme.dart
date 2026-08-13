import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// specs/design.md 토큰을 ThemeData로 코드화. 다크모드는 MVP 확정상 라이트만 제공한다.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      surface: AppColors.surface,
      error: AppColors.accentDanger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.canvas,
      // 하위 페이지는 **오른쪽에서 왼쪽으로** 밀려 들어오고, **왼쪽 끝을 잡고 오른쪽으로
      // 끌면 뒤로** 간다(2026-08-05 요청). Cupertino 전환 빌더가 두 동작을 함께 준다 —
      // 안드로이드 기본(Zoom)에는 엣지 백 제스처가 없어 플랫폼 구분 없이 이걸 쓴다.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
        },
      ),
      // 뒤로가기 아이콘은 `<`(chevron) — 플랫폼 기본(`←` / `arrow_back_ios_new`)을 덮는다.
      // AppBar 기본 뒤로가기와 BackButton 위젯 전부에 적용된다.
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (context) =>
            const Icon(Icons.chevron_left, size: 28),
      ),
      fontFamily: AppTypography.fontFamily, // 앱 전역 Pretendard (design.md §3).
      textTheme: const TextTheme(
        displayLarge: AppTypography.displayHero,
        displayMedium: AppTypography.display,
        titleLarge: AppTypography.section,
        titleMedium: AppTypography.title,
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.bodySmall,
        labelLarge: AppTypography.button,
        labelMedium: AppTypography.caption,
        labelSmall: AppTypography.badge,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.section,
      ),
      // 카드는 캔버스와 같은 흰색 — 그림자 없이 헤어라인 1px로만 계층을 만든다 (design.md §5).
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              disabledBackgroundColor: AppColors.primaryDisabled,
              disabledForegroundColor: AppColors.onPrimary,
              elevation: 0,
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              textStyle: AppTypography.button,
            ).copyWith(
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return AppColors.primaryDisabled;
                }
                if (states.contains(WidgetState.pressed)) {
                  return AppColors.primaryActive;
                }
                return AppColors.primary;
              }),
            ),
      ),
      // Secondary는 ink 아웃라인 — primary 아웃라인이 아니다 (design.md §6).
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: AppColors.foreground,
              disabledForegroundColor: AppColors.mutedSoft,
              backgroundColor: AppColors.surface,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              textStyle: AppTypography.button,
            ).copyWith(
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return const BorderSide(color: AppColors.borderStrong);
                }
                return const BorderSide(color: AppColors.foreground);
              }),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.foreground,
          textStyle: AppTypography.button,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: AppTypography.body.copyWith(color: AppColors.muted),
        // 라벨은 항상 muted — 상태(에러 등)는 테두리 색이 아니라 하단 안내 텍스트로만
        // 표현한다(입력창 소음 최소화, design.md §6). 라벨도 에러 시 빨강으로 바꾸지 않는다.
        labelStyle: const TextStyle(color: AppColors.muted),
        floatingLabelStyle: const TextStyle(color: AppColors.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        // 테두리는 기본/포커스만 색을 구분한다(에러·성공에도 색을 안 바꾼다).
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        // 포커스 = borderStrong(#C1C1C1) 1px. 기본(#DDDDDD)에서 한 톤만 진해진다.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        // 에러 상태도 테두리는 회색 유지(빨강 아님) — 경고는 아래 errorStyle 텍스트로만.
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.borderStrong),
        ),
        errorStyle: AppTypography.bodySmall.copyWith(
          color: AppColors.accentDanger,
        ),
        // 긴 에러 문구(예: "영문, 숫자, 특수문자를 조합해 8자 이상 입력해 주세요")가
        // 좁은 화면에서 한 줄에 잘리지 않고 줄바꿈되도록 최대 2줄 허용(기본값 1).
        errorMaxLines: 2,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: AppColors.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sheet),
        ),
      ),
      // 날짜 피커 — M3 기본은 primary(핫핑크) seed를 배경에 tint로 깔아 분홍빛이 된다.
      // 흰 배경 + tint 제거로 눌러 깔끔하게, 모서리는 넉넉히 둥글게. 선택/오늘만 primary.
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.surface,
        headerForegroundColor: AppColors.foreground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.bodySheet),
        ),
        dayShape: const WidgetStatePropertyAll(CircleBorder()),
        todayForegroundColor: const WidgetStatePropertyAll(AppColors.primary),
        todayBorder: const BorderSide(color: AppColors.primary),
      ),
      // 시간 피커 — datePickerTheme와 같은 이유(M3 기본 seed tint가 분홍빛). 다이얼 배경은
      // surfaceSoft, 선택된 시/분·오전·오후 칩만 primary, 나머지는 흰 배경으로 눌렀다.
      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.surface,
        dialBackgroundColor: AppColors.surfaceSoft,
        dialHandColor: AppColors.primary,
        dialTextColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.onPrimary;
          return AppColors.foreground;
        }),
        entryModeIconColor: AppColors.muted,
        hourMinuteColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.surfaceSoft;
        }),
        hourMinuteTextColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.onPrimary;
          return AppColors.foreground;
        }),
        dayPeriodColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.surface;
        }),
        dayPeriodTextColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.onPrimary;
          return AppColors.foreground;
        }),
        dayPeriodBorderSide: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.bodySheet),
        ),
      ),
      // 드롭다운/메뉴 — design.md §5 는 이걸 float 티어(떠 있는 요소)로 분류한다.
      //
      // ⚠️ **`AppElevation.float` 를 그대로 못 쓴다.** 그 토큰은 BoxShadow 3장인데 Material 의
      // PopupMenu 는 숫자 elevation 만 받는다. 그래서 근사값을 **토큰으로** 뒀다
      // (`AppElevation.floatMaterial` — 생 숫자를 여기 두면 design.md §5 가 금지한 "점진적 단계"가
      // 코드에 생긴다, 2026-08-04 리뷰 P2-8). flat 티어의 헤어라인(`border` 1px + `radius.card`)을
      // 함께 둬서 흰 배경 위 경계가 그림자에만 의존하지 않게 한다.
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.floatMaterial,
        // 그림자 색도 토큰의 `rgba(0,0,0,·)` 을 따른다 — `foreground`(#222222)는 미묘하게 다르다.
        shadowColor: const Color(0xFF000000),
        textStyle: AppTypography.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.canvas,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.muted,
        elevation: 0,
      ),
      // 플로팅 네비 — 배경/그림자/라운드는 AppShell의 컨테이너가 담당(투명 처리).
      // 활성 primary+w600, 비활성 muted+w400 (design.md §6).
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        // 탭을 눌러도 배경에 클릭 색(리플/하이라이트)이 안 보이게 한다.
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return AppTypography.caption.copyWith(
            color: selected ? AppColors.primary : AppColors.muted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          );
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceSoft,
      ),
      // 토글(Switch) — **켜짐은 M3 기본 유지**(primary 트랙 + 흰 thumb), **꺼짐만 커스텀**
      // (2026-08-08): 흰 배경 + 연한 회색(`border-strong`) 테두리, thumb도 같은 연한 회색이며
      // 켜졌을 때 흰 thumb와 **같은 크기(24dp)**. M3는 꺼짐 thumb를 16dp로 작게 그리므로,
      // 비선택 상태에 **투명 thumbIcon**을 넣어 24dp로 키운다(아이콘은 크기만 강제, 보이지 않음).
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.surface;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return AppColors.borderStrong;
        }),
        trackOutlineWidth: const WidgetStatePropertyAll(2),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.onPrimary;
          return AppColors.borderStrong;
        }),
        thumbIcon: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return null;
          return const Icon(Icons.circle, color: Colors.transparent);
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }
}
