import 'package:app/design/theme.dart';
import 'package:app/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('timePickerTheme', () {
    // M3 기본은 seed 파생 톤(핑크빛)을 쓴다 — datePickerTheme와 같은 이유로 눌러야 한다.
    final theme = AppTheme.light.timePickerTheme;

    test('배경·다이얼 배경·다이얼 손잡이는 토큰 색이다(분홍빛 아님)', () {
      expect(theme.backgroundColor, AppColors.surface);
      expect(theme.dialBackgroundColor, AppColors.surfaceSoft);
      expect(theme.dialHandColor, AppColors.primary);
    });

    test('선택된 시/분 칩은 primary, 선택 안 된 칩은 surfaceSoft다', () {
      final selected = {WidgetState.selected};
      final unselected = <WidgetState>{};
      final hourMinuteColor = theme.hourMinuteColor as WidgetStateColor?;
      expect(hourMinuteColor?.resolve(selected), AppColors.primary);
      expect(hourMinuteColor?.resolve(unselected), AppColors.surfaceSoft);
    });

    test('선택된 오전/오후 칩은 primary, 선택 안 된 칩은 surface다', () {
      final selected = {WidgetState.selected};
      final unselected = <WidgetState>{};
      final dayPeriodColor = theme.dayPeriodColor as WidgetStateColor?;
      expect(dayPeriodColor?.resolve(selected), AppColors.primary);
      expect(dayPeriodColor?.resolve(unselected), AppColors.surface);
    });
  });
}
