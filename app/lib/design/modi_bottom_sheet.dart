import 'package:flutter/material.dart';

import 'tokens.dart';

/// 앱 공통 바텀시트를 띄운다 — 21곳에 흩어져 있던 `showModalBottomSheet` 보일러플레이트를
/// 한곳으로 모은다.
///
/// - `useRootNavigator: true` — 시트는 항상 하단 네비(GNB) 위(design.md §8).
/// - `isScrollControlled: true` — [ModiBottomSheet]가 자기 높이를 정하므로 항상 필요하다.
///
/// 모양(배경 `surface` + 상단만 `radius.sheet` + scrim)은 `theme.dart`의
/// `bottomSheetTheme`이 그린다 — 여기서 다시 칠하지 않는다.
Future<T?> showModiSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: builder,
  );
}

/// 공통 바텀시트 본문 — specs/design.md §6(바텀시트 규격, 2026-08-05 지정).
///
/// - 높이 **최소 450 / 최대 600**. 단 화면이 낮으면 화면이 이긴다([_screenFraction]).
/// - [child]는 **스크롤**되고 [button]은 **고정**된다. 버튼을 스크롤 안에 두면 내용이 길 때
///   버튼이 화면 밖으로 밀려 저장할 방법이 사라진다(마이그레이션 전 시트들의 실제 문제).
/// - [button]은 시트 바닥에서 **24** 떠 있다(플로팅 — 위에 헤어라인·배경을 두지 않아
///   내용과 분리돼 보인다).
/// - [child] 아래에는 항상 **40** 여백이 있다 — 내용을 끝까지 스크롤해도 마지막 줄이
///   버튼에 붙지 않는다.
/// - 그리퍼 핸들과 [title]은 스크롤되지 않는 고정 영역이다.
class ModiBottomSheet extends StatelessWidget {
  const ModiBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.button,
    this.titleTrailing,
  });

  /// 스크롤되는 시트 내용.
  final Widget child;

  /// 고정 영역 제목(`section`). null이면 제목 줄 자체를 만들지 않는다.
  final String? title;

  /// 제목 우측에 붙이는 위젯(남은 개수 뱃지 등). [title]이 없으면 무시된다.
  final Widget? titleTrailing;

  /// 바닥에 고정되는 액션 버튼. null이면 버튼 영역이 없다.
  final Widget? button;

  static const double minHeight = 450;
  static const double maxHeight = 600;

  /// 낮은 기기에서 [minHeight]를 그대로 밀어붙이면 시트가 화면을 넘는다 — 화면의 이 비율을
  /// 상한으로 한 번 더 깎는다.
  static const double _screenFraction = 0.9;

  /// [child] 아래 여백.
  static const double contentBottomGap = 40;

  /// [button]과 시트 바닥 사이 거리.
  static const double buttonBottomGap = 24;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final available =
        (media.size.height - media.viewInsets.bottom) * _screenFraction;
    // 화면이 낮으면 상한이 하한보다 작아질 수 있다 — 그때는 상한이 이긴다(넘치지 않게).
    final resolvedMax = maxHeight < available ? maxHeight : available;
    final resolvedMin = minHeight < resolvedMax ? minHeight : resolvedMax;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: resolvedMin,
        maxHeight: resolvedMax,
      ),
      // ⚠️ 여기 두 가지가 규격을 지탱한다. 바꿀 때 주의:
      //  ① 스크롤 영역은 `Expanded`(tight)가 아니라 **`Flexible`(loose)** 다. tight면 남는
      //     공간을 무조건 채워 내용이 짧아도 시트가 항상 최대 높이(600)가 된다.
      //  ② 바깥 Column의 자식은 **정확히 둘**(내용 묶음 / 버튼)이고 `spaceBetween`이다.
      //     그래서 남는 공간 전부가 내용과 버튼 **사이**로 가고 버튼이 바닥에 붙는다.
      //     핸들·제목을 이 Column에 직접 넣으면 그 사이도 벌어진다.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SheetHandle(),
                if (title != null)
                  _SheetTitle(title: title!, trailing: titleTrailing),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.content,
                      right: AppSpacing.content,
                      bottom: contentBottomGap,
                    ),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
          if (button != null)
            Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.content,
                right: AppSpacing.content,
                bottom: buttonBottomGap + media.viewInsets.bottom,
              ),
              child: button,
            ),
        ],
      ),
    );
  }
}

/// 그리퍼 핸들 — 시트를 끌어 닫을 수 있다는 어포던스. 마이그레이션 전에는 시트마다 직접
/// 그렸다(폭·색·여백이 조금씩 달랐다).
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(
        top: AppSpacing.md,
        bottom: AppSpacing.content,
      ),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.content,
        right: AppSpacing.content,
        bottom: AppSpacing.content,
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppTypography.section)),
          ?trailing,
        ],
      ),
    );
  }
}
